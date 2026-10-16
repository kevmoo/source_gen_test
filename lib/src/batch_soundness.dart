import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:cli_util/cli_util.dart';
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';

import 'generate_for_element.dart';

/// Classification of failures caught by [verifyGeneratorBatch].
enum CodegenIssueKind {
  /// [generateForElement] threw an unexpected exception (or an exception that
  /// did not match [CodegenCase.expectedError]).
  generatorException,

  /// [CodegenCase.expectedError] was specified, but [generateForElement]
  /// succeeded without throwing.
  unexpectedSuccess,

  /// `package:analyzer` reported a compile-time error or warning on the
  /// input declarations or generated `.g.dart` part file.
  staticError,

  /// The [CodegenCase.runtimeCheck] snippet threw during `Isolate.spawnUri`
  /// round-trip execution.
  runtimeFailure,
}

/// A single failure caught by [verifyGeneratorBatch].
typedef CodegenIssue = ({
  String caseId,
  CodegenIssueKind kind,
  String message,
  String declarations,
  String? generatedCode,
});

/// Aggregate result returned by [verifyGeneratorBatch].
typedef CodegenBatchReport = ({
  int totalCases,
  int passedCases,
  List<CodegenIssue> issues,
});

/// A single AST/declaration permutation to validate in [verifyGeneratorBatch].
final class CodegenCase {
  /// Unique identifier for this permutation (e.g. `'case_001'`).
  final String id;

  /// Top-level Dart declarations (`@MyAnnotation() class Case001 { ... }`).
  final String declarations;

  /// Optional name of the annotated top-level element in [declarations] to
  /// pass to [generateForElement].
  ///
  /// When `null`, the first top-level `class`, `enum`, `mixin`, `typedef`, or
  /// `extension type` name in [declarations] is extracted automatically.
  final String? elementName;

  /// Optional Dart statements executed inside an `async` block in the batched
  /// `Isolate.spawnUri` runtime oracle.
  final String? runtimeCheck;

  /// When non-null, asserts that [generateForElement] throws an exception
  /// whose string representation matches [expectedError].
  final Pattern? expectedError;

  const CodegenCase({
    required this.id,
    required this.declarations,
    this.elementName,
    this.runtimeCheck,
    this.expectedError,
  });
}

/// Computes the deterministic Cartesian product of named feature [axes].
///
/// Throws an [ArgumentError] if any axis in [axes] has an empty value list.
List<Map<K, V>> cartesianProduct<K, V>(Map<K, List<V>> axes) {
  if (axes.isEmpty) return const [];
  var combinations = <Map<K, V>>[const {}];
  for (final MapEntry(:key, :value) in axes.entries) {
    if (value.isEmpty) {
      throw ArgumentError.value(
        value,
        'axes[$key]',
        'Axis value list must not be empty.',
      );
    }
    combinations = _expandAxis(combinations, key, value);
  }
  return combinations;
}

List<Map<K, V>> _expandAxis<K, V>(
  List<Map<K, V>> current,
  K key,
  List<V> values,
) => [
  for (final prefix in current)
    for (final v in values) {...prefix, key: v},
];

/// Validates a batch of [cases] against [generator] using three oracles in a
/// single shared `package:analyzer` context and a single batched
/// `Isolate.spawnUri` execution:
///
/// 1. **Per-Element Diagnostic & Generation Oracle**: Resolves the combined
///    library once in `AnalysisContextCollection`, wraps it in a
///    [LibraryReader], and calls [generateForElement] individually for each
///    [CodegenCase] inside its own `try` / `catch`. Crashing positive cases and
///    negative [CodegenCase.expectedError] contracts are verified in `O(1)` per
///    element without binary-search bisection or regex snippet slicing.
/// 2. **Static Soundness Oracle**: Assembles `fuzz_batch.dart` and
///    `fuzz_batch.g.dart` with `// === CASE:<id> ===` markers around each
///    surviving case (deduplicating identical shared top-level helper
///    declarations across cases) and feeds both into
///    `AnalysisSession.getErrors` to catch compile-time errors and (when
///    [includeWarnings] is `true`) static warnings such as
///    `invalid_null_aware_operator` or `unnecessary_cast`.
/// 3. **Runtime Round-Trip Oracle**: Executes all surviving
///    [CodegenCase.runtimeCheck] blocks in a single `Isolate.spawnUri`
///    invocation, isolating per-case exceptions so one failing case never masks
///    the rest of the batch.
///
/// Throws a [StateError] detailing all discovered issues when [failOnIssues] is
/// `true` and at least one issue is found.
Future<CodegenBatchReport> verifyGeneratorBatch({
  required Generator generator,
  required List<CodegenCase> cases,
  List<String> imports = const [],
  String preamble = '',
  Map<String, String> auxiliaryFiles = const {},
  String packageRoot = '.',
  String? workDir,
  bool includeWarnings = true,
  bool failOnIssues = true,
  Duration isolateTimeout = const Duration(seconds: 30),
}) async {
  if (cases.isEmpty) {
    return (totalCases: 0, passedCases: 0, issues: const <CodegenIssue>[]);
  }
  final absPkgRoot = p.normalize(p.absolute(packageRoot));
  final pkgConfigFile = _findPackageConfigFile(absPkgRoot);
  final tempWorkDir = _createCodegenWorkDir(absPkgRoot, workDir);
  try {
    final workPkgConfig = _writeWorkDirPackageConfig(
      tempWorkDir.path,
      pkgConfigFile,
    );
    _writeAuxiliaryFiles(tempWorkDir.path, auxiliaryFiles);
    final collection = AnalysisContextCollection(
      includedPaths: [tempWorkDir.path],
      sdkPath: sdkPath,
    );
    final env = (
      context: collection.contextFor(tempWorkDir.path),
      workDir: tempWorkDir.path,
      batchPath: p.join(tempWorkDir.path, 'fuzz_batch.dart'),
      partPath: p.join(tempWorkDir.path, 'fuzz_batch.g.dart'),
      packageConfigUri: p.toUri(workPkgConfig.path),
      imports: imports,
      preamble: preamble,
      includeWarnings: includeWarnings,
      isolateTimeout: isolateTimeout,
    );

    final report = await _executeBatchPipeline(env, generator, cases);
    if (failOnIssues && report.issues.isNotEmpty) {
      throw StateError(formatCodegenBatchReport(report));
    }
    return report;
  } finally {
    _cleanupWorkDir(tempWorkDir);
  }
}

