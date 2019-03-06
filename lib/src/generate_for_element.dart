// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:dart_style/dart_style.dart' as dart_style;
import 'package:source_gen/source_gen.dart';
import 'package:source_gen/src/output_helpers.dart'
    show normalizeGeneratorOutput;

final _formatter = dart_style.DartFormatter();

Future<String> generateForElement(
  GeneratorForAnnotation generator,
  LibraryReader libraryReader,
  String name,
) async {
  final elements =
      libraryReader.allElements.where((e) => e.name == name).toList();

  if (elements.isEmpty) {
    throw ArgumentError.value(
        name, 'name', 'Could not find an element with name `$name`.');
  }

  Element element;

  if (elements.length == 1) {
    element = elements[0];
  } else {
    final rootProperties =
        elements.whereType<PropertyInducingElement>().toList();
    if (rootProperties.length == 1) {
      element = rootProperties[0];
    } else {
      throw UnimplementedError();
    }
  }

  final annotation = generator.typeChecker.firstAnnotationOf(element);

  final generatedStream = normalizeGeneratorOutput(generator
      .generateForAnnotatedElement(element, ConstantReader(annotation), null));

  final generated = await generatedStream.join('\n\n');

  return _formatter.format(generated);
}
