part of 'test_library.dart';

@ShouldGenerate(
  r'''
const TestClass2NameLength = 10;

const TestClass2NameLowerCase = 'testclass2';
''',
)
@ShouldThrow(
  'Uh...',
  configurations: ['vague'],
  element: false,
)
@TestAnnotation()
class TestClass2 {}
