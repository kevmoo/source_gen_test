@TestOn('vm')
library;

import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:checks/checks.dart';
import 'package:source_gen/source_gen.dart';
import 'package:source_gen_test/source_gen_test.dart';
import 'package:test/scaffolding.dart';

class _TestModel {
  const _TestModel();
}

/// A real `source_gen` [GeneratorForAnnotation] with intentional bug triggers
/// so [verifyGeneratorBatch] can test all three verification oracles.
class _DemoModelGenerator extends GeneratorForAnnotation<_TestModel> {
  const _DemoModelGenerator();

  @override
  Iterable<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) sync* {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@_TestModel can only be applied to classes.',
        element: element,
      );
    }
    final name = element.name!;
    if (name.contains('RequiresPartDirective')) {
      final sourceText = element.library.firstFragment.source.contents.data;
      if (!sourceText.contains("part 'fuzz_batch.g.dart';")) {
        throw InvalidGenerationSourceError(
          'Missing generated part directive in library source.',
          element: element,
        );
      }
    }
    if (name.contains('CrashGen')) {
      throw RangeError.index(-1, const <int>[], 'simulatedGeneratorBug');
    }
    if (name.contains('UnparseableSyntax')) {
      yield 'int _\$${name}Bad = ;';
      return;
    }
    if (name.contains('BrokenSyntax')) {
      yield 'Map<String, Object?> _\$${name}ToMap($name v) => '
          '<String, int>{"x": "notAnInt"};';
      return;
    }
    if (name.contains('IgnoredNullAware')) {
      yield '''
// ignore: invalid_null_aware_operator
Map<String, Object?> _\$${name}ToMap($name v, [int nonNull = 42]) => {'x': ?nonNull};
''';
      return;
    }
    if (name.contains('WarnNullAware')) {
      yield '''
Map<String, Object?> _\$${name}ToMap($name v) {
  const nonNull = 42;
  return {'x': ?nonNull};
}
''';
      return;
    }
    if (name.contains('CorruptRuntime')) {
      yield '''
Map<String, Object?> _\$${name}ToMap($name v) => {'x': -999};
$name _\$${name}FromMap(Map<String, Object?> m) => $name(m['x'] as int);
''';
      return;
    }
    yield '''
Map<String, Object?> _\$${name}ToMap($name v) => {'x': v.x + _\$sharedDemoOffset};
$name _\$${name}FromMap(Map<String, Object?> m) => $name((m['x'] as int) - _\$sharedDemoOffset);
''';
    yield r'const _$sharedDemoOffset = 0;';
  }
}

class _PlainLibraryGenerator extends Generator {
  const _PlainLibraryGenerator();

  @override
  String? generate(LibraryReader library, BuildStep buildStep) {
    final sourceText = library.element.firstFragment.source.contents.data;
    if (!sourceText.contains("part 'fuzz_batch.g.dart';")) {
      throw InvalidGenerationSourceError(
        'Library is missing part directive.',
        element: library.element,
      );
    }
    final buf = StringBuffer();
    for (final cls in library.classes) {
      final name = cls.name!;
      if (name.startsWith('_')) continue;
      if (name.contains('FailPlain')) {
        throw InvalidGenerationSourceError(
          'Plain generator rejected $name.',
          element: cls,
        );
      }
      buf.writeln('String _\$${name}Label($name v) => "$name:\${v.x}";');
    }
    return buf.isEmpty ? null : buf.toString();
  }
}

class _AnyElementGenerator extends GeneratorForAnnotation<_TestModel> {
  const _AnyElementGenerator();

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    final safeId = element.name!.replaceAll(r'$', 'Dollar');
    return "const String kGenerated${safeId}Name = r'${element.name}';";
  }
}

const String _testPreamble = '''
class _TestModel {
  const _TestModel();
}
''';

