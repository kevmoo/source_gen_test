import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'goldens.dart';
import 'init_library_reader.dart';
import 'test_build_result.dart';
import 'test_build_step.dart';

Future<TestBuildResult> generateForLibrary<T>(
  GeneratorForAnnotation<T> generator,
  LibraryReader libraryReader, [
  BuildStep? buildStep,
]) async {
  buildStep ??= MockBuildStep();
  final generatedCode = await generator.generate(libraryReader, buildStep);

  // set generated code for the main output asset
  if (buildStep is! MockBuildStep) {
    await buildStep.writeAsString(
      buildStep.allowedOutputs.first,
      generatedCode,
    );
  }

  if (updateGoldens) {
    final step = _check<TestBuildStep>(buildStep, 'buildStep');
    final reader = _check<PathAwareLibraryReader>(
      libraryReader,
      'libraryReader',
    );
    await step.saveGoldens(reader.directory);
  }

  return TestBuildResult.from(buildStep);
}

T _check<T>(Object? instance, String name) {
  if (instance is T) return instance;
  throw InvalidGenerationSourceError(
    'To create or update all golden files, $name must be an instance of $T '
    'it is currently an instance of ${instance.runtimeType}.',
  );
}
