import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/files/package_transfer.dart';
import 'package:lilygobox/features/assistant/data/roleplay_card_importer.dart';
import 'package:lilygobox/features/assistant/data/roleplay_card_package.dart';
import 'package:lilygobox/features/assistant/domain/roleplay_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late String packagePath;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('roleplay-card-package-');
    packagePath = '${directory.path}/cards.tar.zst';
  });
  tearDown(() => directory.delete(recursive: true));

  test('cancels compression without replacing the previous archive', () async {
    final destination = File(packagePath);
    const originalBytes = [1, 2, 3];
    await destination.writeAsBytes(originalBytes);
    final card = AiRoleplayCard.fromFields({'name': 'Archivist'});
    late final PackageTransfer transfer;
    transfer = PackageTransfer(
      onProgress: (progress) {
        if (progress.stage == .compressing) transfer.cancel();
      },
    );

    await expectLater(
      RoleplayCardPackage.write(packagePath, [card], transfer: transfer),
      throwsA(isA<PackageCancelled>()),
    );
    expect(await destination.readAsBytes(), originalBytes);
    expect(await directory.list().length, 1);
  });

  test('imports loose PNG and JSON and exports their original bytes', () async {
    final originalPng = await _pngCard('Archivist');
    final originalJson = _jsonCard('Clockmaker');
    await _looseArchive(packagePath, {
      'folder/card.png': originalPng,
      'folder/card.json': originalJson,
      'readme.txt': Uint8List.fromList(utf8.encode('Character cards')),
    });

    final cards = await RoleplayCardPackage.read(packagePath);
    expect(cards.map((card) => card.name), ['Archivist', 'Clockmaker']);
    expect(cards.first.avatar, isNotNull);
    expect(cards.first.originalFile, originalPng);
    expect(cards.last.originalFile, originalJson);

    final exportedPath = '${directory.path}/exported.tar.zst';
    await RoleplayCardPackage.write(exportedPath, cards);
    final exportedEntries = await _readArchive(exportedPath);
    expect(exportedEntries, hasLength(2));
    expect(
      exportedEntries.entries
          .singleWhere((entry) => entry.key.endsWith('.png'))
          .value,
      originalPng,
    );
    expect(
      exportedEntries.entries
          .singleWhere((entry) => entry.key.endsWith('.json'))
          .value,
      originalJson,
    );

    final restored = await RoleplayCardPackage.read(exportedPath);
    expect(
      restored.map((card) => card.templateFingerprint),
      cards.map((card) => card.templateFingerprint),
    );
  });

  test('writes standard v2 JSON without original file bytes', () async {
    final card = AiRoleplayCard.fromFields({
      'name': 'Archivist',
      'spec_version': '2.0',
      'first_mes': 'Welcome to the archives.',
      'alternate_greetings': ['Good to see you again.'],
      'system_prompt': 'Keep the discussion focused on books.',
      'character_book': {
        'entries': [
          {
            'keys': ['archives'],
            'content': 'The oldest books are here.',
          },
        ],
      },
    });

    await RoleplayCardPackage.write(packagePath, [card]);
    final file = (await _readArchive(packagePath)).entries.single;
    expect(file.key, endsWith('.json'));
    expect(jsonDecode(utf8.decode(file.value)), {
      'spec': 'chara_card_v2',
      'spec_version': '2.0',
      'data': {
        'name': 'Archivist',
        'description': '',
        'personality': '',
        'scenario': '',
        'first_mes': card.opening,
        'mes_example': '',
        'creator_notes': '',
        'system_prompt': card.systemPrompt,
        'post_history_instructions': '',
        'alternate_greetings': card.alternateOpenings,
        'tags': [],
        'creator': '',
        'character_version': '',
        'extensions': {},
        'character_book': {
          'scan_depth': 4,
          'extensions': {},
          'entries': [
            {
              'keys': ['archives'],
              'content': 'The oldest books are here.',
              'secondary_keys': [],
              'insertion_order': 100,
              'enabled': true,
              'constant': false,
              'selective': false,
              'case_sensitive': false,
              'position': 'before_char',
              'use_regex': false,
              'extensions': {'selectiveLogic': 0, 'case_sensitive': false},
            },
          ],
        },
      },
    });
    final restored = (await RoleplayCardPackage.read(packagePath)).single;

    expect(restored.originalFile, file.value);
    expect(restored.templateFingerprint, card.templateFingerprint);
  });

  test('writes a v3 PNG with its saved avatar and ccv3 chunk', () async {
    final imported = await AiRoleplayCardImporter.parse(await _pngCard('林雾'));
    final card = AiRoleplayCard.fromFields({
      'name': imported.name,
      'spec_version': '3.0',
      'description': '图书馆管理员',
    }, avatar: imported.avatar);

    await RoleplayCardPackage.write(packagePath, [card]);
    final file = (await _readArchive(packagePath)).entries.single;
    expect(file.key, endsWith('.png'));
    expect(AiRoleplayCardImporter.hasPngSignature(file.value), isTrue);
    expect(latin1.decode(file.value), contains('tEXtccv3\x00'));

    final restored = (await RoleplayCardPackage.read(packagePath)).single;
    expect(restored.originalFile, file.value);
    expect(restored.avatar, card.avatar);
    expect(restored.templateFingerprint, card.templateFingerprint);
  });

  test('exports clean card names and suffixes filename collisions', () async {
    final cards = [
      AiRoleplayCard.fromFields({
        'name': 'A/B',
        'creator': 'Card Author',
        'character_version': '1.2',
        'spec_version': '3.0',
      }),
      AiRoleplayCard.fromFields({'name': 'A:B'}),
      AiRoleplayCard.fromFields({'name': 'a_b'}),
      AiRoleplayCard.fromFields({'name': 'CON'}),
    ];

    await RoleplayCardPackage.write(packagePath, cards);
    final files = (await _readArchive(packagePath)).entries.toList();

    expect(files.map((file) => file.key), [
      'A_B.json',
      'A_B (2).json',
      'a_b (3).json',
      '_CON.json',
    ]);
    final exportedCard = jsonDecode(utf8.decode(files.first.value)) as Map;
    final exportedData = exportedCard['data'] as Map;
    expect(exportedData['name'], 'A/B');
    expect(exportedData['creator'], 'Card Author');
    expect(exportedData['character_version'], '1.2');
    expect(exportedCard['spec_version'], '3.0');
  });

  test('keeps distinct cards that share a name', () async {
    await _looseArchive(packagePath, {
      'first.json': _jsonCard('Archivist', opening: 'Welcome in.'),
      'second.json': _jsonCard('Archivist', opening: 'Have a seat.'),
    });
    final cards = await RoleplayCardPackage.read(packagePath);

    expect(cards.map((card) => card.name), ['Archivist', 'Archivist']);
    expect(cards.map((card) => card.templateFingerprint).toSet(), hasLength(2));
  });

  test('rejects an archive without cards and malformed card JSON', () async {
    await _looseArchive(packagePath, {'readme.txt': Uint8List(1)});
    await expectLater(
      RoleplayCardPackage.read(packagePath),
      throwsFormatException,
    );

    await _looseArchive(packagePath, {
      'valid.json': _jsonCard('Archivist'),
      'invalid.json': Uint8List.fromList(utf8.encode('{"unexpected": 1}')),
    });
    await expectLater(
      RoleplayCardPackage.read(packagePath),
      throwsFormatException,
    );
  });
}

