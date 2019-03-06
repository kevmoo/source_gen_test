import 'dart:io';

import '../example/example.dart' as example_test;

void main() async {
  if (Platform.environment['TRAVIS_DART_VERSION'] == '2.0.0') {
    print('Skipping on Dart 2.0.0');
    return;
  }

  await example_test.main();
}
