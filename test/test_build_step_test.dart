import 'package:build/build.dart';
import 'package:source_gen_test/src/test_build_step.dart';
import 'package:source_gen_test/src/utils.dart';
import 'package:test/test.dart';

void main() {
  group('AssetId relative paths', () {
    test('', () {
      String $relPath(String ref, String target) =>
          AssetId('xxx', ref).getRelativePathFor(AssetId('xxx', target));

      expect($relPath('f1.dart', 'f2.dart'), equals('f2.dart'));
      expect($relPath('a/f1.dart', 'f2.dart'), equals('../f2.dart'));
      expect($relPath('a/b/f1.dart', 'a/f2.dart'), equals('../f2.dart'));
      expect($relPath('a/b/f1.dart', 'a/b/f2.dart'), equals('f2.dart'));
      expect($relPath('a/b/f1.dart', 'c/f2.dart'), equals('../../c/f2.dart'));
      expect($relPath('a/b/f1.dart', 'a/../f2.dart'), equals('../../f2.dart'));
    });
  });

  group('TestBuildStep', () {
    test('inputId', () {
      final buildStep = TestBuildStep('input_file.dart');
      expect(buildStep.inputId.path, equals('input_file.dart'));
    });

    group('allowedOutputs', () {
      test('default build options', () {
        final buildStep = TestBuildStep('input_file.dart');
        expect(buildStep.allowedOutputs.length, equals(1));
        expect(
          buildStep.allowedOutputs.first.path,
          equals('input_file.g.dart'),
        );
      });

      test('specific build options', () {
        final extensions = {
          '.dart': ['.custom.dart'],
        };
        final buildStep = TestBuildStep(
          'input_file.dart',
          BuilderOptions({'build_extensions': extensions}),
        );
        expect(buildStep.allowedOutputs.length, equals(1));
        expect(
          buildStep.allowedOutputs.first.path,
          equals('input_file.custom.dart'),
        );
      });

      test('several outputs', () {
        final extensions = {
          '.dart': ['.g.dart', '.custom.g.dart'],
        };
        final buildStep = TestBuildStep(
          'input_file.dart',
          BuilderOptions({'build_extensions': extensions}),
        );
        expect(buildStep.allowedOutputs.length, equals(2));
        expect(
          buildStep.allowedOutputs.map((o) => o.path),
          contains('input_file.g.dart'),
        );
        expect(
          buildStep.allowedOutputs.map((o) => o.path),
          contains('input_file.custom.g.dart'),
        );
      });

      test('output with a simple capture group', () {
        final extensions = {
          '{{file}}.dart': ['goldens/{{file}}.g.dart'],
        };
        final buildStep = TestBuildStep(
          'input_file.dart',
          BuilderOptions({'build_extensions': extensions}),
        );
        expect(buildStep.allowedOutputs.length, equals(1));
        expect(
          buildStep.allowedOutputs.first.path,
          equals('goldens/input_file.g.dart'),
        );
      });

      test('output with multiple capture groups', () {
        final extensions = {
          '{{path}}/{{file}}.dart': ['{{path}}/goldens/{{file}}.g.dart'],
        };
        final buildStep = TestBuildStep(
          'dir/input_file.dart',
          BuilderOptions({'build_extensions': extensions}),
        );
        expect(buildStep.allowedOutputs.length, equals(1));
        expect(
          buildStep.allowedOutputs.first.path,
          equals('dir/goldens/input_file.g.dart'),
        );
      });

      test('output with multiple capture groups and relative path', () {
        final extensions = {
          '{{path}}/{{file}}.dart': ['{{path}}/../goldens/{{file}}.g.dart'],
        };
        final buildStep1 = TestBuildStep(
          'dir/input_file.dart',
          BuilderOptions({'build_extensions': extensions}),
        );
        expect(buildStep1.allowedOutputs.length, equals(1));
        expect(
          buildStep1.allowedOutputs.first.path,
          equals('goldens/input_file.g.dart'),
        );
        final buildStep2 = TestBuildStep(
          'dir/subdir/input_file.dart',
          BuilderOptions({'build_extensions': extensions}),
        );
        expect(buildStep2.allowedOutputs.length, equals(1));
        expect(
          buildStep2.allowedOutputs.first.path,
          equals('dir/goldens/input_file.g.dart'),
        );
      });

      test('no match', () {
        expectLater(
          () => TestBuildStep('image.png'),
          throwsA(
            isA<InvalidOutputException>().having(
              (e) => e.message.toLowerCase(),
              'message',
              contains('no matching outputs'),
            ),
          ),
        );

        expectLater(
          () => TestBuildStep(
            'top_level.dart',
            const BuilderOptions({
              'build_extensions': {
                '{{path}}/{{file}}.dart': ['{{path}}/goldens/{{file}}.g.dart'],
              },
            }),
          ),
          throwsA(
            isA<InvalidOutputException>().having(
              (e) => e.message.toLowerCase(),
              'message',
              contains('no matching outputs'),
            ),
          ),
        );
      });
    });

    group('saveGoldens', () {
      const basePath = '/some/path';

      test('default build options', () async {
        final buildStep = TestBuildStep('dir/input_file.dart');
        await buildStep.writeAsString(
          buildStep.allowedOutputs.first,
          '// generated code',
        );
        final paths = await buildStep.saveGoldens(basePath, dryRun: true);
        expect(paths, equals(['$basePath/dir/input_file.g.dart']));
      });

      test('custom build options', () async {
        final buildStep = TestBuildStep(
          'dir/input_file.dart',
          const BuilderOptions({
            'build_extensions': {
              '{{file}}.dart': ['{{file}}_test.g.dart', '{{file}}.g.dart'],
            },
          }),
        );
        await buildStep.writeAsString(
          buildStep.allowedOutputs.first,
          '// generated code',
        );
        await buildStep.writeAsString(
          buildStep.allowedOutputs.last,
          '// generated code',
        );
        final paths = await buildStep.saveGoldens(basePath, dryRun: true);
        expect(
          paths,
          equals([
            '$basePath/dir/input_file_test.g.dart',
            '$basePath/dir/input_file.g.dart',
          ]),
        );
      });

      test('custom build options with partial outputs', () async {
        final buildStep = TestBuildStep(
          'dir/input_file.dart',
          const BuilderOptions({
            'build_extensions': {
              '{{file}}.dart': ['{{file}}_test.g.dart', '{{file}}.g.dart'],
            },
          }),
        );
        await buildStep.writeAsString(
          buildStep.allowedOutputs.first,
          '// generated code',
        );
        final paths = await buildStep.saveGoldens(basePath, dryRun: true);
        expect(paths, equals(['$basePath/dir/input_file_test.g.dart']));
      });
    });
  });
}
