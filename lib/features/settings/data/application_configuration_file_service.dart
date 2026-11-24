import '../../../core/files/zstd_text_file.dart';
import 'application_configuration.dart';

class ApplicationConfigurationFileService {
  const ApplicationConfigurationFileService._();

  static const fileName = 'lilygobox-config${ZstdTextFile.suffix}';
  static const _maximumFileBytes = 128 * 1024;

  static Future<bool> exportConfiguration(
    ApplicationConfiguration configuration, {
    required String fileTypeLabel,
  }) => ZstdTextFile.save(
    configuration.encode(),
    fileName: fileName,
    label: fileTypeLabel,
    maxBytes: _maximumFileBytes,
  );

  static Future<ApplicationConfiguration?> importConfiguration({
    required String fileTypeLabel,
  }) async {
    final source = await ZstdTextFile.open(
      label: fileTypeLabel,
      maxBytes: _maximumFileBytes,
    );
    return source == null ? null : ApplicationConfiguration.decode(source);
  }
}
