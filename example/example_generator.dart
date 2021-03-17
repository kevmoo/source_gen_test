import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/example_annotation.dart';

class ExampleGenerator extends GeneratorForAnnotation<ExampleAnnotation> {
  final bool requireTestClassPrefix;

  const ExampleGenerator({
    this.requireTestClassPrefix = true,
  });

  @override
  Iterable<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) sync* {
    assert(!annotation.isNull, 'The source annotation should be set!');

    if (element.name!.contains('Bad')) {
      log.info('This member might be not good.');
    }

    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        'Only supports annotated classes.',
        todo: 'Remove `TestAnnotation` from the associated element.',
        element: element,
      );
    }

    if (requireTestClassPrefix && !element.name.startsWith('TestClass')) {
      throw InvalidGenerationSourceError(
        'All classes must start with `TestClass`.',
        todo: 'Rename the type or remove the `TestAnnotation` from class.',
        element: element,
      );
    }

    yield 'const ${element.name}NameLength = ${element.name.length};';
    yield 'const ${element.name}NameLowerCase = ${element.name.toLowerCase()};';

    if (annotation.read('includeUpperCase').literalValue as bool) {
      yield 'const ${element.name}NameUpperCase = '
          '${element.name.toUpperCase()};';
    }
  }

  @override
  String toString() =>
      'TestGenerator (requireTestClassPrefix:$requireTestClassPrefix)';
}
