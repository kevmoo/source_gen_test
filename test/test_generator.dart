import 'package:analyzer/dart/element/element2.dart';
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
    Element2 element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) sync* {
    if (alwaysThrowVagueError) {
      throw InvalidGenerationSourceError('Uh...');
    }

    if (element.name3!.contains('Bad')) {
      log.info('This member might be not good.');
    }

    if (element is ClassElement2) {
      final unsupportedFunc = element.methods2.firstWhereOrNull(
        (me) => me.name3!.contains('unsupported'),
      );

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
  }

  @override
  String toString() =>
      'TestGenerator (requireTestClassPrefix:$requireTestClassPrefix)';
}
