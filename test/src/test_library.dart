import 'package:source_gen_test/annotations.dart';

import 'test_annotation.dart';

part 'test_part.dart';
part 'goldens/test_library_file_part_of_current.dart';

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

@ShouldGenerateFile(
  'goldens/test_library_file_no_part.dart',
  configurations: ['default', 'no-prefix-required'],
)
@ShouldThrow(
  'Uh...',
  configurations: ['vague'],
  element: false,
)
@TestAnnotation()
class TestClassFileNoPart {}

@ShouldGenerateFile(
  'goldens/test_library_file_part_of.dart',
  partOf: 'test_part_owner.dart',
  configurations: ['default', 'no-prefix-required'],
)
@ShouldThrow(
  'Uh...',
  configurations: ['vague'],
  element: false,
)
@TestAnnotation()
class TestClassFilePartOf {}

@ShouldGenerateFile(
  'goldens/test_library_file_part_of_current.dart',
  partOfCurrent: true,
  configurations: ['default', 'no-prefix-required'],
)
@ShouldThrow(
  'Uh...',
  configurations: ['vague'],
  element: false,
)
@TestAnnotation()
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
