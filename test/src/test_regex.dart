import 'package:source_gen_test/annotations.dart';

import 'test_annotation.dart';

@ShouldGenerate(
  r'''
const [A-Z]{1}[a-zA-Z]*NameLength = \d+;

const [A-Z]{1}[a-zA-Z]*NameLowerCase = [a-z]+;
''',
  contains: true,
)
@TestAnnotation()
class TestClass {}
