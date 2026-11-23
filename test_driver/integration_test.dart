import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves integration-test screenshots on the host, in $SCREENSHOT_DIR
/// (default build/screenshots). They can show real local test data: keep
/// them out of the repository.
Future<void> main() async {
  final dir = Platform.environment['SCREENSHOT_DIR'] ?? 'build/screenshots';
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final file = File('$dir/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
