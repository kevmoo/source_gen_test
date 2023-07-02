import 'package:source_gen_test/annotations.dart';

import 'example_annotation.dart';

@ShouldGenerate(
  r'''
const TestClass1NameLength = 10;

const TestClass1NameLowerCase = 'testclass1';
''',
  configurations: ['default', 'no-prefix-required'],
)
@ExampleAnnotation()
class TestClass1 {}

@ShouldGenerate(
  r'''
const TestClass2NameLength = 10;

const TestClass2NameLowerCase = 'testclass2';

const TestClass2NameUpperCase = 'TESTCLASS2';
''',
  configurations: ['default', 'no-prefix-required'],
)
@ExampleAnnotation(includeUpperCase: true)
class TestClass2 {}

@ShouldGenerateFile(
  'example_test_golden.dart',
  partOfCurrent: true,
  configurations: ['default', 'no-prefix-required'],
)
@ExampleAnnotation()
class TestClassFilePartOfCurrent {}

@ShouldGenerate(
  r'''
const BadTestClassNameLength = 12;

const BadTestClassNameLowerCase = 'badtestclass';
''',
  configurations: ['no-prefix-required'],
  expectedLogItems: ['This member might be not good.'],
)
@ShouldThrow(
  'All classes must start with `TestClass`.',
  todo: 'Rename the type or remove the `TestAnnotation` from class.',
  configurations: ['default'],
  expectedLogItems: ['This member might be not good.'],
)
@ExampleAnnotation()
class BadTestClass {}

@ShouldThrow(
  'Only supports annotated classes.',
  todo: 'Remove `TestAnnotation` from the associated element.',
)
@ExampleAnnotation()
int anotherExampleFunction() => 42;
