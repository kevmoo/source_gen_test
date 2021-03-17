import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:collection/collection.dart';
import 'package:source_gen/source_gen.dart';

import 'src/test_annotation.dart';

class TestGenerator extends GeneratorForAnnotation<TestAnnotation> {
  final bool requireTestClassPrefix;
  final bool alwaysThrowVagueError;

  const TestGenerator({
    this.requireTestClassPrefix = true,
    this.alwaysThrowVagueError = false,
  });

  @override
  Iterable<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) sync* {
    if (alwaysThrowVagueError) {
      throw InvalidGenerationSourceError('Uh...');
    }

    if (element.name!.contains('Bad')) {
      log.info('This member might be not good.');
    }

    if (element is ClassElement) {
      final unsupportedFunc = element.methods
          .firstWhereOrNull((me) => me.name.contains('unsupported'));

      if (unsupportedFunc != null) {
        throw InvalidGenerationSourceError(
          'Cannot generate for classes with members that include '
          '`unsupported` in their name.',
          element: unsupportedFunc,
        );
      }
    } else {
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
  }

  @override
  String toString() =>
      'TestGenerator (requireTestClassPrefix:$requireTestClassPrefix)';
}
