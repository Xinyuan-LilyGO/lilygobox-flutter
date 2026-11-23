import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/roleplay_card.dart';

abstract final class AiRoleplayCardImporter {
  static const maxFileBytes = AiRoleplayCard.maxOriginalFileBytes;
  static const maxMetadataBytes = 256 * 1024;
  static const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

  static Future<AiRoleplayCard> parse(
    Uint8List bytes, {
    bool retainOriginal = false,
  }) async {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const FormatException('Invalid character card size');
    }
    final original = retainOriginal ? Uint8List.fromList(bytes) : null;
    if (!hasPngSignature(bytes)) {
      return AiRoleplayCard.fromFields(_fields(bytes), originalFile: original);
    }
    final fields = _pngFields(bytes);
    final avatar = await _thumbnail(bytes);
    return AiRoleplayCard.fromFields(
      fields,
      avatar: avatar,
      originalFile: original,
    );
  }

  static bool hasPngSignature(Uint8List bytes) {
    if (bytes.length < _pngSignature.length) return false;
    for (var index = 0; index < _pngSignature.length; index++) {
      if (bytes[index] != _pngSignature[index]) return false;
    }
    return true;
  }

  static Map<Object?, Object?> _fields(List<int> bytes) {
    if (bytes.length > maxMetadataBytes) {
      throw const FormatException('Character metadata is too large');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid character card');
    }
    final spec = value['spec'];
    if (spec == 'chara_card_v2' || spec == 'chara_card_v3') {
      final data = value['data'];
      if (data is Map<String, dynamic>) {
        return {
          ...data,
          'spec_version':
              value['spec_version'] ??
              (spec == 'chara_card_v3' ? '3.0' : '2.0'),
        };
      }
    } else if (spec == null &&
        const [
          'description',
          'personality',
          'scenario',
          'first_mes',
          'mes_example',
          'alternate_greetings',
          'character_book',
          'system_prompt',
          'post_history_instructions',
        ].any(value.containsKey)) {
      return value;
    }
    throw const FormatException('Unsupported character card');
  }

  static Map<Object?, Object?> _pngFields(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var offset = _pngSignature.length;
    String? versionTwo;
    String? versionThree;
    var ended = false;
    while (offset <= bytes.length - 12) {
      final length = data.getUint32(offset);
      if (length > bytes.length - offset - 12) break;
      final type = data.getUint32(offset + 4);
      if (type == 0x49454e44) {
        ended = length == 0;
        break;
      }
      if (type == 0x74455874 && length <= maxMetadataBytes * 2) {
        final start = offset + 8;
        final chunk = Uint8List.sublistView(bytes, start, start + length);
        final separator = chunk.indexOf(0);
        if (separator > 0 && separator <= 79) {
          final key = latin1.decode(chunk.sublist(0, separator)).toLowerCase();
          if (key == 'ccv3' || key == 'chara') {
            final payload = latin1.decode(chunk.sublist(separator + 1));
            if (key == 'ccv3') {
              versionThree ??= payload;
            } else {
              versionTwo ??= payload;
            }
          }
        }
      }
      offset += length + 12;
    }
    if (ended) {
      for (final metadata in [?versionThree, ?versionTwo]) {
        try {
          final fields = _fields(base64Decode(metadata));
          AiRoleplayCard.fromFields(fields);
          return fields;
        } on FormatException {
          continue;
        }
      }
    }
    throw const FormatException('PNG has no supported character card');
  }

  static Future<Uint8List> _thumbnail(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width * descriptor.height > 32000000) {
          throw const FormatException('Character image is too large');
        }
        final scale = math.min(
          1.0,
          128 / math.max(descriptor.width, descriptor.height),
        );
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()),
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final image = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (image == null) {
              throw const FormatException('Invalid character image');
            }
            return Uint8List.sublistView(image);
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}
