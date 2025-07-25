import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/element/element2.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';

const testPackageName = '__test__';

/// Returns a [LibraryReader] for library specified by [targetLibraryFileName]
/// using the files in [sourceDirectory].
Future<PathAwareLibraryReader> initializeLibraryReaderForDirectory(
  String sourceDirectory,
  String targetLibraryFileName,
) async {
  final map = Map.fromEntries(
    Directory(sourceDirectory).listSync().whereType<File>().map(
      (f) => MapEntry(p.basename(f.path), f.readAsStringSync()),
    ),
  );

  try {
    final reader = await initializeLibraryReader(map, targetLibraryFileName);

    return PathAwareLibraryReader(
      directory: sourceDirectory,
      fileName: targetLibraryFileName,
      element: reader.element,
    );
  } on ArgumentError catch (e) // ignore: avoid_catching_errors
  {
    if (e.message == 'Must exist as a key in `contentMap`.') {
      throw ArgumentError.value(
        targetLibraryFileName,
        'targetLibraryFileName',
        'Must exist as a file in `sourceDirectory`.',
      );
    }
    rethrow;
  }
}

/// Returns a [LibraryReader] for library specified by [targetLibraryFileName]
/// using the file contents described by [contentMap].
///
/// [contentMap] contains the Dart file contents to from which to create the
/// library stored as filename / file content pairs.
Future<LibraryReader> initializeLibraryReader(
  Map<String, String> contentMap,
  String targetLibraryFileName,
) async {
  if (!contentMap.containsKey(targetLibraryFileName)) {
    throw ArgumentError.value(
      targetLibraryFileName,
      'targetLibraryFileName',
      'Must exist as a key in `contentMap`.',
    );
  }

  String assetIdForFile(String fileName) => '$testPackageName|lib/$fileName';

  final targetLibraryAssetId = assetIdForFile(targetLibraryFileName);

  final assetMap = contentMap.map(
    (file, content) => MapEntry(assetIdForFile(file), content),
  );

  final library = await resolveSources(
    assetMap,
    (item) async {
      final assetId = AssetId.parse(targetLibraryAssetId);
      return item.libraryFor(assetId);
    },
    resolverFor: targetLibraryAssetId,
    readAllSourcesFromFilesystem: true,
  );

  return LibraryReader(library);
}

/// A [LibraryReader] that also stores the [directory] and [fileName] it reads.
class PathAwareLibraryReader extends LibraryReader {
  final String directory;
  final String fileName;

  PathAwareLibraryReader({
    required this.directory,
    required this.fileName,
    required LibraryElement2 element,
  }) : super(element);

  String get path => p.join(directory, fileName);
}
