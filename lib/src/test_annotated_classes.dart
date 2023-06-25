import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';

import 'annotations.dart';
import 'build_log_tracking.dart';
import 'expectation_element.dart';
import 'generate_for_element.dart';
import 'init_library_reader.dart';
import 'matchers.dart';

const _defaultConfigurationName = 'default';
const _updateGoldensVariable = 'SOURCE_GEN_TEST_UPDATE_GOLDENS';

/// If [defaultConfiguration] is not provided or `null`, "default" and the keys
/// from [additionalGenerators] (if provided) are used.
///
/// Tests registered by this function assume [initializeBuildLogTracking] has
/// been called.
///
/// If [expectedAnnotatedTests] is provided, it should contain the names of the
/// members in [libraryReader] that are annotated for testing. If the same
/// element is annotated for multiple tests, it should appear in the list
/// the same number of times.
void testAnnotatedElements<T>(
  LibraryReader libraryReader,
  GeneratorForAnnotation<T> defaultGenerator, {
  Map<String, GeneratorForAnnotation<T>>? additionalGenerators,
  Iterable<String>? expectedAnnotatedTests,
  Iterable<String>? defaultConfiguration,
}) {
  for (var entry in getAnnotatedClasses<T>(
    libraryReader,
    defaultGenerator,
    additionalGenerators: additionalGenerators,
    expectedAnnotatedTests: expectedAnnotatedTests,
    defaultConfiguration: defaultConfiguration,
  )) {
    entry._registerTest();
  }
}

/// An implementation member only exposed to make it easier to test
/// [testAnnotatedElements] without registering any tests.
@visibleForTesting
List<AnnotatedTest<T>> getAnnotatedClasses<T>(
  LibraryReader libraryReader,
  GeneratorForAnnotation<T> defaultGenerator, {
  Map<String, GeneratorForAnnotation<T>>? additionalGenerators,
  Iterable<String>? expectedAnnotatedTests,
  Iterable<String>? defaultConfiguration,
}) {
  final generators = <String, GeneratorForAnnotation<T>>{
    _defaultConfigurationName: defaultGenerator,
  };
  if (additionalGenerators != null) {
    for (var invalidKey in const [_defaultConfigurationName, '']) {
      if (additionalGenerators.containsKey(invalidKey)) {
        throw ArgumentError.value(
          additionalGenerators,
          'additionalGenerators',
          'Contained an unsupported key "$invalidKey".',
        );
      }
    }
    if (additionalGenerators.containsKey(null)) {
      throw ArgumentError.value(
        additionalGenerators,
        'additionalGenerators',
        'Contained an unsupported key `null`.',
      );
    }
    generators.addAll(additionalGenerators);
  }

  Set<String> defaultConfigSet;

  if (defaultConfiguration != null) {
    defaultConfigSet = defaultConfiguration.toSet();
    if (defaultConfigSet.isEmpty) {
      throw ArgumentError.value(
        defaultConfiguration,
        'defaultConfiguration',
        'Cannot be empty.',
      );
    }

    final unknownShouldThrowDefaults =
        defaultConfigSet.where((v) => !generators.containsKey(v)).toSet();
    if (unknownShouldThrowDefaults.isNotEmpty) {
      throw ArgumentError.value(
        defaultConfiguration,
        'defaultConfiguration',
        'Contains values not associated with provided generators: '
            '${unknownShouldThrowDefaults.map((v) => '"$v"').join(', ')}.',
      );
    }
  } else {
    defaultConfigSet = generators.keys.toSet();
  }

  final annotatedElements =
      genAnnotatedElements(libraryReader, defaultConfigSet);

  final unusedConfigurations = generators.keys.toSet();
  for (var annotatedElement in annotatedElements) {
    unusedConfigurations
        .removeAll(annotatedElement.expectation.configurations!);
  }
  if (unusedConfigurations.isNotEmpty) {
    if (unusedConfigurations.contains(_defaultConfigurationName)) {
      throw ArgumentError(
        'The `defaultGenerator` is not used by any annotated elements.',
      );
    }

    throw ArgumentError(
      'Some of the specified generators were not used for their corresponding '
      'configurations: '
      '${unusedConfigurations.map((c) => '"$c"').join(', ')}.\n'
      'Remove the entry from `additionalGenerators` or update '
      '`defaultConfiguration`.',
    );
  }

  if (expectedAnnotatedTests != null) {
    final expectedList = expectedAnnotatedTests.toList();

    final missing = <String>[];

    for (var elementName in annotatedElements.map((e) => e.elementName)) {
      if (!expectedList.remove(elementName)) {
        missing.add(elementName);
      }
    }

    if (expectedList.isNotEmpty) {
      throw ArgumentError.value(
        expectedList.map((e) => "'$e'").join(', '),
        'expectedAnnotatedTests',
        'There are unexpected items',
      );
    }
    if (missing.isNotEmpty) {
      throw ArgumentError.value(
        missing.map((e) => "'$e'").join(', '),
        'expectedAnnotatedTests',
        'There are items missing',
      );
    }
  }

  final result = <AnnotatedTest<T>>[];

  // element name -> missing configs
  final mapMissingConfigs = <String, Set<String>>{};

  for (final entry in annotatedElements) {
    for (var configuration in entry.expectation.configurations!) {
      final generator = generators[configuration];

      if (generator == null) {
        mapMissingConfigs
            .putIfAbsent(entry.elementName, () => <String>{})
            .add(configuration);
        continue;
      }

      result.add(
        AnnotatedTest<T>._(
          libraryReader,
          generator,
          configuration,
          entry.elementName,
          entry.expectation,
        ),
      );
    }
  }

  if (mapMissingConfigs.isNotEmpty) {
    final elements = mapMissingConfigs.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final message = elements.map((e) {
      final sortedConfigs =
          (e.value.toList()..sort()).map((v) => '"$v"').join(', ');
      return '`${e.key}`: $sortedConfigs';
    }).join('; ');

    throw ArgumentError(
      'There are elements defined with configurations with no associated '
      'generator provided.\n$message',
    );
  }

  return result;
}

