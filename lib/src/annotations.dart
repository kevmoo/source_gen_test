// ignore_for_file: comment_references
// Note: Should be importing the below libs instead, but we are avoiding imports
// in this file to speed up analyzer parsing!
// import 'package:source_gen/source_gen.dart';
// import 'test_annotated_classes.dart';

/// Non-public, implementation base class of  [ShouldGenerate] and
/// [ShouldThrow].
abstract class TestExpectation {
  final Iterable<String>? configurations;
  final List<String> expectedLogItems;

  const TestExpectation._(this.configurations, List<String>? expectedLogItems)
      : expectedLogItems = expectedLogItems ?? const [];

  TestExpectation replaceConfiguration(Iterable<String> newConfiguration);
}

/// Specifies the expected output for code generation on the annotated member.
///
/// Must be used with [testAnnotatedElements].
class ShouldGenerate extends TestExpectation {
  final String expectedOutput;
  final bool contains;

  const ShouldGenerate(
    this.expectedOutput, {
    this.contains = false,
    Iterable<String>? configurations,
    List<String>? expectedLogItems,
  }) : super._(configurations, expectedLogItems);

  @override
  TestExpectation replaceConfiguration(Iterable<String> newConfiguration) =>
      ShouldGenerate(
        expectedOutput,
        contains: contains,
        configurations: newConfiguration,
        expectedLogItems: expectedLogItems,
      );
}

/// Specifies that the expected output for code generation on the annotated
/// member is to match the file contents.
///
/// [expectedOutputFileName] is resolved relative to the file where
/// this annotation is found.
///
/// If [partOfCurrent] is true, the output file is expected to start with
/// the `part of` directive that links back to the current file.
///
/// If [partOf] is non-null, the output file is expected to start with
/// the `part of` directive that links to a given file.
///
/// If `SOURCE_GEN_TEST_UPDATE_GOLDENS` environment variable is set to `1`,
/// then instead of the comparison the output file will be generated
/// with whatever content the generator produces plus the appropriate
/// `part of` directive if any.
/// To do so, on Linux or Mac run the test as:
///
/// SOURCE_GEN_TEST_UPDATE_GOLDENS=1 dart test
///
/// To update a golden, the directory for its file must exist.
///
/// Must be used with [testAnnotatedElements].
class ShouldGenerateFile extends TestExpectation {
  final String expectedOutputFileName;
  final bool contains;
  final String? partOf;
  final bool partOfCurrent;

  const ShouldGenerateFile(
    this.expectedOutputFileName, {
    this.contains = false,
    this.partOf,
    this.partOfCurrent = false,
    Iterable<String>? configurations,
    List<String>? expectedLogItems,
  })  : assert(
          partOf == null || !partOfCurrent,
          'Cannot have both partOf and partOfCurrent',
        ),
        super._(configurations, expectedLogItems);

  @override
  TestExpectation replaceConfiguration(Iterable<String> newConfiguration) =>
      ShouldGenerateFile(
        expectedOutputFileName,
        contains: contains,
        partOf: partOf,
        partOfCurrent: partOfCurrent,
        configurations: newConfiguration,
        expectedLogItems: expectedLogItems,
      );
}

/// Specifies that an [InvalidGenerationSourceError] is expected to be thrown
/// when running generation for the annotated member.
///
/// Must be used with [testAnnotatedElements].
class ShouldThrow extends TestExpectation {
  final String errorMessage;
  final String? todo;

  /// If `null`, expects [InvalidGenerationSourceError.element] to match the
  /// element annotated with [ShouldThrow].
  ///
  /// If a [String], expects [InvalidGenerationSourceError.element] to match an
  /// element with the corresponding name.
  ///
  /// If `true`, [InvalidGenerationSourceError.element] is expected to be
  /// non-null.
  ///
  /// If `false`, [InvalidGenerationSourceError.element] is not checked.
  final dynamic element;

  const ShouldThrow(
    this.errorMessage, {
    this.todo,
    Object? element = true,
    Iterable<String>? configurations,
    List<String>? expectedLogItems,
  })  : element = element ?? true,
        super._(configurations, expectedLogItems);

  @override
  TestExpectation replaceConfiguration(Iterable<String> newConfiguration) =>
      ShouldThrow(
        errorMessage,
        configurations: newConfiguration,
        element: element,
        expectedLogItems: expectedLogItems,
        todo: todo,
      );
}
