import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';

import 'export_file_name.dart';
import 'zstd_file.dart';

abstract final class ZstdTextFile {
  static const suffix = '.json.${ZstdFile.extension}';

  static Future<bool> save(
    String source, {
    required String fileName,
    required String label,
    required int maxBytes,
  }) async {
    final bytes = utf8.encode(source);
    if (bytes.length > maxBytes) {
      throw const FormatException('Configuration file is too large');
    }
    final destination = await getSaveLocation(
      suggestedName: datedExportFileName(fileName, suffix: suffix),
      acceptedTypeGroups: [ZstdFile.typeGroup(label)],
    );
    if (destination == null) return false;
    final path = await ZstdFile.exportPath(destination.path, suffix);
    final encoded = await Isolate.run(
      () => ZstdEncoder().encodeBytes(bytes, level: 3),
    );
    await XFile.fromData(
      encoded,
      name: fileName,
      mimeType: ZstdFile.mimeType,
    ).saveTo(path);
    return true;
  }

  static Future<String?> open({
    required String label,
    required int maxBytes,
  }) async {
    final source = await openFile(
      acceptedTypeGroups: [ZstdFile.typeGroup(label)],
    );
    if (source == null) return null;
    final archiveLimit = maxBytes + 64 * 1024;
    if (await source.length() > archiveLimit) {
      throw const FormatException('Configuration file is too large');
    }
    final bytes = await source.readAsBytes();
    if (bytes.length > archiveLimit) {
      throw const FormatException('Configuration file is too large');
    }
    return Isolate.run(() {
      final output = OutputMemoryStream();
      try {
        ZstdFile.decompress(
          InputMemoryStream(bytes),
          output,
          maxBytes: maxBytes,
        );
      } on ArchiveException catch (error) {
        throw FormatException('Invalid configuration archive', error);
      }
      return utf8.decode(output.getBytes());
    });
  }
}
