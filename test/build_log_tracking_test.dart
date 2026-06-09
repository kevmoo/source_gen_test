import 'package:checks/checks.dart';
import 'package:source_gen_test/src/build_log_tracking.dart';
import 'package:test/scaffolding.dart';

void main() {
  group('after calling initializeBuildLogTracking', () {
    initializeBuildLogTracking();
    test('calling init again throws', () {
      check(initializeBuildLogTracking).throws<StateError>();
    });

    // TODO: actually test something
    // TODO: test a build with log items that are not cleared
  });

  group('without calling initializeBuildLogTracking', () {
    test('accessing buildLogItems throws', () {
      check(() => buildLogItems).throws<StateError>();
    });

    test('calling clearBuildLog throws', () {
      check(clearBuildLog).throws<StateError>();
    });
  });
}
