import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:koni_archive_core/io.dart';
import 'package:koni_sevenz/koni_sevenz.dart';

import '../domain/roleplay_card.dart';
import 'roleplay_card_exporter.dart';
import 'roleplay_card_importer.dart';

abstract final class RoleplayCardPackage {
  static const fileName = 'lilygobox-character-cards.7z';
  static const _maxCards = 1024;
  static const _maxBytes = 256 * 1024 * 1024;
  static const _maxArchiveBytes = _maxBytes + 1024 * 1024;
  static const _archiveHeaderSize = 32;

  static Future<
    ({List<AiRoleplayCard> cards, int unreadableFiles, bool singleCardFile})
  >
  readSources(List<XFile> files) async {
    final cards = <AiRoleplayCard>[];
    var unreadableFiles = 0;
    var singleCardFile = files.length == 1;
    for (final file in files) {
      try {
        final length = await file.length();
        if (length >= _archiveHeaderSize && await _isArchive(file)) {
          singleCardFile = false;
          cards.addAll(await read(file.path));
        } else {
          if (length > AiRoleplayCardImporter.maxFileBytes) {
            throw const FormatException('Character card is too large');
          }
          cards.add(
            await AiRoleplayCardImporter.parse(
              await file.readAsBytes(),
              retainOriginal: true,
            ),
          );
        }
      } catch (_) {
        unreadableFiles++;
      }
    }
    return (
      cards: cards,
      unreadableFiles: unreadableFiles,
      singleCardFile: singleCardFile,
    );
  }

  static Future<bool> _isArchive(XFile file) async {
    final header = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, _archiveHeaderSize)) {
      header.add(chunk);
    }
    return const SevenZFormat().matches(MemoryByteSource(header.takeBytes()));
  }

  static Future<List<AiRoleplayCard>> read(String path) async {
    final files = await Isolate.run(() => _readFiles(path));
    return [
      for (final bytes in files)
        await AiRoleplayCardImporter.parse(bytes, retainOriginal: true),
    ];
  }

  static Future<void> write(String path, List<AiRoleplayCard> cards) =>
      Isolate.run(() => _writeFiles(path, cards));

  static Future<List<Uint8List>> _readFiles(String path) async {
    final source = await FileByteSource.open(path);
    try {
      const format = SevenZFormat();
      if (source.length > _maxArchiveBytes || !await format.matches(source)) {
        throw const FormatException('Invalid character card archive');
      }
      final reader = await format.openReader(
        source,
        const ArchiveReadOptions(
          maxEntryCount: _maxCards,
          maxEntrySize: AiRoleplayCardImporter.maxFileBytes,
          maxContainerDecodeSize: _maxBytes,
        ),
      );
      try {
        final entries = reader.entries.where((entry) {
          final name = entry.path.toLowerCase();
          return entry.isFile &&
              !entry.pathEscapedRoot &&
              (name.endsWith('.png') || name.endsWith('.json'));
        }).toList();
        final size = entries.fold(
          0,
          (sum, entry) => sum + entry.uncompressedSize,
        );
        if (entries.isEmpty || size > _maxBytes) {
          throw const FormatException('Invalid character card archive size');
        }
        final files = <Uint8List>[];
        for (final entry in entries) {
          final bytes = BytesBuilder(copy: false);
          await for (final chunk in reader.openRead(entry)) {
            bytes.add(chunk);
          }
          files.add(bytes.takeBytes());
        }
        return files;
      } finally {
        await reader.close();
      }
    } finally {
      await source.close();
    }
  }

  static Future<void> _writeFiles(
    String path,
    List<AiRoleplayCard> cards,
  ) async {
    if (cards.isEmpty || cards.length > _maxCards) {
      throw const FormatException('Invalid character card count');
    }
    final temporary = File(
      '$path.${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    try {
      final sink = await FileByteSink.create(temporary.path);
      try {
        final writer = const SevenZWriteFormat().openWriter(
          sink,
          const ArchiveWriteOptions(compression: ArchiveCompression.stored),
        );
        var size = 0;
        for (final (index, card) in cards.indexed) {
          final bytes = AiRoleplayCardExporter.encode(card);
          size += bytes.length;
          if (size > _maxBytes ||
              bytes.length > AiRoleplayCardImporter.maxFileBytes) {
            throw const FormatException('Character card archive is too large');
          }
          final safeName = card.name.replaceAll(
            RegExp(r'[<>:"/\\|?*\x00-\x1f]'),
            '_',
          );
          final extension = AiRoleplayCardImporter.hasPngSignature(bytes)
              ? 'png'
              : 'json';
          await writer.addBytes(
            ArchiveEntrySpec(path: '${index + 1}-$safeName.$extension'),
            bytes,
          );
        }
        await writer.close();
      } finally {
        await sink.close();
      }
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
