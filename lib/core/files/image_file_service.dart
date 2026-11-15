/*
 * @Description: 使用系统另存为对话框保存原始图片文件。
 */
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class ImageFileService {
  const ImageFileService._();

  static Future<void> saveAs(Uint8List bytes, {required String label}) async {
    final extension = _extension(bytes);
    final name = 'image.$extension';
    final destination = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: [extension]),
      ],
    );
    if (destination == null) return;
    await XFile.fromData(bytes, name: name).saveTo(destination.path);
  }

  static String _extension(Uint8List bytes) {
    bool starts(List<int> signature, [int offset = 0]) {
      if (bytes.length < offset + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[offset + i] != signature[i]) return false;
      }
      return true;
    }

    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'png';
    if (starts([255, 216, 255])) return 'jpg';
    if (starts([71, 73, 70, 56])) return 'gif';
    if (starts([82, 73, 70, 70]) && starts([87, 69, 66, 80], 8)) return 'webp';
    if (starts([66, 77])) return 'bmp';
    if (starts([73, 73, 42, 0]) || starts([77, 77, 0, 42])) return 'tiff';
    throw const FormatException('Unsupported image format');
  }
}
