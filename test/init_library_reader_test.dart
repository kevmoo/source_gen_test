import 'dart:io';

import 'package:build/build.dart';
import 'package:source_gen_test/src/init_library_reader.dart';
import 'package:test/test.dart';

// TODO: test initializeLibraryReader - but since
//  `initializeLibraryReaderForDirectory` wraps it, not a big hurry
void main() {
  group('initializeLibraryReaderForDirectory', () {
    test('valid', () async {
      final reader = await initializeLibraryReaderForDirectory(
        'test/src',
        'test_library.dart',
      );

      expect(reader.directory, 'test/src');
      expect(reader.fileName, 'test_library.dart');
      expect(
        reader.allElements.map((e) => e.toString()),
        unorderedMatches([
          'library package:__test__/test_library.dart',
          'int get badTestField',
          'class TestClass1',
          'class TestClassFileNoPart',
          'class TestClassFilePartOf',
          'class TestClassFilePartOfCurrent',
          'class BadTestClass',
          'class TestClassWithBadMember',
          'int badTestFunc()',
          'int badTestField',
          'class TestClassThatHasAVeryLongNameThatShouldNotWrapWhenFormatOutputIsANop',
          'class TestClass2',
        ]),
      );
    });

    test('bad library name', () async {
      await expectLater(
        () => initializeLibraryReaderForDirectory(
          'test/src',
          'test_library_bad.dart',
        ),
        throwsA(
          isArgumentError
              .having(
                (ae) => ae.message,
                'message',
                'Must exist as a file in `sourceDirectory`.',
              )
              .having((ae) => ae.name, 'name', 'targetLibraryFileName'),
        ),
      );
    });

    test('non-existant directory', () async {
      await expectLater(
        () => initializeLibraryReaderForDirectory(
          'test/not_src',
          'test_library.dart',
        ),
        throwsA(const TypeMatcher<FileSystemException>()),
      );
    });

    test('part instead', () async {
      await expectLater(
        () => initializeLibraryReaderForDirectory('test/src', 'test_part.dart'),
        throwsA(
          isA<NonLibraryAssetException>().having(
            (ae) => ae.assetId.toString(),
            'assetId.toString()',
            '__test__|lib/test_part.dart',
          ),
        ),
      );
    });
  });
}
