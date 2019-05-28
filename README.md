<p align="center">
  <a href="https://travis-ci.org/kevmoo/source_gen_test">
    <img src="https://travis-ci.org/kevmoo/source_gen_test.svg?branch=master" alt="Build Status" />
  </a>
  <a href="https://pub.dev/packages/source_gen_test">
    <img src="https://img.shields.io/pub/v/source_gen_test.svg" alt="Pub Package Version" />
  </a>
</p>

Make it easy to test `Generators` derived from `package:source_gen` by
annotating test files.

```dart
@ShouldGenerate(
  r'''
const TestClass1NameLength = 10;

const TestClass1NameLowerCase = testclass1;
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

Other helpers are also provided.