void main() {
  group('cartesianProduct', () {
    test('expands multiple axes deterministically', () {
      final product = cartesianProduct<String, String>({
        'nullability': ['T', 'T?'],
        'container': ['scalar', 'list', 'map'],
      });
      check(product).length.equals(6);
      check(
        product.first,
      ).deepEquals({'nullability': 'T', 'container': 'scalar'});
      check(product.last).deepEquals({'nullability': 'T?', 'container': 'map'});
    });

    test(
      'returns empty list for empty axes map and rejects empty axis values',
      () {
        check(cartesianProduct<String, int>(const {})).isEmpty();
        check(
          () => cartesianProduct<String, int>({
            'a': [1],
            'b': const [],
          }),
        ).throws<ArgumentError>();
      },
    );
  });

  group('verifyGeneratorBatch', () {
    test('returns empty report when cases is empty', () async {
      final report = await verifyGeneratorBatch(
        generator: const _DemoModelGenerator(),
        cases: const [],
      );
      check(report.totalCases).equals(0);
      check(report.passedCases).equals(0);
      check(report.issues).isEmpty();
    });

    test(
      'passes when static analysis, negative diagnostics, preamble, '
      'auxiliaryFiles, explicit elementName, external workDir package '
      'resolution, and shared top-level helper deduplication succeed',
      () async {
        final customWorkDir = Directory.systemTemp.createTempSync(
          'sgt_batch_work_',
        );
        try {
          final report = await verifyGeneratorBatch(
            generator: const _DemoModelGenerator(),
            preamble: _testPreamble,
            imports: const [
              "import 'package:meta/meta.dart';",
              "import 'aux_helper.dart';",
            ],
            auxiliaryFiles: const {
              'aux_helper.dart': 'const int kAuxSeed = 7;\n',
            },
            workDir: customWorkDir.path,
            cases: [
              const CodegenCase(
                id: 'valid_alpha',
                declarations: r'''
@immutable
@_TestModel()
class ValidAlpha {
  final int x;
  const ValidAlpha(this.x);
  Map<String, Object?> toMap() => _$ValidAlphaToMap(this);
  factory ValidAlpha.fromMap(Map<String, Object?> m) => _$ValidAlphaFromMap(m);
}
''',
                runtimeCheck: r'''
final orig = ValidAlpha(kAuxSeed);
final decoded = ValidAlpha.fromMap(orig.toMap());
if (decoded.x != kAuxSeed) throw StateError('Mismatch: ${decoded.x}');
''',
              ),
              const CodegenCase(
                id: 'explicit_element_name',
                elementName: 'TargetSecondClass',
                declarations: r'''
class HelperBeforeTarget {
  const HelperBeforeTarget();
}

@_TestModel()
mixin class TargetSecondClass {
  int get x => 99;
  factory TargetSecondClass([int x = 99]) => _TargetSecondClassImpl(x);
  Map<String, Object?> toMap() => _$TargetSecondClassToMap(this);
}

class _TargetSecondClassImpl with TargetSecondClass {
  @override
  final int x;
  _TargetSecondClassImpl([this.x = 99]);
}
''',
                runtimeCheck: '''
final map = TargetSecondClass().toMap();
if (map['x'] != 99) throw StateError('Expected 99');
''',
              ),
              CodegenCase(
                id: 'invalid_enum_target',
                declarations: '''
@_TestModel()
enum NotAClass { a, b }
''',
                expectedError: RegExp(
                  r'@_TestModel can only be applied to classes\.',
                ),
              ),
            ],
          );

          check(report.totalCases).equals(3);
          check(report.passedCases).equals(3);
          check(report.issues).isEmpty();
          check(customWorkDir.listSync()).isEmpty();
        } finally {
          if (customWorkDir.existsSync()) {
            customWorkDir.deleteSync(recursive: true);
          }
        }
      },
    );

    test('isolates per-element generator crashes, exact static error/warning '
        'markers (including case IDs with spaces), and runtime failures in one '
        'batch', () async {
      final report = await verifyGeneratorBatch(
        generator: const _DemoModelGenerator(),
        preamble: _testPreamble,
        failOnIssues: false,
        cases: const [
          CodegenCase(
            id: 'good_case',
            declarations: r'''
@_TestModel()
class GoodCase {
  final int x;
  GoodCase(this.x);
  Map<String, Object?> toMap() => _$GoodCaseToMap(this);
  factory GoodCase.fromMap(Map<String, Object?> m) => _$GoodCaseFromMap(m);
}
''',
            runtimeCheck: '''
final v = GoodCase.fromMap(GoodCase(123).toMap());
if (v.x != 123) throw StateError('Bad round-trip');
''',
          ),
          CodegenCase(
            id: 'crash_gen_case',
            declarations: '''
@_TestModel()
class CrashGenCase {
  final int x;
  CrashGenCase(this.x);
}
''',
          ),
          CodegenCase(
            id: 'static error case 1 <Map<String, int?>>',
            declarations: '''
@_TestModel()
class BrokenSyntaxCase1 {
  final int x;
  BrokenSyntaxCase1(this.x);
}
''',
          ),
          CodegenCase(
            id: 'good_case_10',
            declarations: '''
@_TestModel()
class BrokenSyntaxCase10 {
  final int x;
  BrokenSyntaxCase10(this.x);
}
''',
          ),
          CodegenCase(
            id: 'runtime_compile_error_case',
            declarations: r'''
@_TestModel()
class ValidModelForBadCheck {
  final int x;
  ValidModelForBadCheck(this.x);
  Map<String, Object?> toMap() => _$ValidModelForBadCheckToMap(this);
}
''',
            runtimeCheck: r'''
final _ = _$NonExistentPrivateSymbol;
''',
          ),
          CodegenCase(
            id: 'static_warning_case',
            declarations: '''
@_TestModel()
class WarnNullAwareCase {
  final int x;
  WarnNullAwareCase(this.x);
}
''',
          ),
          CodegenCase(
            id: 'runtime_fail_case',
            declarations: r'''
@_TestModel()
class CorruptRuntimeCase {
  final int x;
  CorruptRuntimeCase(this.x);
  Map<String, Object?> toMap() => _$CorruptRuntimeCaseToMap(this);
  factory CorruptRuntimeCase.fromMap(Map<String, Object?> m) =>
      _$CorruptRuntimeCaseFromMap(m);
}
''',
            runtimeCheck: r'''
final v = CorruptRuntimeCase.fromMap(CorruptRuntimeCase(10).toMap());
if (v.x != 10) throw StateError('Expected 10, got ${v.x}');
''',
          ),
          CodegenCase(
            id: 'unexpected_success_case',
            declarations: '''
@_TestModel()
class ShouldHaveFailedCase {
  final int x;
  ShouldHaveFailedCase(this.x);
}
''',
            expectedError: 'Expected failure that never happens',
          ),
          CodegenCase(
            id: 'mismatched_error_case',
            declarations: '''
@_TestModel()
enum MismatchedErrorEnum { a, b }
''',
            expectedError: 'Some other error text',
          ),
        ],
      );

      check(report.totalCases).equals(9);
      check(report.passedCases).equals(1);

      final byId = {for (final i in report.issues) i.caseId: i};
      check(byId.containsKey('good_case')).isFalse();
      check(
        byId['crash_gen_case']?.kind,
      ).equals(CodegenIssueKind.generatorException);
      const spaceCaseId = 'static error case 1 <Map<String, int?>>';
      check(byId[spaceCaseId]?.kind).equals(CodegenIssueKind.staticError);
      check(byId[spaceCaseId]!.generatedCode).isNotNull()
        ..contains('BrokenSyntaxCase1')
        ..not((it) => it.contains('BrokenSyntaxCase10'));
      check(byId['good_case_10']?.kind).equals(CodegenIssueKind.staticError);
      check(
        byId['runtime_compile_error_case']?.kind,
      ).equals(CodegenIssueKind.staticError);
      check(
        byId['runtime_compile_error_case']!.message,
      ).contains('fuzz_batch_main.dart:');
      check(
        byId['static_warning_case']?.kind,
      ).equals(CodegenIssueKind.staticError);
      check(
        byId['static_warning_case']!.message,
      ).contains('invalid_null_aware_operator');
      check(
        byId['runtime_fail_case']?.kind,
      ).equals(CodegenIssueKind.runtimeFailure);
      check(
        byId['runtime_fail_case']!.message,
      ).contains('Expected 10, got -999');
      check(
        byId['unexpected_success_case']?.kind,
      ).equals(CodegenIssueKind.unexpectedSuccess);
      check(
        byId['mismatched_error_case']?.kind,
      ).equals(CodegenIssueKind.generatorException);
    });

    test('reports unattributed hard errors in preamble even when multiple '
        'cases survive generation', () async {
      final report = await verifyGeneratorBatch(
        generator: const _DemoModelGenerator(),
        preamble:
            '''
$_testPreamble
const int brokenPreambleConstant = 'notAnInt';
''',
        failOnIssues: false,
        cases: const [
          CodegenCase(
            id: 'case_one',
            declarations: '''
@_TestModel()
class CaseOne {
  final int x;
  CaseOne(this.x);
}
''',
          ),
          CodegenCase(
            id: 'case_two',
            declarations: '''
@_TestModel()
class CaseTwo {
  final int x;
  CaseTwo(this.x);
}
''',
          ),
        ],
      );
      check(report.issues).length.equals(1);
      check(report.issues.single.caseId).equals('preamble');
      check(report.issues.single.kind).equals(CodegenIssueKind.staticError);
      check(report.passedCases).equals(0);
    });

    test(
      'attributes broken preamble to preamble without blaming innocent cases '
      'or counting unverified runtime checks as passed (C1 & C4 repro)',
      () async {
        final report = await verifyGeneratorBatch(
          generator: const _DemoModelGenerator(),
          preamble:
              '''
$_testPreamble
const int brokenPreambleConstant = 'zzz';
''',
          failOnIssues: false,
          cases: [
            const CodegenCase(
              id: 'int',
              declarations: '''
@_TestModel()
class IntNamedCase {
  final int x;
  IntNamedCase(this.x);
}
''',
            ),
            for (var i = 1; i <= 7; i++)
              CodegenCase(
                id: 'good_case_$i',
                declarations:
                    '''
@_TestModel()
class GoodPreambleCase$i {
  final int x;
  GoodPreambleCase$i(this.x);
}
''',
              ),
            const CodegenCase(
              id: 'failing_runtime_case',
              declarations: '''
@_TestModel()
class FailingRuntimeCase {
  final int x;
  FailingRuntimeCase(this.x);
}
''',
              runtimeCheck: "throw StateError('must not pass');",
            ),
          ],
        );

        check(report.totalCases).equals(9);
        check(report.passedCases).equals(0);
        check(report.issues).length.equals(1);
        final issue = report.issues.single;
        check(issue.caseId).equals('preamble');
        check(issue.kind).equals(CodegenIssueKind.staticError);
        check(issue.message).contains('fuzz_batch.dart:');
      },
    );

    test(
      'includes part directive in Phase 1 library source for both shared and '
      'per-case readers (B1) and supports plain Generator subclasses (B2)',
      () async {
        final annotatedReport = await verifyGeneratorBatch(
          generator: const _DemoModelGenerator(),
          preamble: _testPreamble,
          cases: const [
            CodegenCase(
              id: 'shared_part_check',
              declarations: '''
@_TestModel()
class RequiresPartDirectiveShared {
  final int x;
  RequiresPartDirectiveShared(this.x);
}
''',
            ),
            CodegenCase(
              id: 'dup_part_check_1',
              declarations: '''
@_TestModel()
class RequiresPartDirectiveDup {
  final int x;
  RequiresPartDirectiveDup(this.x);
}
''',
              expectedError: 'never_matches',
            ),
            CodegenCase(
              id: 'dup_part_check_2',
              declarations: '''
@_TestModel()
class RequiresPartDirectiveDup {
  final int x;
  RequiresPartDirectiveDup(this.x);
}
''',
              expectedError: 'never_matches',
            ),
          ],
          failOnIssues: false,
        );
        final annotatedById = {
          for (final i in annotatedReport.issues) i.caseId: i,
        };
        check(annotatedById.containsKey('shared_part_check')).isFalse();
        check(
          annotatedById['dup_part_check_1']?.kind,
        ).equals(CodegenIssueKind.unexpectedSuccess);
        check(
          annotatedById['dup_part_check_2']?.kind,
        ).equals(CodegenIssueKind.unexpectedSuccess);

        final plainReport = await verifyGeneratorBatch(
          generator: const _PlainLibraryGenerator(),
          cases: const [
            CodegenCase(
              id: 'plain_one',
              declarations: r'''
class PlainOne {
  final int x;
  PlainOne(this.x);
  String get label => _$PlainOneLabel(this);
}
''',
              runtimeCheck: '''
if (PlainOne(11).label != 'PlainOne:11') throw StateError('Bad label');
''',
            ),
            CodegenCase(
              id: 'plain_two',
              declarations: r'''
class PlainTwo {
  final int x;
  PlainTwo(this.x);
  String get label => _$PlainTwoLabel(this);
}
''',
              runtimeCheck: '''
if (PlainTwo(22).label != 'PlainTwo:22') throw StateError('Bad label');
''',
            ),
            CodegenCase(
              id: 'plain_expected_err',
              declarations: '''
class FailPlainTarget {
  final int x = 0;
}
''',
              expectedError: 'Plain generator rejected FailPlainTarget.',
            ),
          ],
        );

        check(plainReport.totalCases).equals(3);
        check(plainReport.passedCases).equals(3);
        check(plainReport.issues).isEmpty();
      },
    );

    test(
      'preserves unformatted generated code when syntax is unparseable instead '
      'of masking it with FormatterException (C2)',
      () async {
        final report = await verifyGeneratorBatch(
          generator: const _DemoModelGenerator(),
          preamble: _testPreamble,
          failOnIssues: false,
          cases: const [
            CodegenCase(
              id: 'unparseable_positive',
              declarations: '''
@_TestModel()
class UnparseableSyntaxPositive {
  final int x;
  UnparseableSyntaxPositive(this.x);
}
''',
            ),
            CodegenCase(
              id: 'unparseable_expected_could_not',
              declarations: '''
@_TestModel()
class UnparseableSyntaxNegative {
  final int x;
  UnparseableSyntaxNegative(this.x);
}
''',
              expectedError: 'Could not',
            ),
          ],
        );

        check(report.totalCases).equals(2);
        check(report.passedCases).equals(0);
        final byId = {for (final i in report.issues) i.caseId: i};
        final posIssue = byId['unparseable_positive']!;
        check(posIssue.kind).equals(CodegenIssueKind.staticError);
        check(
          posIssue.generatedCode,
        ).isNotNull().contains(r'int _$UnparseableSyntaxPositiveBad = ;');
        final negIssue = byId['unparseable_expected_could_not']!;
        check(negIssue.kind).equals(CodegenIssueKind.unexpectedSuccess);
        check(
          negIssue.generatedCode,
        ).isNotNull().contains(r'int _$UnparseableSyntaxNegativeBad = ;');
      },
    );

    test(
      'catches isolate timeout when a runtimeCheck hangs, kills the isolate, '
      'preserves earlier case results, and reports unfinished cases as '
      'runtimeFailure (C3)',
      () async {
        final report = await verifyGeneratorBatch(
          generator: const _DemoModelGenerator(),
          preamble: _testPreamble,
          failOnIssues: false,
          isolateTimeout: const Duration(milliseconds: 200),
          cases: const [
            CodegenCase(
              id: 'passes_before_hang',
              declarations: r'''
@_TestModel()
class PassesBeforeHang {
  final int x;
  PassesBeforeHang(this.x);
  Map<String, Object?> toMap() => _$PassesBeforeHangToMap(this);
}
''',
              runtimeCheck: '''
if (PassesBeforeHang(5).toMap()['x'] != 5) throw StateError('bad');
''',
            ),
            CodegenCase(
              id: 'hanging_case',
              declarations: '''
@_TestModel()
class HangingCase {
  final int x;
  HangingCase(this.x);
}
''',
              runtimeCheck: '''
await Completer<void>().future;
''',
            ),
            CodegenCase(
              id: 'unexecuted_after_hang',
              declarations: r'''
@_TestModel()
class UnexecutedAfterHang {
  final int x;
  UnexecutedAfterHang(this.x);
  Map<String, Object?> toMap() => _$UnexecutedAfterHangToMap(this);
}
''',
              runtimeCheck: '''
if (UnexecutedAfterHang(1).toMap()['x'] != 1) throw StateError('bad');
''',
            ),
          ],
        );

        check(report.totalCases).equals(3);
        check(report.passedCases).equals(1);
        final byId = {for (final i in report.issues) i.caseId: i};
        check(byId.containsKey('passes_before_hang')).isFalse();
        check(
          byId['hanging_case']?.kind,
        ).equals(CodegenIssueKind.runtimeFailure);
        check(byId['hanging_case']!.message).contains('timed out');
        check(
          byId['unexecuted_after_hang']?.kind,
        ).equals(CodegenIssueKind.runtimeFailure);
      },
    );

    test('distinguishes prefix case IDs (case_1 vs case_10) and respects END '
        'markers without substring collision (C4)', () async {
      final report = await verifyGeneratorBatch(
        generator: const _DemoModelGenerator(),
        preamble: _testPreamble,
        failOnIssues: false,
        cases: const [
          CodegenCase(
            id: 'case_1',
            declarations: r'''
@_TestModel()
class Case1 {
  final int x;
  Case1(this.x);
  Map<String, Object?> toMap() => _$Case1ToMap(this);
}
''',
            runtimeCheck: '''
if (Case1(9).toMap()['x'] != 9) throw StateError('bad');
''',
          ),
          CodegenCase(
            id: 'case_10',
            declarations: '''
@_TestModel()
class BrokenSyntaxCase10Prefix {
  final int x;
  BrokenSyntaxCase10Prefix(this.x);
}
''',
          ),
        ],
      );

      check(report.totalCases).equals(2);
      check(report.passedCases).equals(1);
      check(report.issues).length.equals(1);
      check(report.issues.single.caseId).equals('case_10');
      check(report.issues.single.kind).equals(CodegenIssueKind.staticError);
    });

    test('preserves leading // ignore: comments before generated declarations '
        'when includeWarnings is true (C5)', () async {
      final report = await verifyGeneratorBatch(
        generator: const _DemoModelGenerator(),
        preamble: _testPreamble,
        cases: const [
          CodegenCase(
            id: 'ignored_null_aware',
            declarations: r'''
@_TestModel()
class IgnoredNullAwareCase {
  final int x;
  IgnoredNullAwareCase(this.x);
  Map<String, Object?> toMap() => _$IgnoredNullAwareCaseToMap(this);
}
''',
            runtimeCheck: '''
if (IgnoredNullAwareCase(1).toMap()['x'] != 42) throw StateError('bad');
''',
          ),
        ],
      );

      check(report.totalCases).equals(1);
      check(report.passedCases).equals(1);
      check(report.issues).isEmpty();
    });

    test(
      'extracts element names accurately across doc comments, modifiers, '
      'dollar identifiers, extension type const, and legacy typedefs (C6a)',
      () async {
        final report = await verifyGeneratorBatch(
          generator: const _AnyElementGenerator(),
          preamble: _testPreamble,
          cases: const [
            CodegenCase(
              id: 'sealed_dollar_class_with_doc',
              declarations: r'''
/// Doc comment mentioning class FakeDocClass and enum FakeDocEnum.
@_TestModel()
sealed class $Real_Class {}
''',
              runtimeCheck: r'''
if (kGeneratedDollarReal_ClassName != r'$Real_Class') {
  throw StateError('bad class name');
}
''',
            ),
            CodegenCase(
              id: 'ext_type_const',
              declarations: '''
@_TestModel()
extension type const ConstExtType(int x) {}
''',
              runtimeCheck: '''
if (kGeneratedConstExtTypeName != 'ConstExtType') {
  throw StateError('bad ext type');
}
''',
            ),
            CodegenCase(
              id: 'legacy_typedef',
              declarations: '''
@_TestModel()
typedef void LegacyCallback(int x);
''',
              runtimeCheck: '''
if (kGeneratedLegacyCallbackName != 'LegacyCallback') {
  throw StateError('bad typedef');
}
''',
            ),
          ],
        );

        check(report.totalCases).equals(3);
        check(report.passedCases).equals(3);
        check(report.issues).isEmpty();
      },
    );

    test('captures uncaught async errors in runtimeCheck via runZonedGuarded '
        'and attributes them to the failing case without aborting subsequent '
        'cases (C6b)', () async {
      final report = await verifyGeneratorBatch(
        generator: const _DemoModelGenerator(),
        preamble: _testPreamble,
        failOnIssues: false,
        cases: const [
          CodegenCase(
            id: 'async_error_case',
            declarations: '''
@_TestModel()
class AsyncErrorCase {
  final int x;
  AsyncErrorCase(this.x);
}
''',
            runtimeCheck: '''
scheduleMicrotask(() => throw StateError('async boom'));
''',
          ),
          CodegenCase(
            id: 'subsequent_passing_case',
            declarations: r'''
@_TestModel()
class SubsequentPassingCase {
  final int x;
  SubsequentPassingCase(this.x);
  Map<String, Object?> toMap() => _$SubsequentPassingCaseToMap(this);
}
''',
            runtimeCheck: '''
if (SubsequentPassingCase(7).toMap()['x'] != 7) throw StateError('bad');
''',
          ),
        ],
      );

      check(report.totalCases).equals(2);
      check(report.passedCases).equals(1);
      check(report.issues).length.equals(1);
      final issue = report.issues.single;
      check(issue.caseId).equals('async_error_case');
      check(issue.kind).equals(CodegenIssueKind.runtimeFailure);
      check(issue.message).contains('async boom');
    });

    test(
      'suppresses warnings when includeWarnings is false and throws StateError '
      'when failOnIssues is true',
      () async {
        final noWarnReport = await verifyGeneratorBatch(
          generator: const _DemoModelGenerator(),
          preamble: _testPreamble,
          includeWarnings: false,
          cases: const [
            CodegenCase(
              id: 'warn_ignored',
              declarations: '''
@_TestModel()
class WarnNullAwareIgnored {
  final int x;
  WarnNullAwareIgnored(this.x);
}
''',
            ),
          ],
        );
        check(noWarnReport.passedCases).equals(1);
        check(noWarnReport.issues).isEmpty();

        await check(
          verifyGeneratorBatch(
            generator: const _DemoModelGenerator(),
            preamble: _testPreamble,
            cases: const [
              CodegenCase(
                id: 'warn_reported',
                declarations: '''
@_TestModel()
class WarnNullAwareReported {
  final int x;
  WarnNullAwareReported(this.x);
}
''',
              ),
            ],
          ),
        ).throws<StateError>();
      },
    );
  });
}
