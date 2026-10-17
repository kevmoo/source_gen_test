---
name: source-gen-test-fuzz
description: >-
  Stress-tests Dart source_gen Generator and GeneratorForAnnotation code
  generators by extracting AST control-flow branch axes, expanding combinatorial
  declaration matrices with cartesianProduct, and validating per-case generated
  output through verifyGeneratorBatch across diagnostic contracts, analyzer
  static errors and warnings, and batched Isolate.spawnUri runtime round-trip
  execution. Use when fuzzing or stress-testing a source_gen generator package,
  auditing code generator soundness across AST permutations, or running
  /source-gen-test-fuzz. Do not use for byte-stream parser fuzzing with
  libFuzzer (use fuzz) or single-case golden expectation updates.
---

# AST-Combinatorial `source_gen` Generator Fuzzing (`source-gen-test-fuzz`)

Unlike byte-stream parsers, a `package:source_gen` `Generator` or
`GeneratorForAnnotation<T>` (such as `json_serializable`, `build_cli`,
`built_value`, `freezed`, or custom annotation generators) takes **valid,
resolved Dart declarations** (`ClassElement`, `FieldElement`, `DartType`,
`ConstantReader`) and emits Dart source code (`.g.dart`).

To uncover deep interaction bugs in a `Generator`, permute the **AST declaration
axes that flip control-flow branches inside the generator** and validate every
permutation with `verifyGeneratorBatch` from
`package:source_gen_test/source_gen_test.dart` in a single shared
`AnalysisContextCollection` and a single batched `Isolate.spawnUri` call.

## Quick Start

Ensure the target package depends on `source_gen_test: ^1.4.1` in
`dev_dependencies` (`pubspec.yaml`), then run a `dart test -c source` file or a
standalone script (with `--enable-asserts` and `--packages` pointing to the
target package's or workspace's `.dart_tool/package_config.json`):

```bash
cd /path/to/target_package && \
  dart test -c source test/codegen_fuzz_test.dart
```

For standalone exploration scripts outside `test/`:

```bash
cd /path/to/target_package && \
  SOURCE_GEN_TEST_WORK_DIR="$(mktemp -d)" \
  dart --enable-asserts --packages=.dart_tool/package_config.json \
    /path/to/fuzz_slice.dart
```

In a Dart Pub workspace where `.dart_tool/package_config.json` lives at the
workspace root, pass `--packages=../.dart_tool/package_config.json` (or run via
`dart test -c source`). `verifyGeneratorBatch` automatically materializes a
normalized `.dart_tool/package_config.json` inside its temporary work directory
so external `workDir` / `SOURCE_GEN_TEST_WORK_DIR` paths resolve `package:`
imports cleanly.

## API Quick Reference (`package:source_gen_test/source_gen_test.dart`)

```dart
enum CodegenIssueKind {
  generatorException,
  unexpectedSuccess,
  staticError,
  runtimeFailure,
}

typedef CodegenIssue = ({
  String caseId,
  CodegenIssueKind kind,
  String message,
  String declarations,
  String? generatedCode,
});

typedef CodegenBatchReport = ({
  int totalCases,
  int passedCases,
  List<CodegenIssue> issues,
});

const CodegenCase({
  required String id,
  required String declarations,
  String? elementName, // Defaults to the first top-level declaration in `declarations`.
  String? runtimeCheck,
  Pattern? expectedError,
});

List<Map<K, V>> cartesianProduct<K, V>(Map<K, List<V>> axes);

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
});

String formatCodegenBatchReport(CodegenBatchReport report);
```

## Workflow: How to Fuzz a `Generator`

### Phase 1: Map the Generator's AST Branch Axes

Read the target generator's `lib/src/` files and list every condition that
branches on the input `Element`, `DartType`, or annotation `ConstantReader`:

1. **Type Nullability & Generic Bounds**:
   - Non-nullable `T` vs. nullable `T?` vs. `dynamic` / `Object?` / `Object`.
   - Unbounded `<T>` vs. bounded `<T extends Object>` or `<T extends num?>`.
   - `forceNullable` interactions (default values, nullable constructor
     parameters on non-nullable fields, custom converters).
