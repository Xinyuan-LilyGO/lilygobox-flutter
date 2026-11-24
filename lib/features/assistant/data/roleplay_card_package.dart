import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_selector/file_selector.dart';

import '../../../core/files/zstd_file.dart';
import '../../../core/files/zstd_tar.dart';
import '../domain/roleplay_card.dart';
import 'roleplay_card_exporter.dart';
import 'roleplay_card_importer.dart';

abstract final class RoleplayCardPackage {
  static const fileName = 'lilygobox-character-cards${ZstdTar.suffix}';
  static const _maxCards = 1024;
  static const _maxBytes = 256 * 1024 * 1024;
  static const _maxTarBytes = _maxBytes + _maxCards * 1024 + 1024;
  static const _maxArchiveBytes = _maxTarBytes + 1024 * 1024;
  static const _archiveHeaderSize = 4;

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
    return ZstdFile.matches(header.takeBytes());
  }

  static Future<List<AiRoleplayCard>> read(String path) async {
    final files = await Isolate.run(() => _readFiles(path));
    return [
      for (final bytes in files)
        await AiRoleplayCardImporter.parse(bytes, retainOriginal: true),
    ];
  }

  static Future<void> write(
    String requestedPath,
    List<AiRoleplayCard> cards,
  ) async {
    final path = await ZstdTar.exportPath(requestedPath);
    await Isolate.run(() => _writeFiles(path, cards));
  }

  static List<Uint8List> _readFiles(String path) {
    if (File(path).lengthSync() > _maxArchiveBytes) {
      throw const FormatException('Invalid character card archive size');
    }
    final input = InputFileStream(path);
    final output = OutputMemoryStream();
    final files = <Uint8List>[];
    var count = 0;
    var total = 0;
    try {
      ZstdFile.decompress(input, output, maxBytes: _maxTarBytes);
      TarDecoder().decodeBytes(
        output.getBytes(),
        verify: true,
        keepEntries: false,
        callback: (entry) {
          if (++count > _maxCards ||
              entry.size > AiRoleplayCardImporter.maxFileBytes) {
            throw const FormatException('Invalid character card archive size');
          }
          final name = entry.name.replaceAll('\\', '/').toLowerCase();
          if (name.startsWith('/') ||
              name.contains(':') ||
              name.split('/').contains('..') ||
              entry.isSymbolicLink ||
              entry.isHardLink) {
            throw const FormatException('Invalid character card archive entry');
          }
          if (!entry.isFile ||
              !(name.endsWith('.png') || name.endsWith('.json'))) {
            return;
          }
          total += entry.size;
          if (total > _maxBytes) {
            throw const FormatException('Invalid character card archive size');
          }
          files.add(entry.content);
        },
      );
    } finally {
      input.closeSync();
    }
    if (files.isEmpty) {
      throw const FormatException('Character card archive is empty');
    }
    return files;
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
      final output = OutputFileStream(temporary.path);
      try {
        final writer = ZstdTar.writer(output);
        var size = 0;
        for (final (index, card) in cards.indexed) {
          final bytes = AiRoleplayCardExporter.encode(card);
          size += bytes.length;
          if (size > _maxBytes ||
              bytes.length > AiRoleplayCardImporter.maxFileBytes) {
            throw const FormatException('Character card archive is too large');
          }
          final safeName = String.fromCharCodes(
            card.name
                .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
                .runes
                .take(20),
          );
          final extension = AiRoleplayCardImporter.hasPngSignature(bytes)
              ? 'png'
              : 'json';
          writer.add(
            ArchiveFile.bytes('${index + 1}-$safeName.$extension', bytes),
          );
        }
        writer.close();
      } finally {
        output.closeSync();
      }
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
