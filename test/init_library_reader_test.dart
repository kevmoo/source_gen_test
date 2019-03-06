import 'dart:io';

import 'package:source_gen_test/src/init_library_reader.dart';
import 'package:test/test.dart';

Object _skipDart200() {
  final travisDartVersion = Platform.environment['TRAVIS_DART_VERSION'];
  if (travisDartVersion == '2.0.0') {
    return 'Skipping on Dart 2.0.0';
  }
  return null;
}

// TODO: test initializeLibraryReader - but since
//  `initializeLibraryReaderForDirectory` wraps it, not a big hurry
void main() {
  group('initializeLibraryReaderForDirectory', () {
    test('valid', () async {
      final reader = await initializeLibraryReaderForDirectory(
          'test/src', 'test_library.dart');

      expect(
        reader.allElements.map((e) => e.name),
        unorderedMatches([
          'BadTestClass',
          'badTestField',
          'badTestField',
          'badTestFunc',
          'TestClass1',
          'TestClass2',
          'TestClassWithBadMember',
        ]),
      );
    });

    test('bad library name', () async {
      await expectLater(
        () => initializeLibraryReaderForDirectory(
            'test/src', 'test_library_bad.dart'),
        throwsA(isArgumentError
            .having((ae) => ae.message, 'message',
                'Must exist as a file in `sourceDirectory`.')
            .having((ae) => ae.name, 'name', 'targetLibraryFileName')),
      );
    });

    test('non-existant directory', () async {
      await expectLater(
          () => initializeLibraryReaderForDirectory(
              'test/not_src', 'test_library.dart'),
          throwsA(const TypeMatcher<FileSystemException>()));
    });

    test('part instead', () async {
      await expectLater(
        () => initializeLibraryReaderForDirectory('test/src', 'test_part.dart'),
        throwsA(isArgumentError
            .having((ae) => ae.message, 'message',
                'Does not seem to reference a Dart library.')
            .having((ae) => ae.name, 'name', 'targetLibraryFileName')),
      );
    }, skip: _skipDart200());
  });
}
