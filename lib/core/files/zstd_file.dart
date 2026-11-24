import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';

abstract final class ZstdFile {
  static const extension = 'zst';
  static const mimeType = 'application/zstd';
  static const uniformTypeIdentifier = 'org.iana.application.zstd';

  static bool matches(List<int> header) =>
      header.length >= 4 &&
      header[0] == 0x28 &&
      header[1] == 0xb5 &&
      header[2] == 0x2f &&
      header[3] == 0xfd;

  static void decompress(
    InputStream input,
    OutputStream output, {
    required int maxBytes,
  }) {
    if (!matches(input.peekBytes(4).toUint8List())) {
      throw const FormatException('Expected a Zstd archive');
    }
    ZstdDecoder(maxWindowSize: maxBytes)
        .decodeStream(input, output, verify: true, maxOutputSize: maxBytes);
  }

  static XTypeGroup typeGroup(String label) => XTypeGroup(
    label: label,
    extensions: const [extension],
    mimeTypes: const [mimeType],
    uniformTypeIdentifiers: const [uniformTypeIdentifier],
  );

  static String withSuffix(String name, String suffix) {
    final lower = name.toLowerCase();
    if (lower.endsWith(suffix)) return name;
    const lastExtension = '.$extension';
    final stem = lower.endsWith(lastExtension)
        ? name.substring(0, name.length - lastExtension.length)
        : name;
    final innerSuffix = suffix.substring(
      0,
      suffix.length - lastExtension.length,
    );
    return stem.toLowerCase().endsWith(innerSuffix)
        ? '$stem$lastExtension'
        : '$stem$suffix';
  }

  static Future<String> exportPath(String requested, String suffix) async {
    final path = withSuffix(requested, suffix);
    if (path != requested &&
        await FileSystemEntity.type(path, followLinks: false) != .notFound) {
      throw FileSystemException('Export destination already exists', path);
    }
    return path;
  }
}