Uint8List _jsonCard(
  String name, {
  String opening = 'Welcome.',
}) => Uint8List.fromList(
  utf8.encode(
    ' ${jsonEncode({'name': name, 'description': '', 'personality': '', 'scenario': '', 'first_mes': opening, 'mes_example': ''})}\n',
  ),
);

Future<void> _looseArchive(String path, Map<String, Uint8List> files) async {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  await File(
    path,
  ).writeAsBytes(ZstdEncoder().encodeBytes(TarEncoder().encodeBytes(archive)));
}

Future<Map<String, Uint8List>> _readArchive(String path) async {
  final archive = TarDecoder().decodeBytes(
    ZstdDecoder().decodeBytes(await File(path).readAsBytes(), verify: true),
    verify: true,
  );
  return {for (final entry in archive.files) entry.name: entry.content};
}

Future<Uint8List> _pngCard(String name) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF447799), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(16, 16);
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final pngBytes = Uint8List.sublistView(png);
      final endChunk = pngBytes.length - 12;
      final metadata = base64Encode(_jsonCard(name));
      final chunk = latin1.encode('tEXtchara\x00$metadata');
      final length = ByteData(4)..setUint32(0, chunk.length - 4);
      final checksum = ByteData(4)..setUint32(0, _crc32(chunk));
      return (BytesBuilder()
            ..add(Uint8List.sublistView(pngBytes, 0, endChunk))
            ..add(length.buffer.asUint8List())
            ..add(chunk)
            ..add(checksum.buffer.asUint8List())
            ..add(Uint8List.sublistView(pngBytes, endChunk)))
          .takeBytes();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
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
