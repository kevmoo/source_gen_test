import 'package:checks/checks.dart';
import 'package:source_gen/source_gen.dart';
import 'package:source_gen_test/src/build_log_tracking.dart';
import 'package:source_gen_test/src/generate_for_element.dart';
import 'package:source_gen_test/src/init_library_reader.dart';
import 'package:source_gen_test/src/test_annotated_classes.dart';
import 'package:test/scaffolding.dart';

import 'test_generator.dart';

const _testAnnotationContent = r'''
class TestAnnotation {
  const TestAnnotation();
}''';

Future<void> main() async {
  group('Bad annotations', () {
    test('duplicate configurations for the same member', () async {
      final badReader = await initializeLibraryReader({
        'bad_lib.dart': r"""
import 'package:source_gen_test/annotations.dart';
import 'annotations.dart';
@ShouldGenerate('', configurations: ['c'])
@ShouldGenerate('', configurations: ['c'])
@TestAnnotation()
class TestClass{}
""",
        'annotations.dart': _testAnnotationContent,
      }, 'bad_lib.dart');

      final error = check(
        () => testAnnotatedElements(badReader, const TestGenerator()),
      ).throws<InvalidGenerationSourceError>();
      error
          .has((e) => e.message, 'message')
          .equals(
            'There are multiple annotations for these configurations: "c".',
          );
      error
          .has((e) => e.todo, 'todo')
          .equals(
            'Ensure each configuration is only represented once per member.',
          );
    });

    test('annotation with no configuration', () async {
      final badReader = await initializeLibraryReader({
        'bad_lib.dart': r"""
import 'package:source_gen_test/annotations.dart';
import 'annotations.dart';
@ShouldGenerate('', configurations: [])
@TestAnnotation()
class EmptyConfig{}
""",
        'annotations.dart': _testAnnotationContent,
      }, 'bad_lib.dart');

      final error = check(
        () => testAnnotatedElements(badReader, const TestGenerator()),
      ).throws<InvalidGenerationSourceError>();
      error
          .has((e) => e.message, 'message')
          .equals('`configuration` cannot be empty.');
      error.has((e) => e.todo, 'todo').equals('Leave it `null`.');
    });
  });

  final reader = await initializeLibraryReaderForDirectory(
    'test/src',
    'test_library.dart',
  );

  group('generateForElement', () {
    test('TestClass1', () async {
      final output = await generateForElement(
        const TestGenerator(),
        reader,
        'TestClass1',
      );
      printOnFailure(output);
      check(output).equals(r'''
const TestClass1NameLength = 10;

const TestClass1NameLowerCase = 'testclass1';
''');
    });

    test('TestClass2', () async {
      final output = await generateForElement(
        const TestGenerator(),
        reader,
        'TestClass2',
      );
      printOnFailure(output);
      check(output).equals(r'''
const TestClass2NameLength = 10;

const TestClass2NameLowerCase = 'testclass2';
''');
    });
  });

  test('throwsInvalidGenerationSourceError', () async {
    await check(
      generateForElement(const TestGenerator(), reader, 'BadTestClass'),
    ).throws<InvalidGenerationSourceError>(
      (it) => it
        ..has(
          (e) => e.message,
          'message',
        ).equals('All classes must start with `TestClass`.')
        ..has(
          (e) => e.todo,
          'todo',
        ).equals('Rename the type or remove the `TestAnnotation` from class.'),
    );
  });

  group('testAnnotatedElements', () {
    const validAdditionalGenerators = {
      'no-prefix-required': TestGenerator(requireTestClassPrefix: false),
      'vague': TestGenerator(alwaysThrowVagueError: true),
    };

    const validExpectedAnnotatedTests = [
      'BadTestClass',
      'BadTestClass',
      'BadTestClass',
      'badTestFunc',
      'badTestFunc',
      'TestClass1',
      'TestClass1',
      'TestClass2',
      'TestClass2',
      'TestClassFileNoPart',
      'TestClassFileNoPart',
      'TestClassFilePartOf',
      'TestClassFilePartOf',
      'TestClassFilePartOfCurrent',
      'TestClassFilePartOfCurrent',
      'TestClassWithBadMember',
      'badTestField',
      'badTestField',
    ];

    group('[integration tests]', () {
      initializeBuildLogTracking();
      testAnnotatedElements(
        reader,
        const TestGenerator(),
        additionalGenerators: validAdditionalGenerators,
        expectedAnnotatedTests: validExpectedAnnotatedTests,
      );
    });

    group('test counts', () {
      test('nul defaultConfiguration', () {
        final list = getAnnotatedClasses(
          reader,
          const TestGenerator(),
          additionalGenerators: validAdditionalGenerators,
          expectedAnnotatedTests: validExpectedAnnotatedTests,
        );

        check(list).length.equals(25);
      });

      test('valid configuration', () {
        final list = getAnnotatedClasses(
          reader,
          const TestGenerator(),
          additionalGenerators: validAdditionalGenerators,
          expectedAnnotatedTests: validExpectedAnnotatedTests,
          defaultConfiguration: ['default', 'no-prefix-required', 'vague'],
        );

        check(list).length.equals(25);
      });

      test('different defaultConfiguration', () {
        final list = getAnnotatedClasses(
          reader,
          const TestGenerator(),
          additionalGenerators: validAdditionalGenerators,
          expectedAnnotatedTests: validExpectedAnnotatedTests,
          defaultConfiguration: ['default'],
        );

        check(list).length.equals(22);
      });

      test('different defaultConfiguration', () {
        final list = getAnnotatedClasses(
          reader,
          const TestGenerator(),
          additionalGenerators: validAdditionalGenerators,
          expectedAnnotatedTests: validExpectedAnnotatedTests,
          defaultConfiguration: ['no-prefix-required'],
        );

        check(list).length.equals(22);
      });
    });
    group('defaultConfiguration', () {
      test('empty', () {
        _checkArgumentError(
          () => testAnnotatedElements(
            reader,
            const TestGenerator(),
            additionalGenerators: validAdditionalGenerators,
            defaultConfiguration: [],
          ),
          'Cannot be empty.',
          'defaultConfiguration',
        );
      });

      test('unknown item', () {
        _checkArgumentError(
          () => testAnnotatedElements(
            reader,
            const TestGenerator(),
            additionalGenerators: const {
              'no-prefix-required': TestGenerator(
                requireTestClassPrefix: false,
              ),
            },
            defaultConfiguration: ['unknown'],
          ),
          'Contains values not associated with provided generators: '
              '"unknown".',
          'defaultConfiguration',
        );
      });
    });

    group('expectedAnnotatedTests', () {
      test('too many', () {
        _checkArgumentError(
          () => testAnnotatedElements(
            reader,
            const TestGenerator(),
            expectedAnnotatedTests: [
              'TestClass1',
              'TestClass2',
              'BadTestClass',
              'extra',
            ],
          ),
          'There are unexpected items',
          'expectedAnnotatedTests',
        );
      });

      test('too few', () {
        _checkArgumentError(
          () => testAnnotatedElements(
            reader,
            const TestGenerator(),
            expectedAnnotatedTests: ['TestClass1', 'TestClass2'],
          ),
          'There are items missing',
          'expectedAnnotatedTests',
        );
      });
    });

    group('additionalGenerators', () {
      test('unused generator fails', () {
        _checkArgumentError(
          () => testAnnotatedElements(
            reader,
            const TestGenerator(),
            additionalGenerators: {'extra': const TestGenerator()}
              ..addAll(validAdditionalGenerators),
            expectedAnnotatedTests: [
              'TestClass1',
              'TestClass2',
              'BadTestClass',
              'BadTestClass',
              'badTestFunc',
              'badTestFunc',
            ],
            // 'vague' is excluded here!
            defaultConfiguration: ['default', 'no-prefix-required'],
          ),
          'Some of the specified generators were not used for their '
          'corresponding configurations: "extra".\n'
          'Remove the entry from `additionalGenerators` or update '
          '`defaultConfiguration`.',
        );
      });

      test('missing a specified generator fails', () {
        _checkArgumentError(
          () => testAnnotatedElements(reader, const TestGenerator()),
          'There are elements defined with configurations with no '
          'associated generator provided.\n'
          '`BadTestClass`: "no-prefix-required", "vague"; '
          '`TestClass1`: "no-prefix-required", "vague"; '
          '`TestClass2`: "vague"; '
          '`TestClassFileNoPart`: "no-prefix-required", "vague"; '
          '`TestClassFilePartOf`: "no-prefix-required", "vague"; '
          '`TestClassFilePartOfCurrent`: "no-prefix-required", "vague"; '
          '`badTestField`: "vague"; '
          '`badTestFunc`: "vague"',
        );
      });

      test('key "default" not allowed', () {
        _checkArgumentError(
          () => testAnnotatedElements(
            reader,
            const TestGenerator(),
            additionalGenerators: const {
              'default': TestGenerator(requireTestClassPrefix: false),
            },
          ),
          'Contained an unsupported key "default".',
          'additionalGenerators',
        );
      });

      test('key "" not allowed', () {
        _checkArgumentError(
          () => testAnnotatedElements(
            reader,
            const TestGenerator(),
            additionalGenerators: const {
              '': TestGenerator(requireTestClassPrefix: false),
            },
          ),
          'Contained an unsupported key "".',
          'additionalGenerators',
        );
      });
    });
  });
}

void _checkArgumentError(
  void Function() callback,
  String expectedMessagePart, [
  String? expectedName,
]) {
  final error = check(callback).throws<ArgumentError>();
  error
      .has((e) => e.message, 'message')
      .isA<String>()
      .contains(expectedMessagePart);
  if (expectedName != null) {
    error.has((e) => e.name, 'name').equals(expectedName);
  }
}
