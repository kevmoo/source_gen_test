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
    if (name.contains('CrashGen')) {
      throw RangeError.index(-1, const <int>[], 'simulatedGeneratorBug');
    }
    if (name.contains('BrokenSyntax')) {
      yield 'Map<String, Object?> _\$${name}ToMap($name v) => '
          '<String, int>{"x": "notAnInt"};';
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
      check(report.issues).isNotEmpty();
      check(report.issues.first.kind).equals(CodegenIssueKind.staticError);
      check(report.passedCases).isLessThan(report.totalCases);
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
