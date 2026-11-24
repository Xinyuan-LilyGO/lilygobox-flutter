/*
 * @Description: 用 Dart 编解码库读写智能体数据库对象。
 */

import 'dart:typed_data';

import 'package:archive/archive.dart';

abstract final class AgentCompression {
  static const maxBytes = 512 * 1024 * 1024;

  static Uint8List compressObject(Uint8List data) {
    _checkSize(data.length);
    return (BytesBuilder(copy: false)
          ..add(_sizeHeader(data.length))
          ..add(ZstdEncoder().encodeBytes(data, level: 3)))
        .takeBytes();
  }

  static Uint8List decompressObject(Uint8List bytes) {
    if (bytes.length <= 8) throw const FormatException('Invalid Zstd frame');
    final size = _readSize(bytes);
    _checkSize(size);
    final output = ZstdDecoder(maxWindowSize: maxBytes).decodeBytes(
      Uint8List.sublistView(bytes, 8),
      verify: true,
      maxOutputSize: size,
    );
    if (output.length != size) {
      throw const FormatException('Corrupt Zstd object');
    }
    return output;
  }

  static Uint8List _sizeHeader(int bytes) =>
      (ByteData(8)..setUint64(0, bytes, Endian.little)).buffer.asUint8List();

  static int _readSize(Uint8List bytes) =>
      ByteData.sublistView(bytes).getUint64(0, Endian.little);

  static void _checkSize(int size) {
    if (size < 0 || size > maxBytes) {
      throw const FormatException('Data exceeds size limit');
    }
  }
}