2. **Container & Wrapper Nesting**:
   - Scalar `T`, `List<T>`, `Set<T>`, `Iterable<T>`, `Map<String, T>`,
     `Map<EnumKey, EnumVal>`, and nested `Map<String, List<T?>>`.
3. **Declaration Origin & Class Hierarchy**:
   - Regular fields, getter/setter pairs, virtual fields, `super.field`
     parameters, primary constructor declaring parameters, generic superclasses,
     mixins (`with M1, M2`), named mixin applications
     (`class Sub<T> = Base<T> with Mixin;`), and cross-library `typedef` aliases
     (`typedef Id<T> = T;`, `typedef NullableAlias = Foo?;`, private
     `typedef _Priv = String;` in an imported `auxiliaryFiles` library).
4. **Annotation & Configuration Combinations**:
   - Class-level and field-level flags that interact (`includeIfNull`,
     `explicitToJson`, `genericArgumentFactories`, `checked`,
     `disallowUnrecognizedKeys`, `createFieldMap`, `createPerFieldToJson`,
     `createJsonSchema`, custom `fromJson`/`toJson` tear-offs with
     optional/positional/generic parameters).

### Phase 2: Build the Combinatorial Matrix with `cartesianProduct`

Use `cartesianProduct` to expand orthogonal axes into `CodegenCase` entries.
Group `100-500` cases per `verifyGeneratorBatch` call so the Dart SDK and
package dependencies resolve once per batch (~1-2 seconds):

```dart
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:json_serializable/src/json_serializable_generator.dart';
import 'package:source_gen_test/source_gen_test.dart';
import 'package:test/test.dart';

const _typeSpecs = <String, ({String sample, String defaultLiteral})>{
  'int': (sample: '42', defaultLiteral: '0'),
  'int?': (sample: 'null', defaultLiteral: '0'),
  'List<int?>': (sample: '[1, null]', defaultLiteral: 'const []'),
  'Map<String, int?>': (sample: "{'a': 1, 'b': null}", defaultLiteral: 'const {}'),
};

void main() {
  test('JsonSerializableGenerator combinatorial matrix', () async {
    final axes = cartesianProduct<String, String>({
      'fieldType': _typeSpecs.keys.toList(),
      'includeIfNull': ['null', 'true', 'false'],
      'defaultValue': ['none', 'defaultVal'],
    });

    final cases = <CodegenCase>[];
    for (var i = 0; i < axes.length; i++) {
      final combo = axes[i];
      final className = 'FuzzCase$i';
      final type = combo['fieldType']!;
      final spec = _typeSpecs[type]!;
      final inc = combo['includeIfNull']!;
      final hasDefault = combo['defaultValue'] == 'defaultVal';
      cases.add(
        CodegenCase(
          id: 'case_${i}_${combo.values.join("_")}',
          declarations: '''
@JsonSerializable(includeIfNull: $inc)
class $className {
  final $type value;
  $className(${hasDefault ? '{this.value = ${spec.defaultLiteral}}' : 'this.value'});
  factory $className.fromJson(Map<String, dynamic> json) =>
      _\$${className}FromJson(json);
  Map<String, dynamic> toJson() => _\$${className}ToJson(this);
}
''',
          runtimeCheck: '''
final instance = $className(${hasDefault ? 'value: ${spec.sample}' : spec.sample});
final wire = jsonDecode(jsonEncode(instance.toJson())) as Map<String, dynamic>;
final decoded = $className.fromJson(wire);
if (!const DeepCollectionEquality().equals(
  jsonDecode(jsonEncode(decoded.toJson())),
  wire,
)) {
  throw StateError('Round-trip mismatch for $className: \$wire');
}
''',
        ),
      );
    }

    final report = await verifyGeneratorBatch(
      generator: JsonSerializableGenerator(),
      imports: const [
        "import 'dart:convert';",
        "import 'package:collection/collection.dart';",
        "import 'package:json_annotation/json_annotation.dart';",
        "import 'aux_types.dart';",
      ],
      preamble: '''
enum SharedStatus { active, paused }
int sharedFromJson(Object? v) => (v as num).toInt();
Object? sharedToJson(int v) => v;
''',
      auxiliaryFiles: const {
        'aux_types.dart': 'typedef CrossLibInt = int;\n',
      },
      cases: cases,
      failOnIssues: false,
    );
    expect(report.issues, isEmpty, reason: formatCodegenBatchReport(report));
  });
}
```