Future<CodegenBatchReport> _executeBatchPipeline(
  _BatchEnv env,
  Generator generator,
  List<CodegenCase> cases,
) async {
  final genStep = await _runPerElementGeneration(env, generator, cases);
  final issues = <CodegenIssue>[...genStep.issues];
  var staticSurvivors = const <CodegenCase>[];
  var runtimePassedIds = const <String>{};

  if (genStep.survivors.isNotEmpty) {
    final staticStep = await _verifyStaticDiagnostics(
      env,
      genStep.survivors,
      genStep.generatedByCaseId,
    );
    staticSurvivors = staticStep.survivors;
    _appendUniqueIssues(issues, staticStep.issues);
    if (staticSurvivors.isNotEmpty) {
      final runtimeStep = await _runBatchedIsolateChecks(
        env,
        staticSurvivors,
        genStep.generatedByCaseId,
      );
      runtimePassedIds = runtimeStep.passedCaseIds;
      _appendUniqueIssues(issues, runtimeStep.issues);
    }
  }

  final verifiedIds = _collectVerifiedCaseIds(
    passedNegativeIds: genStep.passedNegativeIds,
    staticSurvivors: staticSurvivors,
    runtimePassedIds: runtimePassedIds,
    issues: issues,
  );
  return (
    totalCases: cases.length,
    passedCases: verifiedIds.length,
    issues: List<CodegenIssue>.unmodifiable(issues),
  );
}

Set<String> _collectVerifiedCaseIds({
  required Set<String> passedNegativeIds,
  required List<CodegenCase> staticSurvivors,
  required Set<String> runtimePassedIds,
  required List<CodegenIssue> issues,
}) {
  final failedIds = {for (final issue in issues) issue.caseId};
  return <String>{
    ...passedNegativeIds,
    for (final c in staticSurvivors)
      if (!_hasRuntimeCheck(c)) c.id,
    ...runtimePassedIds,
  }..removeAll(failedIds);
}

bool _hasRuntimeCheck(CodegenCase c) =>
    c.runtimeCheck != null && c.runtimeCheck!.trim().isNotEmpty;

typedef _BatchEnv = ({
  AnalysisContext context,
  String workDir,
  String batchPath,
  String partPath,
  Uri packageConfigUri,
  List<String> imports,
  String preamble,
  bool includeWarnings,
  Duration isolateTimeout,
});

int _workDirCounter = 0;

Directory _createCodegenWorkDir(String absPkgRoot, String? explicitWorkDir) {
  _workDirCounter++;
  final stamp = '${DateTime.now().microsecondsSinceEpoch}_$_workDirCounter';
  final baseDir = _resolveBaseWorkDir(absPkgRoot, explicitWorkDir);
  return Directory(p.join(baseDir, 'codegen_$stamp'))
    ..createSync(recursive: true);
}

String _resolveBaseWorkDir(String absPkgRoot, String? explicitWorkDir) {
  if (explicitWorkDir != null && explicitWorkDir.isNotEmpty) {
    return p.normalize(p.absolute(explicitWorkDir));
  }
  final envWorkDir =
      Platform.environment['SOURCE_GEN_TEST_WORK_DIR'] ??
      Platform.environment['FUZZ_WORK_DIR'];
  if (envWorkDir != null && envWorkDir.isNotEmpty) {
    return p.normalize(p.absolute(envWorkDir));
  }
  return p.join(absPkgRoot, '.dart_tool', 'source_gen_test');
}

void _cleanupWorkDir(Directory workDir) {
  final parent = workDir.parent;
  if (workDir.existsSync()) {
    workDir.deleteSync(recursive: true);
  }
  final parentName = p.basename(parent.path);
  if (parent.existsSync() &&
      (parentName == 'source_gen_test' || parentName == 'fuzz') &&
      parent.listSync().isEmpty) {
    parent.deleteSync();
  }
}

