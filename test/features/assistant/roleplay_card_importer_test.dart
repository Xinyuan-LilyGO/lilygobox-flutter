import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/roleplay_card_importer.dart';
import 'package:lilygobox/features/assistant/domain/roleplay_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JSON character cards', () {
    test('reads a flat legacy card', () async {
      final card = await AiRoleplayCardImporter.parse(
        _jsonBytes({'name': '  Rowan  ', 'first_mes': 'Welcome in.'}),
      );

      expect(card.name, 'Rowan');
      expect(card.opening, 'Welcome in.');
      expect(card.avatar, isNull);
    });

    for (final version in [2, 3]) {
      test('reads the character fields from a v$version card', () async {
        final card = await AiRoleplayCardImporter.parse(
          _jsonBytes({
            'spec': 'chara_card_v$version',
            'spec_version': '$version.0',
            'name': 'Outside the character data',
            'data': {
              'name': 'Lan',
              'description': 'The owner of a clock shop',
              'personality': 'Patient',
              'scenario': 'It is close to midnight',
              'first_mes': 'What brings you here?',
              'mes_example': '{{char}}: Come in.',
              'creator': 'A. Author',
              'character_version': '1.1',
              'creator_notes': 'A private author note',
              'tags': ['clocks'],
              'alternate_greetings': ['Welcome back!'],
            },
          }),
        );

        expect(card.name, 'Lan');
        expect(card.description, 'The owner of a clock shop');
        expect(card.personality, 'Patient');
        expect(card.scenario, 'It is close to midnight');
        expect(card.opening, 'What brings you here?');
        expect(card.examples, '{{char}}: Come in.');
        expect(card.formatVersion, '$version.0');
        expect(card.version, '1.1');
        expect(card.creator, 'A. Author');
        expect(card.creatorNotes, 'A private author note');
        expect(card.tags, ['clocks']);
        expect(card.openings, ['What brings you here?', 'Welcome back!']);
      });
    }

    test(
      'rejects non-card data, malformed fields and oversized metadata',
      () async {
        final invalidCards = <Object>[
          ['not a card'],
          {'name': 'An unrelated JSON document'},
          {'name': ' ', 'description': 'Missing a name'},
          {'name': 'Lan', 'description': 42},
          {
            'spec': 'chara_card_v4',
            'data': {'name': 'Lan'},
          },
          {
            'name': 'Lan',
            'description': 'x' * AiRoleplayCardImporter.maxMetadataBytes,
          },
        ];

        for (final invalidCard in invalidCards) {
          await expectLater(
            AiRoleplayCardImporter.parse(_jsonBytes(invalidCard)),
            throwsFormatException,
            reason:
                'Invalid character card ${invalidCards.indexOf(invalidCard)}',
          );
        }
      },
    );
  });

  group('PNG character cards', () {
    late Uint8List image;

    setUpAll(() async => image = await _createPng());

    test('prefers ccv3 metadata and returns a scaled avatar', () async {
      final card = await AiRoleplayCardImporter.parse(
        _addMetadata(image, {
          'chara': _base64Card(2, 'Legacy'),
          'ccv3': _base64Card(3, 'Preferred'),
        }),
      );

      expect(card.name, 'Preferred');
      final codec = await ui.instantiateImageCodec(card.avatar!);
      addTearDown(codec.dispose);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);
      expect(frame.image.width, 128);
      expect(frame.image.height, 64);
      expect(
        AiRoleplayCard.fromSnapshot(card.toSnapshot()).avatar,
        card.avatar,
      );
    });

    test('uses chara when ccv3 cannot be decoded', () async {
      final card = await AiRoleplayCardImporter.parse(
        _addMetadata(image, {'ccv3': '?', 'chara': _base64Card(2, 'Legacy')}),
      );

      expect(card.name, 'Legacy');
    });

    test('keeps a long v3 character description intact', () async {
      final description = 'x' * 24781;
      final opening = 'y' * 10743;
      final metadata = base64Encode(
        _jsonBytes({
          'spec': 'chara_card_v3',
          'spec_version': '3.0',
          'data': {
            'name': 'Lan',
            'description': description,
            'first_mes': opening,
          },
        }),
      );
      final card = await AiRoleplayCardImporter.parse(
        _addMetadata(image, {'ccv3': metadata}),
      );

      expect(card.description, description);
      expect(card.opening, opening);
      expect(card.avatar, isNotNull);
      expect(
        AiRoleplayCard.fromSnapshot(card.toSnapshot()).description,
        description,
      );
    });

    test(
      'rejects plain PNGs, invalid metadata and incomplete chunk data',
      () async {
        final valid = _addMetadata(image, {'chara': _base64Card(2, 'Lan')});

        for (final invalid in [
          image,
          _addMetadata(image, {'ccv3': '?'}),
          Uint8List.sublistView(valid, 0, valid.length - 13),
        ]) {
          await expectLater(
            AiRoleplayCardImporter.parse(invalid),
            throwsFormatException,
          );
        }
      },
    );
  });

  test('round trips imported data and expands only supported macros', () {
    final card = AiRoleplayCard.fromFields({
      'name': 'Lan',
      'description': '{{char}} repairs clocks.',
      'first_mes': 'Hello, {{ USER }}. I am {{char}}. {{other}}',
      'system_prompt': 'Use very short sentences.',
      'creator_notes': 'Not model context.',
    });

    final restored = AiRoleplayCard.fromSnapshot(card.toSnapshot());

    expect(restored.toSnapshot(), card.toSnapshot());
    expect(
      restored.expand(restored.opening, 'Alex'),
      'Hello, Alex. I am Lan. {{other}}',
    );
    final instruction = AiRoleplayBinding(
      card: restored,
      playerName: 'Alex',
      includeProfile: true,
      storyActive: true,
      includeAdvancedPrompts: true,
    ).conversationInstruction;
    expect(instruction, contains('Lan repairs clocks.'));
    expect(instruction, contains('Use very short sentences.'));
    expect(instruction, isNot(contains('Not model context.')));
    expect(instruction, isNot(contains('Hello, Alex.')));
  });
}

Uint8List _jsonBytes(Object data) =>
    Uint8List.fromList(utf8.encode(jsonEncode(data)));

String _base64Card(int version, String name) => base64Encode(
  _jsonBytes({
    'spec': 'chara_card_v$version',
    'data': {'name': name},
  }),
);

Future<Uint8List> _createPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF447799), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(256, 128);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return Uint8List.sublistView(bytes!);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Uint8List _addMetadata(Uint8List image, Map<String, String> entries) {
  final endChunk = image.length - 12;
  final output = BytesBuilder()..add(Uint8List.sublistView(image, 0, endChunk));
  for (final entry in entries.entries) {
    final data = latin1.encode('tEXt${entry.key}\x00${entry.value}');
    final chunkLength = ByteData(4)..setUint32(0, data.length - 4);
    final checksum = ByteData(4)..setUint32(0, _crc32(data));
    output
      ..add(chunkLength.buffer.asUint8List())
      ..add(data)
      ..add(checksum.buffer.asUint8List());
  }
  output.add(Uint8List.sublistView(image, endChunk));
  return output.takeBytes();
}

int _crc32(List<int> bytes) {
  var checksum = 0xFFFFFFFF;
  for (final byte in bytes) {
    checksum ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      checksum = (checksum >>> 1) ^ (checksum.isOdd ? 0xEDB88320 : 0);
    }
  }
  return checksum ^ 0xFFFFFFFF;
}
