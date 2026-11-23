import 'dart:convert';
import 'dart:typed_data';

import '../domain/roleplay_card.dart';
import 'roleplay_card_importer.dart';

abstract final class AiRoleplayCardExporter {
  static Uint8List encode(AiRoleplayCard card) {
    if (card.originalFile case final original?) return original;

    final cardJson = card.toTavernJson();
    final metadata = utf8.encode(jsonEncode(cardJson));
    if (metadata.length > AiRoleplayCardImporter.maxMetadataBytes) {
      throw const FormatException('Character metadata is too large');
    }
    if (card.avatar case final avatar?) {
      final keyword = cardJson['spec'] == 'chara_card_v3' ? 'ccv3' : 'chara';
      return _embedMetadata(avatar, keyword, metadata);
    }
    return metadata;
  }

  static Uint8List _embedMetadata(
    Uint8List avatar,
    String keyword,
    Uint8List metadata,
  ) {
    const endChunkSize = 12;
    final endOffset = avatar.length - endChunkSize;
    final data = ByteData.sublistView(avatar);
    if (!AiRoleplayCardImporter.hasPngSignature(avatar) ||
        endOffset < 8 ||
        data.getUint32(endOffset) != 0 ||
        data.getUint32(endOffset + 4) != 0x49454E44) {
      throw const FormatException('Invalid character avatar PNG');
    }

    final chunk = ascii.encode('tEXt$keyword\x00${base64Encode(metadata)}');
    final length = ByteData(4)..setUint32(0, chunk.length - 4);
    final checksum = ByteData(4)..setUint32(0, _crc32(chunk));
    return (BytesBuilder(copy: false)
          ..add(Uint8List.sublistView(avatar, 0, endOffset))
          ..add(length.buffer.asUint8List())
          ..add(chunk)
          ..add(checksum.buffer.asUint8List())
          ..add(Uint8List.sublistView(avatar, endOffset)))
        .takeBytes();
  }

  static int _crc32(Uint8List bytes) {
    var checksum = 0xFFFFFFFF;
    for (final byte in bytes) {
      checksum ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        checksum = (checksum >>> 1) ^ (checksum.isOdd ? 0xEDB88320 : 0);
      }
    }
    return checksum ^ 0xFFFFFFFF;
  }
}
