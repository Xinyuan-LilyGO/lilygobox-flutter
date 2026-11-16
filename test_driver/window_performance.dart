import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final label =
        Platform.environment['LILYGOBOX_WINDOW_PERF_LABEL'] ?? 'default';
    await Directory('tmp').create(recursive: true);
    await File('tmp/window-performance-$label.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