> [!IMPORTANT]
>
> - **Omit default arguments (`packageRoot: '.'`) under
>   `avoid_redundant_argument_values`**: `verifyGeneratorBatch` defaults
>   `packageRoot = '.'` and `failOnIssues = true`. Only pass `packageRoot` when
>   running from outside the target package directory, and pass
>   `failOnIssues: false` when asserting on `report.issues` directly via
>   `expect(report.issues, isEmpty, reason: formatCodegenBatchReport(report))`.
> - **Normalize JSON wire values (`jsonDecode(jsonEncode(...))`) and use
>   `DeepCollectionEquality` in `runtimeCheck`**: In generators like
>   `json_serializable` with `explicitToJson: false`, `toJson()` returns nested
>   custom objects and `Iterable`s in memory without converting them to JSON
>   maps/lists. Round-trip through `jsonDecode(jsonEncode(instance.toJson()))`
>   before calling `fromJson`, and bind `final expected = $expectedExpr;` before
>   string interpolation so string literals containing `'` do not break syntax
>   in `fuzz_batch_main.dart`.
> - **Place shared top-level helpers in `preamble:` and make them public when
>   referenced by `runtimeCheck`**: `CodegenCase.runtimeCheck` executes in a
>   separate entrypoint library (`fuzz_batch_main.dart`) that imports
>   `fuzz_batch.dart`. Any shared helper type or function in `preamble:` that is
>   referenced inside `runtimeCheck` must be public (not `_`-prefixed).
> - **Specify `elementName` when `declarations` contains multiple top-level
>   declarations**: `CodegenCase.elementName` defaults to the first top-level
>   declaration in `declarations`. When a `CodegenCase` defines per-case helper
>   mixins, base classes, or concrete subclasses alongside the annotated target
>   class, pass `elementName: className` explicitly.
> - **Expose library-private `_$` helpers via public members when asserting in
>   `runtimeCheck`**: Generators like `build_cli` or `json_serializable` emit
>   public top-level functions (`parse<Cls>`) alongside library-private symbols
>   (`_$populate<Cls>Parser`, `_$<Cls>Command`, `_$ClsJsonSchema`,
>   `_$ClsFieldMap`). Because `runtimeCheck` runs in `fuzz_batch_main.dart`,
>   expose a public static wrapper method or concrete subclass inside
>   `CodegenCase.declarations` to exercise library-private generated members.

### Phase 3: Understand the Three Built-In Oracles

`verifyGeneratorBatch` automatically runs all three verification stages and
isolates failures per case without aborting the rest of the batch:

1. **Oracle 1 -- Per-Case Diagnostic & Crash Isolation (`generatorException` /
   `unexpectedSuccess`)**:
   - Resolves the library in `AnalysisContextCollection` (with
     `part 'fuzz_batch.g.dart';` included), wraps it in a `LibraryReader`, and
     invokes the generator individually for each `CodegenCase` inside its own
     `try` / `catch` (passing `_MockBuildStep` to match `generateForElement`).
   - Any positive case that crashes in the generator is caught in `O(1)`
     directly on that case and recorded with its exact stack trace, while all
     surviving cases keep their exact per-case generated snippet.
   - Negative cases (`expectedError: ...`) assert that the generator rejects
     invalid declarations with a matching error message rather than crashing or
     silently emitting broken code.
2. **Oracle 2 -- Static Soundness with Exact Marker Attribution (`staticError`
   via `AnalysisSession.getErrors`)**:
   - Wraps each surviving case in `// === CASE:<id> ===` ...
     `// === END:<id> ===` inside **both** `fuzz_batch.dart` and
     `fuzz_batch.g.dart` (with `// ignore_for_file: type=lint`, deduplicating
     identical top-level helper declarations across cases while preserving
     `// ignore:` comments) and checks `AnalysisSession.getErrors` for both
     `Severity.error` and `Severity.warning` (catching
     `invalid_null_aware_operator`, `unnecessary_cast`,
     `dead_null_aware_expression`, invalid type bounds, and leaked private
     typedefs).
   - Statically non-compilable cases map back to their exact `CodegenCase.id`
     and `generatedCode` via marker offsets and are automatically stripped
     (without re-invoking the generator) before launching the runtime isolate.
