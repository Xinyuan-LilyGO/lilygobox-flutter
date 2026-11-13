import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/model_service_configuration_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/file_selector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late List<MethodCall> calls;
  Object? pickerResult;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'lilygobox-service-backup-',
    );
    addTearDown(() => directory.delete());
    calls = [];
    pickerResult = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return pickerResult;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<File> file(List<int> bytes) async {
    final target = File('${directory.path}/configuration.json');
    await target.writeAsBytes(bytes);
    addTearDown(() => target.delete());
    return target;
  }

  test('cancelled import and export leave no file', () async {
    expect(
      await ModelServiceConfigurationFileService.importConfiguration(
        fileTypeLabel: 'Model services',
      ),
      isNull,
    );
    expect(
      await ModelServiceConfigurationFileService.exportConfiguration(
        '{}',
        fileTypeLabel: 'Model services',
      ),
      isFalse,
    );
    expect(directory.listSync(), isEmpty);
  });

  test('exports complete UTF-8 source with a separate filename', () async {
    final target = await file([]);
    pickerResult = target.path;
    const source = '{"name":"模型服务","apiKey":"test-secret"}';
    expect(
      await ModelServiceConfigurationFileService.exportConfiguration(
        source,
        fileTypeLabel: 'Model services',
      ),
      isTrue,
    );
    expect(await target.readAsString(), source);
    expect(calls.single.method, 'getSavePath');
    expect(
      (calls.single.arguments as Map)['suggestedName'],
      'lilygobox-model-services.json',
    );
  });

  test(
    'imports complete UTF-8 content without interpreting the schema',
    () async {
      const source = '{"name":"模型服务","apiKey":"test-secret"}';
      final target = await file(utf8.encode(source));
      pickerResult = [target.path];
      expect(
        await ModelServiceConfigurationFileService.importConfiguration(
          fileTypeLabel: 'Model services',
        ),
        source,
      );
    },
  );

  test('rejects oversized import before returning configuration', () async {
    final target = await file(List.filled(2 * 1024 * 1024 + 1, 32));
    pickerResult = [target.path];
    expect(
      ModelServiceConfigurationFileService.importConfiguration(
        fileTypeLabel: 'Model services',
      ),
      throwsFormatException,
    );
  });

  test('rejects invalid UTF-8 instead of corrupting a credential', () async {
    final target = await file([0xff, 0xfe, 0x41]);
    pickerResult = [target.path];
    expect(
      ModelServiceConfigurationFileService.importConfiguration(
        fileTypeLabel: 'Model services',
      ),
      throwsFormatException,
    );
  });

  test('rejects oversized export before opening a save dialog', () async {
    expect(
      ModelServiceConfigurationFileService.exportConfiguration(
        'x' * (2 * 1024 * 1024 + 1),
        fileTypeLabel: 'Model services',
      ),
      throwsFormatException,
    );
    expect(calls, isEmpty);
  });
}
