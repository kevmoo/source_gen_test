import 'dart:async';

import 'package:source_gen_test/src/build_log_tracking.dart';
import 'package:source_gen_test/src/init_library_reader.dart';
import 'package:source_gen_test/src/test_annotated_classes.dart';

import 'example_generator.dart';
import 'src/example_annotation.dart';

Future<void> main() async {
  final reader = await initializeLibraryReaderForDirectory(
    'example/src',
    'example_test_src.dart',
  );

  initializeBuildLogTracking();
  testAnnotatedElements<ExampleAnnotation>(
    reader,
    const ExampleGenerator(),
    additionalGenerators: const {
      'no-prefix-required': ExampleGenerator(requireTestClassPrefix: false)
    },
  );
}
