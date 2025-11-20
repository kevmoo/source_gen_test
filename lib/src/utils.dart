import 'package:build/build.dart';

String normalizeLineEndings(String code) =>
    code.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String normalizePath(String path) =>
    path.contains(r'\') ? path.split(r'\').join('/') : path;

extension AssetIdRelPathExt on AssetId {
  String getRelativePathFor(AssetId target) {
    final targetSegments = target.pathSegments;
    final currentSegments = pathSegments;

    while (targetSegments.isNotEmpty &&
        currentSegments.isNotEmpty &&
        targetSegments.first == currentSegments.first) {
      targetSegments.removeAt(0);
      currentSegments.removeAt(0);
    }

    while (currentSegments.length > 1) {
      targetSegments.insert(0, '..');
      currentSegments.removeAt(0);
    }

    return targetSegments.join('/');
  }
}
