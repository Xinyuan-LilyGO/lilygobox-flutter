/*
 * @Description: 通过系统文件选择器导入和导出独立模型服务配置文件。
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class ModelServiceConfigurationFileService {
  const ModelServiceConfigurationFileService._();

  static const fileName = 'lilygobox-model-services.json';
  static const _maximumFileBytes = 2 * 1024 * 1024;

  static Future<bool> exportConfiguration(
    String source, {
    required String fileTypeLabel,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(source));
    if (bytes.length > _maximumFileBytes) {
      throw const FormatException('Model service configuration is too large.');
    }
    final destination = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [
        XTypeGroup(label: fileTypeLabel, extensions: const ['json']),
      ],
    );
    if (destination == null) return false;

    await XFile.fromData(
      bytes,
      name: fileName,
      mimeType: 'application/json',
    ).saveTo(destination.path);
    return true;
  }

  static Future<String?> importConfiguration({
    required String fileTypeLabel,
  }) async {
    final source = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: fileTypeLabel, extensions: const ['json']),
      ],
    );
    if (source == null) return null;
    if (await source.length() > _maximumFileBytes) {
      throw const FormatException('Model service configuration is too large.');
    }
    final bytes = await source.readAsBytes();
    if (bytes.length > _maximumFileBytes) {
      throw const FormatException('Model service configuration is too large.');
    }
    return utf8.decode(bytes);
  }
}
