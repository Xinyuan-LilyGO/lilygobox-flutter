import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';
Future<void> main() async {
 await integrationDriver(responseDataCallback:(data) async {
  final label=Platform.environment['LILYGOBOX_PERF_LABEL'] ?? 'default';
  final directory=Directory('tmp');await directory.create(recursive:true);
  await File('tmp/workflow-performance-$label.json').writeAsString(const JsonEncoder.withIndent('  ').convert(data));
 });
}
