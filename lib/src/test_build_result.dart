import 'package:build/build.dart';

class TestBuildResult {
  TestBuildResult._();

  final _outputs = <AssetId, String>{};

  static Future<TestBuildResult> from(BuildStep step) async {
    final results = TestBuildResult._();
    for (var id in step.allowedOutputs) {
      try {
        final code = await step.readAsString(id);
        results._outputs[id] = code;
      } catch (_) {}
    }
    return results;
  }

  String? getGeneratedContents(AssetId outputId) => _outputs[outputId];
}
