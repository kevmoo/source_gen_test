[![Pub package](https://img.shields.io/pub/v/source_gen_test.svg)](https://pub.dev/packages/source_gen_test)
[![CI](https://github.com/kevmoo/source_gen_test/actions/workflows/ci.yml/badge.svg)](https://github.com/kevmoo/source_gen_test/actions/workflows/ci.yml)
[![package publisher](https://img.shields.io/pub/publisher/source_gen_test.svg)](https://pub.dev/packages/source_gen_test/publisher)

Make it easy to test `Generators` derived from `package:source_gen` by
annotating test files.

```dart
@ShouldGenerate(
  r'''
const TestClass1NameLength = 10;

const TestClass1NameLowerCase = 'testclass1';
''',
  configurations: ['default', 'no-prefix-required'],
)
@ShouldThrow(
  'Uh...',
  configurations: ['vague'],
  element: false,
)
@TestAnnotation()
class TestClass1 {}
```

Test against a golden output file if you also want to write tests on the output
itself.

```dart
part 'goldens/testclass2.dart';

@ShouldGenerateFile(
  'goldens/testclass2.dart',
  partOfCurrent: true,
  configurations: ['default', 'no-prefix-required'],
)
@ShouldThrow(
  'Uh...',
  configurations: ['vague'],
  element: false,
)
@TestAnnotation()
class TestClass2 {}
```

Other helpers are also provided.

## Combinatorial Batch Verification (`verifyGeneratorBatch`)

Use `cartesianProduct` and `verifyGeneratorBatch` to validate large matrices of
AST/declaration permutations against a `Generator` or `GeneratorForAnnotation`
in a single shared `package:analyzer` context and batched `Isolate.spawnUri`
runtime pass:

```dart
final axes = cartesianProduct({
  'fieldType': ['int', 'int?', 'List<int?>'],
  'includeIfNull': ['true', 'false'],
});

final report = await verifyGeneratorBatch(
  generator: MyGenerator(),
  imports: const ["import 'package:my_pkg/annotations.dart';"],
  cases: [
    for (var i = 0; i < axes.length; i++)
      CodegenCase(
        id: 'case_$i',
        declarations: '''
@MyAnnotation(includeIfNull: ${axes[i]['includeIfNull']})
class Case$i {
  final ${axes[i]['fieldType']} value;
  Case$i(this.value);
}
''',
        runtimeCheck: 'final c = Case$i(null);',
      ),
  ],
);
```
