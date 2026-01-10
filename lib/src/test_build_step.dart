import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';

import '_expected_outputs.dart';
import 'init_library_reader.dart';
import 'utils.dart';

const _defaultBuildExtensions = {
  '.dart': ['.g.dart'],
};

class TestBuildStep extends BuildStep {
  TestBuildStep(String path, [BuilderOptions? options]) {
    final buildExtensions =
        (options?.config['build_extensions'] as Map<String, List<String>>?) ??
        _defaultBuildExtensions;

    final expectedOutputs =
        buildExtensions.entries
            .map(($) => ParsedBuildOutputs.parse($.key, $.value))
            .toList();

    path = normalizePath(path);
    inputId = AssetId.parse('$testPackageName|$path');

    final output =
        expectedOutputs.where(($) => $.hasAnyOutputFor(inputId)).firstOrNull;
    if (output == null) {
      throw InvalidOutputException(inputId, 'no matching outputs');
    }

    _allowedOutputs.addAll(output.matchingOutputsFor(inputId));

    // stderr.writeln(
    //   '\nINPUT ID = $inputId\nALLOWED OUTPUTS = $allowedOutputs\n',
    // );
  }

  @override
  late final AssetId inputId;

  final _generatedContents = <AssetId, String>{};
  final _allowedOutputs = <AssetId>[];

  @override
  Iterable<AssetId> get allowedOutputs => _allowedOutputs.where((_) => true);

  @override
  Future<String> readAsString(AssetId id, {Encoding encoding = utf8}) async =>
      _generatedContents[id] ?? '';

  @override
  Future<void> writeAsString(
    AssetId id,
    FutureOr<String> contents, {
    Encoding encoding = utf8,
  }) async {
    if (!allowedOutputs.contains(id)) {
      throw InvalidOutputException(id, 'Invalid output');
    }
    _generatedContents[id] = normalizeLineEndings(await contents).trim();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockBuildStep extends BuildStep {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

extension GoldenExt on TestBuildStep {
  Future<List<String>> saveGoldens(
    String directory, {
    bool dryRun = false,
    DartFormatter? formatter,
  }) => Future.wait(
    _generatedContents.entries.where((content) => content.value.isNotEmpty).map(
      (content) async {
        final filepath = normalizePath('$directory/${content.key.path}');
        final file = File(filepath);
        if (!dryRun) {
          await file.parent.create(recursive: true);
          await file.writeAsString(
            formatter?.format(content.value) ?? content.value,
            flush: true,
          );
        }
        return file.path;
      },
    ),
  );
}
