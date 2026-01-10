import 'package:build/build.dart';

class TestBuildResult {
  TestBuildResult._(this.inputId);

  final AssetId inputId;
  final _outputs = <AssetId, String>{};

  static Future<TestBuildResult> from(BuildStep step) async {
    final results = TestBuildResult._(step.inputId);
    for (var id in step.allowedOutputs) {
      try {
        final code = await step.readAsString(id);
        if (code.isNotEmpty) {
          results._outputs[id] = code;
        }
      } catch (_) {}
    }
    return results;
  }

  Iterable<AssetId> get outputs => _outputs.keys;

  String? getGeneratedContents(AssetId outputId) => _outputs[outputId];
}
