import 'package:source_gen_test/src/build_log_tracking.dart';
import 'package:source_gen_test/src/init_library_reader.dart';
import 'package:source_gen_test/src/test_annotated_classes.dart';

import 'src/test_annotation.dart';
import 'test_generator.dart';

Future<void> main() async {
  initializeBuildLogTracking();
  final reader = await initializeLibraryReaderForDirectory(
    'test/src',
    'test_regex.dart',
  );
  testAnnotatedElements<TestAnnotation>(
    reader,
    const TestGenerator(),
  );
}
