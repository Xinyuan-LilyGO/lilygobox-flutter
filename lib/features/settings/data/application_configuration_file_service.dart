import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'application_configuration.dart';

class ApplicationConfigurationFileService {
  const ApplicationConfigurationFileService._();

  static const fileName = 'lilygobox-config.json';
  static const _maximumFileBytes = 128 * 1024;

  static Future<bool> exportConfiguration(
    ApplicationConfiguration configuration, {
    required String fileTypeLabel,
  }) async {
    final destination = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [
        XTypeGroup(label: fileTypeLabel, extensions: const ['json']),
      ],
    );
    if (destination == null) return false;

    final bytes = Uint8List.fromList(utf8.encode(configuration.encode()));
    await XFile.fromData(
      bytes,
      name: fileName,
      mimeType: 'application/json',
    ).saveTo(destination.path);
    return true;
  }

  static Future<ApplicationConfiguration?> importConfiguration({
    required String fileTypeLabel,
  }) async {
    final source = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: fileTypeLabel, extensions: const ['json']),
      ],
    );
    if (source == null) return null;
    if (await source.length() > _maximumFileBytes) {
      throw const FormatException('Configuration file is too large.');
    }
    return ApplicationConfiguration.decode(
      utf8.decode(await source.readAsBytes()),
    );
  }
}