3. **Oracle 3 -- Batched Runtime Round-Trip (`runtimeFailure` via
   `Isolate.spawnUri`)**:
   - Wraps every surviving `CodegenCase.runtimeCheck` in an isolated
     `runZonedGuarded` + `try` / `catch` inside a single `Isolate.spawnUri`
     script, streaming per-case completion events and verifying runtime
     round-trip equivalence.

### Phase 4: Structuring for Day-2 Maintenance & Surface-Area Drift Guards

When committing a permanent `verifyGeneratorBatch` suite into a package's
`test/` directory, structure it so future humans and agents can add new types,
annotation parameters, or builder options without hunting through multi-switch
control flow or leaving silent coverage gaps:

1. **Use Flat Spec Tables (`_TypeSpec`, `_FeatureSpec`), Never Parallel `switch`
   Chains**:
   - Store type and feature variations in self-contained `const` data records or
     classes (e.g. `const _typeSpecs = <_TypeSpec>[...]`,
     `const _featureSpecs = <_FeatureSpec>[...]`) and pass their indices into
     `cartesianProduct`.
   - Adding a new supported type or annotation feature should require adding
     **one** entry to a spec list rather than editing multiple `switch` blocks.
2. **Isolate Asymmetric Options from Uniform Round-Trip Templates**:
   - Options that omit generated methods (e.g. disabling `fromJson` or `toJson`
     generation), require custom constructor names, or ignore unannotated fields
     will fail compilation if forced into a uniform two-way round-trip class
     template.
   - Keep uniform features in the `cartesianProduct` slice and test asymmetric
     options in a dedicated slice with tailored class templates.
3. **Add a Dynamic Surface-Area Drift Guard Test**:
   - Do **not** maintain a static `const _coveredParams = {...}` set, which can
     be silenced by appending a string without writing a test case.
   - Instead, introspect the target package's annotation constructor parameters
     via `initializeLibraryReader` (and any canonical supported-type lists the
     generator exports), and scan the actual `CodegenCase.declarations` strings
     emitted by the positive slices to verify every non-deprecated parameter is
     genuinely exercised:

```dart
Set<String> extractExercisedAnnotationArgs(
  Iterable<CodegenCase> cases,
  String annotationName,
) {
  final pattern = RegExp('@$annotationName\\s*\\(([^)]*)\\)', multiLine: true);
  final argNamePattern = RegExp(r'(\b\w+)\s*:');
  return {
    for (final c in cases)
      for (final m in pattern.allMatches(c.declarations))
        for (final arg in argNamePattern.allMatches(m.group(1)!))
          arg.group(1)!,
  };
}

test('surface area drift guard: all annotation parameters are exercised', () async {
  final positiveCases = [...buildSlice1Cases(), ...buildSlice2Cases()];
  final reader = await initializeLibraryReader({
    'surface.dart': "export 'package:my_pkg/annotations.dart' show MyAnnotation;",
  }, 'surface.dart');

  final cls = reader.element.exportNamespace.definedNames2['MyAnnotation']
      as ClassElement;
  final expectedParams = {
    for (final p in cls.unnamedConstructor!.formalParameters)
      if (!p.metadata.hasDeprecated) p.name!,
  };
  final exercised = extractExercisedAnnotationArgs(
    positiveCases,
    'MyAnnotation',
  );

  expect(
    exercised,
    containsAll(expectedParams),
    reason: '''
Every non-deprecated parameter on @MyAnnotation must be exercised in at least
one positive CodegenCase (missing: ${expectedParams.difference(exercised)}).
Add an entry to `_typeSpecs` or `_featureSpecs` in this test file.
Uses `verifyGeneratorBatch` from `package:source_gen_test` (if using an AI
agent, load the bundled `source-gen-test-fuzz` skill via `dart run skills@ get`).
''',
  );
});
```

> [!NOTE]
>
> Always clean up any temporary scripts created during exploration so the target
> repository's `git status` stays completely clean unless staging a verified bug
> fix and regression test.