@visibleForTesting
class AnnotatedTest<T> {
  final GeneratorForAnnotation<T> generator;
  final String configuration;
  final LibraryReader _libraryReader;
  final TestExpectation expectation;
  final String _elementName;

  String get _testName {
    var value = _elementName;
    if (configuration != _defaultConfigurationName) {
      value += ' with configuration "$configuration"';
    }
    return value;
  }

  AnnotatedTest._(
    this._libraryReader,
    this.generator,
    this.configuration,
    this._elementName,
    this.expectation,
  );

  void _registerTest() {
    if (expectation is ShouldGenerate) {
      test(_testName, _shouldGenerateTest);
      return;
    } else if (expectation is ShouldGenerateFile) {
      test(_testName, _shouldGenerateFileTest);
      return;
    } else if (expectation is ShouldThrow) {
      test(_testName, _shouldThrowTest);
      return;
    }
    throw StateError('Should never get here.');
  }

  Future<String> _generate() =>
      generateForElement<T>(generator, _libraryReader, _elementName);

  Future<void> _shouldGenerateTest() async {
    final output = await _generate();
    final exp = expectation as ShouldGenerate;

    try {
      expect(
        output,
        exp.contains
            ? contains(exp.expectedOutput)
            : equals(exp.expectedOutput),
      );
    } on TestFailure {
      printOnFailure("ACTUAL CONTENT:\nr'''\n$output'''");
      rethrow;
    }

    expect(
      buildLogItems,
      exp.expectedLogItems,
      reason: 'The expected log items do not match.',
    );
    clearBuildLog();
  }

  Future<void> _shouldGenerateFileTest() async {
    final output = await _generate();
    final exp = expectation as ShouldGenerateFile;

    if (_libraryReader is! PathAwareLibraryReader) {
      throw TestFailure(
        'Cannot run the test because _libraryReader does not contain '
        'the directory information, and so the golden cannot be located. '
        'Use initializeLibraryReaderForDirectory() to automatically set it.',
      );
    }

    final reader = _libraryReader as PathAwareLibraryReader;
    final path = p.join(reader.directory, exp.expectedOutputFileName);
    final testOutput = _padOutputForFile(output);

    try {
      if (Platform.environment[_updateGoldensVariable] == '1') {
        File(path).writeAsStringSync(testOutput);
      } else {
        final content = File(path).readAsStringSync();
        expect(
          testOutput,
          exp.contains ? contains(content) : equals(content),
        );
      }
    } on FileSystemException catch (ex) {
      throw TestFailure(
        'Cannot open file: ${exp.expectedOutputFileName}\n'
        'Absolute path:    ${Directory.current.path}/$path\n'
        '$ex\n\n'
        'To create or update all golden files, set the environment variable '
        '$_updateGoldensVariable=1\n\n'
        'Make sure the directory exists and you can write the file in it.',
      );
    } on TestFailure {
      printOnFailure("ACTUAL CONTENT:\nr'''\n$output'''");
      printOnFailure(
        'To update all golden files, set the environment variable '
        '$_updateGoldensVariable=1',
      );
      rethrow;
    }

    expect(
      buildLogItems,
      exp.expectedLogItems,
      reason: 'The expected log items do not match.',
    );
    clearBuildLog();
  }

  String _padOutputForFile(String output) {
    final exp = expectation as ShouldGenerateFile;

    if (exp.partOf != null) {
      return "part of '${exp.partOf}';\n\n$output";
    }

    if (exp.partOfCurrent) {
      final reader = _libraryReader as PathAwareLibraryReader;
      final outputDirectory =
          File(p.join(reader.directory, exp.expectedOutputFileName)).parent;

      final path = p.relative(
        reader.path,
        from: outputDirectory.path,
      );
      return "part of '$path';\n\n$output";
    }

    return output;
  }

  Future<void> _shouldThrowTest() async {
    final exp = expectation as ShouldThrow;

    Matcher? elementMatcher;

    if (exp.element == null || exp.element is String) {
      String expectedElementName;
      if (exp.element == null) {
        expectedElementName = _elementName;
      } else {
        assert(exp.element is String);
        expectedElementName = exp.element as String;
      }
      elementMatcher = const TypeMatcher<Element>()
          .having((e) => e.name, 'name', expectedElementName);
    } else if (exp.element == true) {
      elementMatcher = isNotNull;
    } else {
      assert(exp.element == false);
    }

    await expectLater(
      _generate,
      throwsInvalidGenerationSourceError(
        exp.errorMessage,
        todoMatcher: exp.todo,
        elementMatcher: elementMatcher,
      ),
    );

    expect(
      buildLogItems,
      exp.expectedLogItems,
      reason: 'The expected log items do not match.',
    );
    clearBuildLog();
  }
}
