---
name: source-gen-fuzz
description: >-
  Stress-tests Dart source_gen Generator and GeneratorForAnnotation code
  generators by extracting AST control-flow branch axes, expanding combinatorial
  declaration matrices with cartesianProduct, and validating per-case generated
  output through verifyGeneratorBatch across diagnostic contracts, analyzer
  static errors and warnings, and batched Isolate.spawnUri runtime round-trip
  execution. Use when fuzzing or stress-testing a source_gen generator package,
  auditing code generator soundness across AST permutations, or running
  /source-gen-fuzz. Do not use for byte-stream parser fuzzing with libFuzzer
  (use fuzz) or single-case golden expectation updates.
---

# AST-Combinatorial `source_gen` Generator Fuzzing (`source-gen-fuzz`)

Unlike byte-stream parsers, a `package:source_gen` `Generator` or
`GeneratorForAnnotation<T>` (such as `json_serializable`, `built_value`,
`freezed`, or custom annotation generators) takes **valid, resolved Dart
declarations** (`ClassElement`, `FieldElement`, `DartType`, `ConstantReader`)
and emits Dart source code (`.g.dart`).

To uncover deep interaction bugs in a `Generator`, permute the **AST declaration
axes that flip control-flow branches inside the generator** and validate every
permutation with `verifyGeneratorBatch` from
`package:source_gen_test/source_gen_test.dart` in a single shared
`AnalysisContextCollection` and a single batched `Isolate.spawnUri` call.

## Quick Start

Run a standalone script (with `--enable-asserts` and `--packages` pointing to
the target package's or workspace's `.dart_tool/package_config.json`) or a
`dart test -c source` file in the target package directory:

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
const CodegenCase({
  required String id,
  required String declarations,
  String? elementName,
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
import 'package:json_annotation/json_annotation.dart';
import 'package:json_serializable/src/json_serializable_generator.dart';
import 'package:source_gen_test/source_gen_test.dart';

Future<void> main() async {
  final axes = cartesianProduct<String, String>({
    'fieldType': ['int', 'int?', 'List<int?>', 'Map<String, int?>'],
    'includeIfNull': ['null', 'true', 'false'],
    'defaultValue': ['none', 'defaultVal'],
  });

  final cases = <CodegenCase>[];
  for (var i = 0; i < axes.length; i++) {
    final combo = axes[i];
    final className = 'FuzzCase$i';
    final type = combo['fieldType']!;
    final inc = combo['includeIfNull']!;
    final hasDefault = combo['defaultValue'] == 'defaultVal';
    cases.add(
      CodegenCase(
        id: 'case_${i}_${combo.values.join("_")}',
        declarations: '''
@JsonSerializable(includeIfNull: $inc)
class $className {
  final $type value;
  $className(${hasDefault ? '{this.value = const []}' : 'this.value'});
  factory $className.fromJson(Map<String, dynamic> json) =>
      _\$${className}FromJson(json);
  Map<String, dynamic> toJson() => _\$${className}ToJson(this);
}
''',
        runtimeCheck: '''
final instance = $className(...);
final encoded = instance.toJson();
final decoded = $className.fromJson(encoded);
''',
      ),
    );
  }

  final report = await verifyGeneratorBatch(
    generator: JsonSerializableGenerator(),
    packageRoot: '.',
    imports: const [
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
  print('Passed ${report.passedCases}/${report.totalCases} cases.');
  if (report.issues.isNotEmpty) {
    print(formatCodegenBatchReport(report));
  }
}
```

> [!IMPORTANT]
>
> - **Place shared top-level helpers in `preamble:` and make them public when
>   referenced by `runtimeCheck`**: `CodegenCase.runtimeCheck` executes in a
>   separate entrypoint library (`fuzz_batch_main.dart`) that imports
>   `fuzz_batch.dart`. Any shared helper type or function in `preamble:` that is
>   referenced inside `runtimeCheck` must be public (not `_`-prefixed).
> - **One target `elementName` is generated per `CodegenCase` for
>   `GeneratorForAnnotation`**: The generator runs once per `CodegenCase` on its
>   target `elementName` (or across the per-case library for plain `Generator`
>   implementations, automatically deduplicating shared top-level helpers like
>   `const _$SharedStatusEnumMap` across cases in `fuzz_batch.g.dart`). If a
>   case references a helper class in `preamble:` or `declarations` that is not
>   the case's target `elementName`, give that helper class manual
>   `fromJson`/`toJson` methods rather than relying on `_$HelperFromJson`.
> - **Expose library-private `_$` helpers via public members when asserting in
>   `runtimeCheck`**: To inspect library-private symbols emitted into
>   `fuzz_batch.g.dart` (such as `_$ClsJsonSchema`, `_$ClsFieldMap`,
>   `_$ClsJsonKeys`, or `_$ClsPerFieldToJson`), expose a public static getter on
>   the test class inside `declarations` (for example,
>   `static Map<String, Object?> get schema => _$ClsJsonSchema;`).

### Phase 3: Understand the Three Built-In Oracles

`verifyGeneratorBatch` automatically runs all three verification stages and
isolates failures per case without aborting the rest of the batch:

1. **Oracle 1 -- Per-Case Diagnostic & Crash Isolation (`generatorException` /
   `unexpectedSuccess`)**:
   - Resolves the library in `AnalysisContextCollection` (with
     `part 'fuzz_batch.g.dart';` included), wraps it in a `LibraryReader`, and
     invokes the generator individually for each `CodegenCase` inside its own
     `try` / `catch`.
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
     script, streaming per-case completion events and verifying
     `fromJson(toJson())` round-trip equivalence at runtime.

> [!NOTE]
>
> Always clean up any temporary scripts created during exploration so the target
> repository's `git status` stays completely clean unless staging a verified bug
> fix and regression test.
