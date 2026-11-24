/*
 * @Description: 通过系统文件选择器导入和导出独立模型服务配置文件。
 */

import '../../../core/files/zstd_text_file.dart';

class ModelServiceConfigurationFileService {
  const ModelServiceConfigurationFileService._();

  static const fileName = 'lilygobox-model-services${ZstdTextFile.suffix}';
  static const _maximumFileBytes = 2 * 1024 * 1024;

  static Future<bool> exportConfiguration(
    String source, {
    required String fileTypeLabel,
  }) => ZstdTextFile.save(
    source,
    fileName: fileName,
    label: fileTypeLabel,
    maxBytes: _maximumFileBytes,
  );

  static Future<String?> importConfiguration({required String fileTypeLabel}) =>
      ZstdTextFile.open(label: fileTypeLabel, maxBytes: _maximumFileBytes);
}