File _writeWorkDirPackageConfig(String workDir, File baseConfigFile) {
  final baseConfigDir = p.dirname(baseConfigFile.path);
  final raw =
      jsonDecode(baseConfigFile.readAsStringSync()) as Map<String, Object?>;
  final rawPackages = (raw['packages'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final updatedPackages = [
    for (final entry in rawPackages)
      _absolutizePackageEntry(entry, baseConfigDir),
  ];
  return File(p.join(workDir, '.dart_tool', 'package_config.json'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({...raw, 'packages': updatedPackages}),
    );
}

Map<String, Object?> _absolutizePackageEntry(
  Map<String, Object?> entry,
  String configDir,
) {
  final rootUriStr = entry['rootUri'] as String;
  final parsed = Uri.parse(rootUriStr);
  if (parsed.hasScheme) return entry;
  final absPath = p.normalize(p.join(configDir, p.fromUri(parsed)));
  return {...entry, 'rootUri': p.toUri(absPath).toString()};
}

void _writeAuxiliaryFiles(String workDir, Map<String, String> auxiliaryFiles) {
  for (final MapEntry(:key, :value) in auxiliaryFiles.entries) {
    File(p.join(workDir, key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(value);
  }
}

typedef _GenerationBatchStep = ({
  List<CodegenCase> survivors,
  Set<String> passedNegativeIds,
  Map<String, String> generatedByCaseId,
  List<CodegenIssue> issues,
});

Future<_GenerationBatchStep> _runPerElementGeneration(
  _BatchEnv env,
  Generator generator,
  List<CodegenCase> cases,
) async {
  final initialSource = _buildLibrarySource(
    env: env,
    cases: cases,
    includePartDirective: true,
  );
  final library = await _resolveLibraryAtPath(
    env.context,
    env.batchPath,
    initialSource,
  );
  final sharedReader = LibraryReader(library);
  final survivors = <CodegenCase>[];
  final passedNegativeIds = <String>{};
  final generatedByCaseId = <String, String>{};
  final issues = <CodegenIssue>[];
  final isAnnotatedGen = generator is GeneratorForAnnotation<Object?>;

  for (final c in cases) {
    final elementName = isAnnotatedGen ? _resolveCaseElementName(c) : null;
    final reader = await _readerForCase(
      env,
      sharedReader,
      c,
      elementName,
      isSingleCaseBatch: cases.length == 1,
    );
    final outcome = await _evaluateSingleCase(
      generator,
      reader,
      c,
      elementName,
    );
    _recordCaseGenerationOutcome(
      c: c,
      outcome: outcome,
      survivors: survivors,
      passedNegativeIds: passedNegativeIds,
      generatedByCaseId: generatedByCaseId,
      issues: issues,
    );
  }
  return (
    survivors: survivors,
    passedNegativeIds: passedNegativeIds,
    generatedByCaseId: generatedByCaseId,
    issues: issues,
  );
}

void _recordCaseGenerationOutcome({
  required CodegenCase c,
  required _CaseGenOutcome outcome,
  required List<CodegenCase> survivors,
  required Set<String> passedNegativeIds,
  required Map<String, String> generatedByCaseId,
  required List<CodegenIssue> issues,
}) {
  if (outcome.issue != null) {
    issues.add(outcome.issue!);
    return;
  }
  if (c.expectedError != null) {
    passedNegativeIds.add(c.id);
    return;
  }
  survivors.add(c);
  if (outcome.generatedCode != null) {
    generatedByCaseId[c.id] = outcome.generatedCode!;
  }
}

String _resolveCaseElementName(CodegenCase c) {
  final explicit = c.elementName?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final symbols = _extractDeclaredSymbols(c.declarations);
  if (symbols.isNotEmpty) return symbols.first;
  throw ArgumentError.value(
    c.declarations,
    'declarations',
    'Could not auto-extract a top-level class, enum, mixin, typedef, or '
        'extension type name for case "${c.id}". Provide `elementName`.',
  );
}

Future<LibraryReader> _readerForCase(
  _BatchEnv env,
  LibraryReader sharedReader,
  CodegenCase c,
  String? elementName, {
  required bool isSingleCaseBatch,
}) async {
  if (_canReuseSharedReader(sharedReader, elementName, isSingleCaseBatch)) {
    return sharedReader;
  }
  final singleSource = _buildLibrarySource(
    env: env,
    cases: [c],
    includePartDirective: true,
  );
  final lib = await _resolveLibraryAtPath(
    env.context,
    env.batchPath,
    singleSource,
  );
  return LibraryReader(lib);
}

bool _canReuseSharedReader(
  LibraryReader sharedReader,
  String? elementName,
  bool isSingleCaseBatch,
) {
  if (elementName == null) return isSingleCaseBatch;
  final matchCount = sharedReader.allElements
      .where((e) => e.name == elementName)
      .length;
  return matchCount == 1;
}

typedef _CaseGenOutcome = ({String? generatedCode, CodegenIssue? issue});

Future<_CaseGenOutcome> _evaluateSingleCase(
  Generator generator,
  LibraryReader reader,
  CodegenCase c,
  String? elementName,
) async {
  try {
    final raw = await _invokeCaseGenerator(generator, reader, elementName);
    final trimmed = raw.trim();
    final code = trimmed.isEmpty ? null : trimmed;
    if (c.expectedError != null) {
      return (
        generatedCode: code,
        issue: (
          caseId: c.id,
          kind: CodegenIssueKind.unexpectedSuccess,
          message:
              'Expected generator error matching ${c.expectedError}, '
              'but generation succeeded.',
          declarations: c.declarations,
          generatedCode: code,
        ),
      );
    }
    return (generatedCode: code, issue: null);
  } on Object catch (e, st) {
    if (c.expectedError != null &&
        _matchesPattern(e.toString(), c.expectedError!)) {
      return (generatedCode: null, issue: null);
    }
    final msg = c.expectedError != null
        ? 'Expected error matching ${c.expectedError}, but caught: $e'
        : '$e\n$st';
    return (
      generatedCode: null,
      issue: (
        caseId: c.id,
        kind: CodegenIssueKind.generatorException,
        message: msg,
        declarations: c.declarations,
        generatedCode: null,
      ),
    );
  }
}

Future<String> _invokeCaseGenerator(
  Generator generator,
  LibraryReader reader,
  String? elementName,
) async {
  final Object? rawOutput;
  if (generator is GeneratorForAnnotation<Object?>) {
    final element = _lookupCaseElement(reader, elementName!);
    final annotation = _resolveElementAnnotation(generator, element);
    rawOutput = await generator.generateForAnnotatedElement(
      element,
      ConstantReader(annotation),
      _BatchBuildStep(),
    );
  } else {
    rawOutput = await generator.generate(reader, _BatchBuildStep());
  }
  return _normalizeGeneratorOutput(rawOutput).join('\n\n');
}

Element _lookupCaseElement(LibraryReader reader, String name) {
  final elements = reader.allElements.where((e) => e.name == name).toList();
  if (elements.isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Could not find an element with name `$name`.',
    );
  }
  if (elements.length == 1) return elements.first;
  final rootProperties = elements.whereType<PropertyInducingElement>().toList();
  if (rootProperties.length == 1) return rootProperties.first;
  throw UnimplementedError();
}

DartObject? _resolveElementAnnotation(
  GeneratorForAnnotation<Object?> generator,
  Element element,
) {
  final direct = generator.typeChecker.firstAnnotationOf(
    element,
    throwOnUnresolved: generator.throwOnUnresolved,
  );
  if (direct != null) return direct;
  final checkerName = generator.typeChecker.toString().split(' ').first;
  for (final meta in element.metadata.annotations) {
    final obj = meta.computeConstantValue();
    if (obj?.type?.element?.name == checkerName) {
      return obj;
    }
  }
  return null;
}

Stream<String> _normalizeGeneratorOutput(Object? value) async* {
  final resolved = value is Future<Object?> ? await value : value;
  if (resolved == null) return;
  if (resolved is String) {
    final trimmed = resolved.trim();
    if (trimmed.isNotEmpty) yield trimmed;
    return;
  }
  yield* _normalizeGeneratorCollection(resolved);
}

Stream<String> _normalizeGeneratorCollection(Object value) async* {
  if (value is Iterable<Object?>) {
    for (final item in value) {
      yield* _normalizeGeneratorOutput(item);
    }
    return;
  }
  if (value is Stream<Object?>) {
    await for (final item in value) {
      yield* _normalizeGeneratorOutput(item);
    }
    return;
  }
  throw ArgumentError('Unexpected generator output: $value');
}

class _BatchBuildStep extends BuildStep {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

bool _matchesPattern(String text, Pattern pattern) => switch (pattern) {
  final RegExp re => re.hasMatch(text),
  final String s => text.contains(s),
  _ => pattern.allMatches(text).isNotEmpty,
};

typedef _StaticVerifyResult = ({
  List<CodegenCase> survivors,
  List<CodegenIssue> issues,
});

Future<_StaticVerifyResult> _verifyStaticDiagnostics(
  _BatchEnv env,
  List<CodegenCase> survivors,
  Map<String, String> generatedByCaseId,
) async {
  var current = survivors;
  final issues = <CodegenIssue>[];
  for (var pass = 0; pass < 5 && current.isNotEmpty; pass++) {
    final step = await _runSingleStaticPass(env, current, generatedByCaseId);
    _appendUniqueIssues(issues, step.issues);
    if (step.done) {
      return (survivors: step.survivors, issues: issues);
    }
    current = step.survivors;
  }
  if (current.isNotEmpty) {
    _appendUniqueIssues(issues, [
      _buildPreambleMessageIssue(
        env.preamble,
        'Static analysis retry cap (5 passes) exhausted with '
        '${current.length} unverified case(s): '
        '${current.map((c) => c.id).join(', ')}.',
      ),
    ]);
  }
  return (survivors: const <CodegenCase>[], issues: issues);
}

typedef _StaticPassStep = ({
  List<CodegenCase> survivors,
  List<CodegenIssue> issues,
  bool done,
});

Future<_StaticPassStep> _runSingleStaticPass(
  _BatchEnv env,
  List<CodegenCase> survivors,
  Map<String, String> generatedByCaseId,
) async {
  final partSource = _buildPartSource(survivors, generatedByCaseId);
  final batchSource = _buildLibrarySource(
    env: env,
    cases: survivors,
    includePartDirective: partSource != null,
  );
  await _writeAndSyncBatchFiles(env, batchSource, partSource);

  final batchDiag = await _collectRelevantDiagnostics(
    env.context,
    env.batchPath,
    includeWarnings: env.includeWarnings,
  );
  final partDiag = partSource != null
      ? await _collectRelevantDiagnostics(
          env.context,
          env.partPath,
          includeWarnings: env.includeWarnings,
        )
      : const <Diagnostic>[];

  if (batchDiag.isEmpty && partDiag.isEmpty) {
    return (survivors: survivors, issues: const <CodegenIssue>[], done: true);
  }

  final attribution = _attributeBatchAndPartDiagnostics(
    survivors: survivors,
    generatedByCaseId: generatedByCaseId,
    preamble: env.preamble,
    batchFile: (
      fileLabel: 'fuzz_batch.dart',
      source: batchSource,
      diagnostics: batchDiag,
    ),
    partFile: (
      fileLabel: 'fuzz_batch.g.dart',
      source: partSource ?? '',
      diagnostics: partDiag,
    ),
  );
  return _resolveNextStaticPassStep(survivors, attribution);
}

_StaticPassStep _resolveNextStaticPassStep(
  List<CodegenCase> survivors,
  _StaticAttributionResult attribution,
) {
  if (attribution.errorCaseIds.isEmpty) {
    final allIssues = [
      ...attribution.issues,
      ...attribution.unattributedIssues,
    ];
    return (
      survivors: attribution.hasUnattributedHardError
          ? const <CodegenCase>[]
          : survivors,
      issues: allIssues,
      done: true,
    );
  }
  final cleanSurvivors = [
    for (final c in survivors)
      if (!attribution.errorCaseIds.contains(c.id)) c,
  ];
  final cannotProgress =
      cleanSurvivors.isEmpty || cleanSurvivors.length == survivors.length;
  final issues = cannotProgress
      ? [...attribution.issues, ...attribution.unattributedIssues]
      : attribution.issues;
  return (
    survivors: cannotProgress ? const <CodegenCase>[] : cleanSurvivors,
    issues: issues,
    done: cannotProgress,
  );
}

Future<void> _writeAndSyncBatchFiles(
  _BatchEnv env,
  String batchSource,
  String? partSource,
) async {
  File(env.batchPath).writeAsStringSync(batchSource);
  env.context.changeFile(env.batchPath);
  if (partSource != null) {
    File(env.partPath).writeAsStringSync(partSource);
    env.context.changeFile(env.partPath);
  } else if (File(env.partPath).existsSync()) {
    File(env.partPath).deleteSync();
  }
  await env.context.applyPendingFileChanges();
}

typedef _MarkedFileDiagnostics = ({
  String fileLabel,
  String source,
  List<Diagnostic> diagnostics,
});

typedef _StaticAttributionResult = ({
  List<CodegenIssue> issues,
  List<CodegenIssue> unattributedIssues,
  Set<String> errorCaseIds,
  bool hasUnattributedHardError,
});

_StaticAttributionResult _attributeBatchAndPartDiagnostics({
  required List<CodegenCase> survivors,
  required Map<String, String> generatedByCaseId,
  required String preamble,
  required _MarkedFileDiagnostics batchFile,
  required _MarkedFileDiagnostics partFile,
}) {
  final caseMap = {for (final c in survivors) c.id: c};
  final symbolMap = _buildSymbolToCaseIdMap(survivors);
  final batchAttr = _attributeMarkedDiagnostics(
    fileDiag: batchFile,
    caseMap: caseMap,
    symbolMap: symbolMap,
    generatedByCaseId: generatedByCaseId,
    preamble: preamble,
  );
  final partAttr = _attributeMarkedDiagnostics(
    fileDiag: partFile,
    caseMap: caseMap,
    symbolMap: symbolMap,
    generatedByCaseId: generatedByCaseId,
    preamble: preamble,
  );
  return (
    issues: [...batchAttr.issues, ...partAttr.issues],
    unattributedIssues: [
      ...batchAttr.unattributedIssues,
      ...partAttr.unattributedIssues,
    ],
    errorCaseIds: {...batchAttr.errorCaseIds, ...partAttr.errorCaseIds},
    hasUnattributedHardError:
        batchAttr.hasUnattributedHardError || partAttr.hasUnattributedHardError,
  );
}

_StaticAttributionResult _attributeMarkedDiagnostics({
  required _MarkedFileDiagnostics fileDiag,
  required Map<String, CodegenCase> caseMap,
  required Map<String, String> symbolMap,
  required Map<String, String> generatedByCaseId,
  required String preamble,
}) {
  final foundIssues = <CodegenIssue>[];
  final unattributedIssues = <CodegenIssue>[];
  final errorCaseIds = <String>{};
  var hasUnattributedHardError = false;
  for (final d in fileDiag.diagnostics) {
    final caseId = _attributeSingleDiagnostic(fileDiag, d, symbolMap);
    final matched = caseId != null ? caseMap[caseId] : null;
    if (matched != null) {
      foundIssues.add(
        _buildStaticIssue(
          matched,
          d,
          fileDiag.fileLabel,
          generatedByCaseId[matched.id],
        ),
      );
      if (d.severity == Severity.error) errorCaseIds.add(matched.id);
    } else {
      unattributedIssues.add(
        _buildPreambleDiagnosticIssue(preamble, d, fileDiag.fileLabel),
      );
      if (d.severity == Severity.error) {
        hasUnattributedHardError = true;
      }
    }
  }
  return (
    issues: foundIssues,
    unattributedIssues: unattributedIssues,
    errorCaseIds: errorCaseIds,
    hasUnattributedHardError: hasUnattributedHardError,
  );
}

String? _attributeSingleDiagnostic(
  _MarkedFileDiagnostics fileDiag,
  Diagnostic d,
  Map<String, String> symbolMap,
) {
  if (fileDiag.source.isNotEmpty &&
      d.offset >= 0 &&
      d.offset <= fileDiag.source.length) {
    return _attributeOffsetInMarkedSource(fileDiag.source, d.offset);
  }
  return _attributeDiagnosticBySymbol(d.message, symbolMap);
}

CodegenIssue _buildStaticIssue(
  CodegenCase c,
  Diagnostic d,
  String fileLabel,
  String? generatedCode,
) => (
  caseId: c.id,
  kind: CodegenIssueKind.staticError,
  message:
      '[$fileLabel:${d.diagnosticCode.name.toLowerCase()}] '
      '${d.message}',
  declarations: c.declarations,
  generatedCode: generatedCode,
);

CodegenIssue _buildPreambleDiagnosticIssue(
  String preamble,
  Diagnostic d,
  String fileLabel,
) => _buildPreambleMessageIssue(
  preamble,
  '[$fileLabel:${d.diagnosticCode.name.toLowerCase()}] ${d.message}',
);

CodegenIssue _buildPreambleMessageIssue(String preamble, String message) => (
  caseId: 'preamble',
  kind: CodegenIssueKind.staticError,
  message: message,
  declarations: preamble,
  generatedCode: null,
);

void _appendUniqueIssues(
  List<CodegenIssue> target,
  List<CodegenIssue> candidates,
) {
  for (final candidate in candidates) {
    final exists = target.any(
      (e) =>
          e.caseId == candidate.caseId &&
          e.kind == candidate.kind &&
          e.message == candidate.message,
    );
    if (!exists) target.add(candidate);
  }
}

Future<List<Diagnostic>> _collectRelevantDiagnostics(
  AnalysisContext context,
  String filePath, {
  required bool includeWarnings,
}) async {
  final res = await context.currentSession.getErrors(filePath);
  if (res is! ErrorsResult) return const [];
  return [
    for (final d in res.diagnostics)
      if (_isRelevantDiagnostic(d, includeWarnings: includeWarnings)) d,
  ];
}

const Set<String> _ignoredWarningCodes = {
  'unused_element',
  'unused_field',
  'unused_import',
  'unused_local_variable',
};

bool _isRelevantDiagnostic(Diagnostic d, {required bool includeWarnings}) {
  if (d.severity == Severity.error) return true;
  if (!includeWarnings || d.severity != Severity.warning) return false;
  return !_ignoredWarningCodes.contains(d.diagnosticCode.name.toLowerCase());
}

Map<String, String> _buildSymbolToCaseIdMap(List<CodegenCase> cases) {
  final map = <String, String>{};
  for (final c in cases) {
    map[c.id] = c.id;
    final explicit = c.elementName?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      map[explicit] = c.id;
    }
    for (final sym in _extractDeclaredSymbols(c.declarations)) {
      map[sym] = c.id;
    }
  }
  return map;
}

final RegExp _typeLikeDeclHeaderRe = RegExp(
  r'^(?:(?:augment|abstract|sealed|base|interface|final|inline|mixin)\s+)*'
  r'(?:class|enum|mixin|extension(?:\s+type(?:\s+const)?)?)\s+'
  r'(?!on\b)([A-Za-z_$][A-Za-z0-9_$]*)',
);

final RegExp _typedefDeclHeaderRe = RegExp(
  r'^(?:augment\s+)?typedef\s+'
  r'(?:[A-Za-z_$][A-Za-z0-9_$<>?,\s.]*\s+)?'
  r'([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:<[^>]*>)?\s*(?:=|\()',
);

final RegExp _executableOrVarDeclHeaderRe = RegExp(
  r'^(?:(?:augment|external|const|final|late|var|get|set)\s+)*'
  r'(?:[A-Za-z_$][A-Za-z0-9_$<>?,\s.]*\s+)?'
  r'([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:<[^>]*>)?\s*(?:\(|=|;|=>|\{)',
);

List<String> _extractDeclaredSymbols(String declarations) {
  final unit = parseString(
    content: declarations,
    throwIfDiagnostics: false,
  ).unit;
  final symbols = <String>[];
  for (final decl in unit.declarations) {
    final start = decl.firstTokenAfterCommentAndMetadata.offset;
    if (start < 0 || start >= declarations.length) continue;
    final header = declarations.substring(start, decl.end);
    final match =
        _typeLikeDeclHeaderRe.firstMatch(header) ??
        _typedefDeclHeaderRe.firstMatch(header) ??
        _executableOrVarDeclHeaderRe.firstMatch(header);
    if (match != null) {
      symbols.add(match.group(1)!);
    }
  }
  return symbols;
}

final RegExp _caseMarkerRe = RegExp(
  r'^// === (CASE|END):(.+?) ===$',
  multiLine: true,
);

String? _attributeOffsetInMarkedSource(String source, int offset) {
  if (offset < 0 || offset > source.length) return null;
  String? activeCaseId;
  for (final match in _caseMarkerRe.allMatches(source)) {
    if (match.start > offset) break;
    final kind = match.group(1);
    final id = match.group(2)!;
    if (kind == 'CASE') {
      activeCaseId = id;
    } else if (activeCaseId == id) {
      activeCaseId = null;
    }
  }
  return activeCaseId;
}

String? _attributeDiagnosticBySymbol(
  String text,
  Map<String, String> symbolMap,
) {
  String? bestCaseId;
  var bestLen = 0;
  for (final MapEntry(:key, :value) in symbolMap.entries) {
    if (key.length > bestLen && _containsWholeIdentifier(text, key)) {
      bestLen = key.length;
      bestCaseId = value;
    }
  }
  return bestCaseId;
}

bool _containsWholeIdentifier(String text, String identifier) {
  if (identifier.isEmpty) return false;
  final escaped = RegExp.escape(identifier);
  return RegExp('(?<![A-Za-z0-9_\$])$escaped(?![A-Za-z0-9_\$])').hasMatch(text);
}

typedef _RuntimeBatchStep = ({
  Set<String> passedCaseIds,
  List<CodegenIssue> issues,
});

Future<_RuntimeBatchStep> _runBatchedIsolateChecks(
  _BatchEnv env,
  List<CodegenCase> survivors,
  Map<String, String> generatedByCaseId,
) async {
  final initialRunnable = [
    for (final c in survivors)
      if (_hasRuntimeCheck(c)) c,
  ];
  if (initialRunnable.isEmpty) {
    return (passedCaseIds: const <String>{}, issues: const <CodegenIssue>[]);
  }

  final mainPath = p.join(env.workDir, 'fuzz_batch_main.dart');
  final filterStep = await _filterCompilableRuntimeChecks(
    env: env,
    mainPath: mainPath,
    runnable: initialRunnable,
    generatedByCaseId: generatedByCaseId,
  );
  final issues = <CodegenIssue>[...filterStep.issues];
  if (filterStep.runnable.isEmpty) {
    return (passedCaseIds: const <String>{}, issues: issues);
  }

  final runResult = await _executeIsolateRunner(
    mainUri: p.toUri(mainPath),
    packageConfigUri: env.packageConfigUri,
    runnableIds: [for (final c in filterStep.runnable) c.id],
    timeout: env.isolateTimeout,
  );
  final caseMap = {for (final c in filterStep.runnable) c.id: c};
  for (final failure in runResult.failures) {
    final c = caseMap[failure['id']!];
    if (c == null) continue;
    issues.add((
      caseId: c.id,
      kind: CodegenIssueKind.runtimeFailure,
      message: failure['error']!,
      declarations: c.declarations,
      generatedCode: generatedByCaseId[c.id],
    ));
  }
  return (passedCaseIds: runResult.passedIds, issues: issues);
}

typedef _RuntimeFilterStep = ({
  List<CodegenCase> runnable,
  List<CodegenIssue> issues,
});

Future<_RuntimeFilterStep> _filterCompilableRuntimeChecks({
  required _BatchEnv env,
  required String mainPath,
  required List<CodegenCase> runnable,
  required Map<String, String> generatedByCaseId,
}) async {
  var current = runnable;
  final issues = <CodegenIssue>[];
  for (var pass = 0; pass < 5 && current.isNotEmpty; pass++) {
    final step = await _runSingleRuntimeFilterPass(
      env: env,
      mainPath: mainPath,
      runnable: current,
      generatedByCaseId: generatedByCaseId,
    );
    _appendUniqueIssues(issues, step.issues);
    if (step.done) {
      return (runnable: step.survivors, issues: issues);
    }
    current = step.survivors;
  }
  if (current.isNotEmpty) {
    _appendUniqueIssues(issues, [
      _buildPreambleMessageIssue(
        env.preamble,
        'Runtime harness static check retry cap (5 passes) exhausted with '
        '${current.length} unverified case(s): '
        '${current.map((c) => c.id).join(', ')}.',
      ),
    ]);
  }
  return (runnable: const <CodegenCase>[], issues: issues);
}

Future<_StaticPassStep> _runSingleRuntimeFilterPass({
  required _BatchEnv env,
  required String mainPath,
  required List<CodegenCase> runnable,
  required Map<String, String> generatedByCaseId,
}) async {
  final mainSource = _buildRuntimeRunnerSource(
    runnable: runnable,
    imports: env.imports,
  );
  File(mainPath).writeAsStringSync(mainSource);
  env.context.changeFile(mainPath);
  await env.context.applyPendingFileChanges();
  final mainDiag = await _collectRelevantDiagnostics(
    env.context,
    mainPath,
    includeWarnings: false,
  );
  if (mainDiag.isEmpty) {
    return (survivors: runnable, issues: const <CodegenIssue>[], done: true);
  }

  final mainFile = (
    fileLabel: 'fuzz_batch_main.dart',
    source: mainSource,
    diagnostics: mainDiag,
  );
  final attr = _attributeMarkedDiagnostics(
    fileDiag: mainFile,
    caseMap: {for (final c in runnable) c.id: c},
    symbolMap: _buildSymbolToCaseIdMap(runnable),
    generatedByCaseId: generatedByCaseId,
    preamble: env.preamble,
  );
  return _resolveNextStaticPassStep(runnable, attr);
}

typedef _IsolateRunOutcome = ({
  Set<String> passedIds,
  List<Map<String, String>> failures,
});

class _IsolateRunTracker {
  final List<String> runnableIds;
  final Set<String> completedIds = {};
  final Set<String> passedIds = {};
  final List<Map<String, String>> failures = [];
  final Completer<void> done = Completer<void>();
  String? activeCaseId;

  _IsolateRunTracker(this.runnableIds);

  void handleMessage(Object? message) {
    if (message is! Map) return;
    switch (message['type']) {
      case 'done':
        _completeDone();
      case 'start':
        activeCaseId = message['id'] as String?;
      case 'pass':
        final id = message['id'] as String?;
        if (id != null) {
          _markCompleted(id);
          passedIds.add(id);
        }
      case 'fail':
        final id = message['id'] as String?;
        if (id != null) {
          _markCompleted(id);
          passedIds.remove(id);
          failures.add({'id': id, 'error': message['error'] as String});
        }
    }
  }

  void _markCompleted(String? id) {
    if (id == null) return;
    completedIds.add(id);
    if (activeCaseId == id) activeCaseId = null;
  }

  void _completeDone() {
    if (!done.isCompleted) done.complete();
  }

  void handleCrash(Object? err) {
    recordUnfinished(
      activeError: 'Isolate crashed during runtime check: $err',
      pendingError: 'Runtime check did not run because isolate crashed: $err',
    );
    _completeDone();
  }

  void recordUnfinished({
    required String activeError,
    required String pendingError,
  }) {
    for (final id in runnableIds) {
      if (completedIds.add(id)) {
        final msg = id == activeCaseId ? activeError : pendingError;
        failures.add({'id': id, 'error': msg});
      }
    }
  }
}

Future<_IsolateRunOutcome> _executeIsolateRunner({
  required Uri mainUri,
  required Uri packageConfigUri,
  required List<String> runnableIds,
  required Duration timeout,
}) async {
  final tracker = _IsolateRunTracker(runnableIds);
  final receivePort = ReceivePort();
  final errorPort = ReceivePort();
  final sub = receivePort.listen(tracker.handleMessage);
  final errSub = errorPort.listen(tracker.handleCrash);
  Isolate? isolate;
  try {
    isolate = await Isolate.spawnUri(
      mainUri,
      const <String>[],
      receivePort.sendPort,
      packageConfig: packageConfigUri,
      onError: errorPort.sendPort,
    );
    await tracker.done.future.timeout(timeout);
  } on TimeoutException {
    tracker.recordUnfinished(
      activeError: 'Runtime check timed out after $timeout.',
      pendingError:
          'Runtime check did not finish before isolate timeout ($timeout).',
    );
  } on IsolateSpawnException catch (e) {
    tracker.recordUnfinished(
      activeError: 'Isolate failed to spawn: $e',
      pendingError: 'Isolate failed to spawn: $e',
    );
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    await sub.cancel();
    await errSub.cancel();
    receivePort.close();
    errorPort.close();
  }
  return (passedIds: tracker.passedIds, failures: tracker.failures);
}

String _buildRuntimeRunnerSource({
  required List<CodegenCase> runnable,
  required List<String> imports,
}) {
  final buf = StringBuffer()
    ..writeln('// ignore_for_file: type=lint')
    ..writeln("import 'dart:async';")
    ..writeln("import 'dart:isolate';")
    ..writeln("import 'fuzz_batch.dart';");
  for (final imp in imports) {
    final trimmed = imp.trim();
    if (trimmed.isEmpty) continue;
    buf.writeln(trimmed.endsWith(';') ? trimmed : '$trimmed;');
  }
  buf.writeln();
  for (var i = 0; i < runnable.length; i++) {
    final c = runnable[i];
    buf
      ..writeln('// === CASE:${c.id} ===')
      ..writeln('Future<void> _\$sgtRunCase$i() async {')
      ..writeln(c.runtimeCheck)
      ..writeln('}')
      ..writeln('// === END:${c.id} ===')
      ..writeln();
  }
  buf
    ..writeln(_runtimeCaseExecutorHelper)
    ..writeln(
      'Future<void> main(List<String> args, SendPort replyPort) async {',
    );
  for (var i = 0; i < runnable.length; i++) {
    final escapedId = jsonEncode(runnable[i].id);
    buf.writeln(
      r'  await _$sgtExecuteRuntimeCase('
      '$escapedId, _\$sgtRunCase$i, replyPort);',
    );
  }
  buf
    ..writeln("  replyPort.send({'type': 'done'});")
    ..writeln('}');
  return buf.toString();
}

const String _runtimeCaseExecutorHelper = r'''
Future<void> _$sgtExecuteRuntimeCase(
  String id,
  Future<void> Function() body,
  SendPort replyPort,
) async {
  replyPort.send({'type': 'start', 'id': id});
  final errors = <String>[];
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      try {
        await body();
        await Future<void>.delayed(Duration.zero);
      } on Object catch (e, st) {
        errors.add('$e\n$st');
      } finally {
        if (!done.isCompleted) done.complete();
      }
    },
    (Object e, StackTrace st) {
      errors.add('$e\n$st');
      if (!done.isCompleted) {
        done.complete();
      } else {
        replyPort.send({'type': 'fail', 'id': id, 'error': '$e\n$st'});
      }
    },
  );
  await done.future;
  if (errors.isEmpty) {
    replyPort.send({'type': 'pass', 'id': id});
  } else {
    replyPort.send({'type': 'fail', 'id': id, 'error': errors.join('\n')});
  }
}
''';

String _buildLibrarySource({
  required _BatchEnv env,
  required List<CodegenCase> cases,
  required bool includePartDirective,
}) {
  final buf = StringBuffer()..writeln('// ignore_for_file: type=lint');
  for (final imp in env.imports) {
    final trimmed = imp.trim();
    if (trimmed.isEmpty) continue;
    buf.writeln(trimmed.endsWith(';') ? trimmed : '$trimmed;');
  }
  if (includePartDirective) {
    buf.writeln("part 'fuzz_batch.g.dart';");
  }
  if (env.preamble.trim().isNotEmpty) {
    buf
      ..writeln()
      ..writeln(env.preamble.trim());
  }
  for (final c in cases) {
    buf
      ..writeln()
      ..writeln('// === CASE:${c.id} ===')
      ..writeln(c.declarations.trim())
      ..writeln('// === END:${c.id} ===');
  }
  return buf.toString();
}

String? _buildPartSource(
  List<CodegenCase> survivors,
  Map<String, String> generatedByCaseId,
) {
  final hasGenerated = survivors.any(
    (c) => generatedByCaseId.containsKey(c.id),
  );
  if (!hasGenerated) return null;
  final buf = StringBuffer()
    ..writeln('// ignore_for_file: type=lint')
    ..writeln("part of 'fuzz_batch.dart';");
  final seenChunks = <String>{};
  for (final c in survivors) {
    final code = generatedByCaseId[c.id];
    if (code == null || code.isEmpty) continue;
    final uniqueChunks = [
      for (final chunk in _splitTopLevelDeclarations(code))
        if (seenChunks.add(chunk)) chunk,
    ];
    if (uniqueChunks.isEmpty) continue;
    buf
      ..writeln()
      ..writeln('// === CASE:${c.id} ===')
      ..writeln(uniqueChunks.join('\n\n'))
      ..writeln('// === END:${c.id} ===');
  }
  return buf.toString();
}

List<String> _splitTopLevelDeclarations(String code) {
  final parsed = parseString(content: code, throwIfDiagnostics: false);
  final declarations = parsed.unit.declarations;
  if (parsed.errors.isNotEmpty || declarations.isEmpty) {
    return [code.trim()];
  }
  final directives = parsed.unit.directives;
  var start = directives.isEmpty ? 0 : directives.last.end;
  final chunks = <String>[];
  for (var i = 0; i < declarations.length; i++) {
    final isLast = i == declarations.length - 1;
    final end = isLast
        ? code.length
        : _declarationSplitEnd(
            code,
            declarations[i].end,
            declarations[i + 1].offset,
          );
    final chunk = code.substring(start, end).trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    start = end;
  }
  return chunks;
}

int _declarationSplitEnd(String code, int declEnd, int nextDeclOffset) {
  final nl = code.indexOf('\n', declEnd);
  return (nl != -1 && nl < nextDeclOffset) ? nl + 1 : declEnd;
}

Future<LibraryElement> _resolveLibraryAtPath(
  AnalysisContext context,
  String filePath,
  String source,
) async {
  File(filePath).writeAsStringSync(source);
  context.changeFile(filePath);
  await context.applyPendingFileChanges();
  final resolved = await context.currentSession.getResolvedLibrary(filePath);
  if (resolved is! ResolvedLibraryResult) {
    throw StateError('Failed to resolve library at $filePath: $resolved');
  }
  return resolved.element;
}

/// Formats a [CodegenBatchReport] into a human-readable diagnostic summary.
String formatCodegenBatchReport(CodegenBatchReport report) {
  final buf = StringBuffer()
    ..writeln(
      'Codegen batch verification found ${report.issues.length} issue(s) '
      '(${report.passedCases}/${report.totalCases} cases passed):',
    );
  for (final issue in report.issues) {
    buf
      ..writeln()
      ..writeln('--- [${issue.kind.name}] Case: ${issue.caseId} ---')
      ..writeln('Message: ${issue.message.trim()}')
      ..writeln('Declarations:\n${issue.declarations.trim()}');
    if (issue.generatedCode != null && issue.generatedCode!.trim().isNotEmpty) {
      buf.writeln('Generated Code:\n${issue.generatedCode!.trim()}');
    }
  }
  return buf.toString();
}

File _findPackageConfigFile(String startDir) {
  var current = p.normalize(p.absolute(startDir));
  while (true) {
    final candidate = File(
      p.join(current, '.dart_tool', 'package_config.json'),
    );
    if (candidate.existsSync()) return candidate;
    final parent = p.dirname(current);
    if (parent == current) break;
    current = parent;
  }
  throw StateError(
    'No .dart_tool/package_config.json found in $startDir or its parents. '
    'Run `dart pub get` first.',
  );
}
