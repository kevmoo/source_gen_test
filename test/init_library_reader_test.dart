import 'dart:io';

import 'package:build/build.dart';
import 'package:checks/checks.dart';
import 'package:source_gen_test/src/init_library_reader.dart';
import 'package:test/scaffolding.dart';

// TODO: test initializeLibraryReader - but since
//  `initializeLibraryReaderForDirectory` wraps it, not a big hurry
void main() {
  group('initializeLibraryReaderForDirectory', () {
    test('valid', () async {
      final reader = await initializeLibraryReaderForDirectory(
        'test/src',
        'test_library.dart',
      );

      check(reader.directory).equals('test/src');
      check(reader.fileName).equals('test_library.dart');
      check(reader.allElements.map((e) => e.toString())).unorderedEquals([
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
        'class TestClass2',
      ]);
    });

    test('bad library name', () async {
      await check(
        initializeLibraryReaderForDirectory(
          'test/src',
          'test_library_bad.dart',
        ),
      ).throws<ArgumentError>(
        (it) => it
          ..has(
            (ae) => ae.message,
            'message',
          ).equals('Must exist as a file in `sourceDirectory`.')
          ..has((ae) => ae.name, 'name').equals('targetLibraryFileName'),
      );
    });

    test('non-existant directory', () async {
      await check(
        initializeLibraryReaderForDirectory(
          'test/not_src',
          'test_library.dart',
        ),
      ).throws<FileSystemException>();
    });

    test('part instead', () async {
      await check(
        initializeLibraryReaderForDirectory('test/src', 'test_part.dart'),
      ).throws<NonLibraryAssetException>(
        (it) => it
            .has((ae) => ae.assetId.toString(), 'assetId.toString()')
            .equals('__test__|lib/test_part.dart'),
      );
    });
  });
}
