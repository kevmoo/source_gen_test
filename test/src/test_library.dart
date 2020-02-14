import 'package:source_gen_test/annotations.dart';

import 'test_annotation.dart';

part 'test_part.dart';

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

@ShouldGenerate(
  r'''
const BadTestClassNameLength = 12;

const BadTestClassNameLowerCase = badtestclass;
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
@ShouldThrow(
  'Uh...',
  configurations: ['vague'],
  element: false,
)
@TestAnnotation()
class BadTestClass {}

@ShouldThrow(
  'Cannot generate for classes with members that include `unsupported` in '
  'their name.',
  element: 'unsupportedFunc',
  configurations: ['default'],
  expectedLogItems: ['This member might be not good.'],
)
@TestAnnotation()
class TestClassWithBadMember {
  void unsupportedFunc() {}
}

@ShouldThrow(
  'Only supports annotated classes.',
  todo: 'Remove `TestAnnotation` from the associated element.',
)
@ShouldThrow(
  'Uh...',
  configurations: ['vague'],
  element: false,
)
@TestAnnotation()
int badTestFunc() => 42;

@ShouldThrow(
  'Only supports annotated classes.',
  todo: 'Remove `TestAnnotation` from the associated element.',
)
@ShouldThrow(
  'Uh...',
  configurations: ['vague'],
  element: false,
)
@TestAnnotation()
const badTestField = 42;
