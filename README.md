<a href="https://pub.dev/packages/source_gen_test">
<img src="https://img.shields.io/pub/v/source_gen_test.svg" alt="Pub Package Version" />
</a>

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

Test against a golden output if you also want to write tests on the output itself.

```dart
part 'goldens/testclass2.dart';

@ShouldGenerateGolden(
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
