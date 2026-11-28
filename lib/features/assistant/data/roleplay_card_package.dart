import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_selector/file_selector.dart';

import '../../../core/files/package_transfer.dart';
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
  static const _windowsReservedNames = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  static Future<
    ({List<AiRoleplayCard> cards, int unreadableFiles, bool singleCardFile})
  >
  readSources(List<XFile> files, {PackageTransfer? transfer}) async {
    final cards = <AiRoleplayCard>[];
    var unreadableFiles = 0;
    var singleCardFile = files.length == 1;
    for (final (index, file) in files.indexed) {
      if (files.length > 1) {
        transfer?.reportBatch(completed: index, total: files.length);
      }
      transfer?.report(
        PackageProgress(.reading, completed: index, total: files.length),
      );
      try {
        final length = await file.length();
        if (length >= _archiveHeaderSize && await _isArchive(file)) {
          singleCardFile = false;
          cards.addAll(await read(file.path, transfer: transfer));
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
        transfer?.check();
      } on PackageCancelled {
        rethrow;
      } catch (_) {
        unreadableFiles++;
      }
    }
    if (files.length > 1) {
      transfer?.reportBatch(completed: files.length, total: files.length);
    }
    transfer?.report(
      PackageProgress(.reading, completed: files.length, total: files.length),
    );
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

  static Future<List<AiRoleplayCard>> read(
    String path, {
    PackageTransfer? transfer,
  }) async {
    final files = transfer == null
        ? await Isolate.run(() => _readFiles(path, PackageTransfer()))
        : await transfer.runWorker(path, _readFiles);
    final cards = <AiRoleplayCard>[];
    for (final (index, bytes) in files.indexed) {
      transfer?.report(
        PackageProgress(.analyzing, completed: index, total: files.length),
      );
      await transfer?.checkpoint();
      cards.add(
        await AiRoleplayCardImporter.parse(bytes, retainOriginal: true),
      );
    }
    transfer?.check();
    return cards;
  }

  static Future<void> write(
    String requestedPath,
    List<AiRoleplayCard> cards, {
    PackageTransfer? transfer,
  }) async {
    final path = await ZstdTar.exportPath(requestedPath);
    final temporary = File(
      '$path.${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    final input = (temporary.path, cards);
    try {
      if (transfer == null) {
        await Isolate.run(() => _writeFiles(input, PackageTransfer()));
      } else {
        await transfer.runWorker(input, _writeFiles);
      }
      transfer?.commit();
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<List<Uint8List>> _readFiles(
    String path,
    PackageTransfer transfer,
  ) async {
    final source = File(path);
    final length = await source.length();
    if (length > _maxArchiveBytes) {
      throw const FormatException('Invalid character card archive size');
    }
    final output = OutputMemoryStream();
    final files = <Uint8List>[];
    var count = 0;
    var total = 0;
    try {
      await transfer.decompress(
        source,
        output,
        length: length,
        limit: _maxTarBytes,
        decoder: const ZstdDecoderConverter(maxWindowSize: _maxTarBytes),
      );
      transfer.report(const PackageProgress(.analyzing));
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
      output.closeSync();
    }
    if (files.isEmpty) {
      throw const FormatException('Character card archive is empty');
    }
    return files;
  }

  static Future<void> _writeFiles(
    (String, List<AiRoleplayCard>) input,
    PackageTransfer transfer,
  ) async {
    final (path, cards) = input;
    if (cards.isEmpty || cards.length > _maxCards) {
      throw const FormatException('Invalid character card count');
    }
    final output = OutputFileStream(path);
    try {
      final writer = ZstdTar.writer(output);
      var size = 0;
      final fileNames = <String>{};
      for (final (index, card) in cards.indexed) {
        if (cards.length > 1) {
          transfer.reportBatch(completed: index, total: cards.length);
        }
        transfer.report(
          PackageProgress(.compressing, completed: index, total: cards.length),
        );
        await transfer.checkpoint();
        final bytes = AiRoleplayCardExporter.encode(card);
        size += bytes.length;
        if (size > _maxBytes ||
            bytes.length > AiRoleplayCardImporter.maxFileBytes) {
          throw const FormatException('Character card archive is too large');
        }
        final extension = AiRoleplayCardImporter.hasPngSignature(bytes)
            ? 'png'
            : 'json';
        writer.add(
          ArchiveFile.bytes(
            _archiveFileName(card.name, extension, fileNames),
            bytes,
          ),
        );
      }
      writer.close();
      if (cards.length > 1) {
        transfer.reportBatch(completed: cards.length, total: cards.length);
      }
    } finally {
      output.closeSync();
    }
  }

  static String _archiveFileName(
    String name,
    String extension,
    Set<String> usedFileNames,
  ) {
    var safeName = String.fromCharCodes(
      name
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
          .trim()
          .replaceAll(RegExp(r'[. ]+$'), '')
          .runes
          .take(20),
    );
    if (safeName.isEmpty) safeName = 'Character card';
    if (_windowsReservedNames.contains(
      safeName.split('.').first.toUpperCase(),
    )) {
      safeName = '_$safeName';
    }

    var candidate = '$safeName.$extension';
    var duplicate = 2;
    while (!usedFileNames.add(candidate.toLowerCase())) {
      candidate = '$safeName ($duplicate).$extension';
      duplicate++;
    }
    return candidate;
  }
}
