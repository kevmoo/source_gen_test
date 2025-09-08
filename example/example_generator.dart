import 'package:analyzer/dart/element/element2.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/example_annotation.dart';

class ExampleGenerator extends GeneratorForAnnotation<ExampleAnnotation> {
  final bool requireTestClassPrefix;

  const ExampleGenerator({this.requireTestClassPrefix = true});

  @override
  Iterable<String> generateForAnnotatedElement(
    Element2 element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) sync* {
    assert(!annotation.isNull, 'The source annotation should be set!');

    if (element.name3!.contains('Bad')) {
      log.info('This member might be not good.');
    }

    if (element is! ClassElement2) {
      throw InvalidGenerationSourceError(
        'Only supports annotated classes.',
        todo: 'Remove `TestAnnotation` from the associated element.',
        element: element,
      );
    }

    if (requireTestClassPrefix && !element.name3!.startsWith('TestClass')) {
      throw InvalidGenerationSourceError(
        'All classes must start with `TestClass`.',
        todo: 'Rename the type or remove the `TestAnnotation` from class.',
        element: element,
      );
    }

    yield 'const ${element.name3!}NameLength = ${element.name3!.length};';
    yield 'const ${element.name3!}NameLowerCase = '
        "'${element.name3!.toLowerCase()}';";

    if (annotation.read('includeUpperCase').literalValue as bool) {
      yield 'const ${element.name3!}NameUpperCase = '
          "'${element.name3!.toUpperCase()}';";
    }
  }

  @override
  String toString() =>
      'TestGenerator (requireTestClassPrefix:$requireTestClassPrefix)';
}
