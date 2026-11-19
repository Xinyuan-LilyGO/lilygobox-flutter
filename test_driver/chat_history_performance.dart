import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    await Directory('tmp').create(recursive: true);
    final label = Platform.environment['LILYGOBOX_CHAT_HISTORY_LABEL'];
    final path = label == null
        ? 'tmp/chat-history-native.json'
        : 'tmp/chat-history-native-$label.json';
    await File(path)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
