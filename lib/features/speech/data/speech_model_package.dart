/*
 * @Description: 在后台导入和导出标准格式的离线语音模型包。
 */

import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart' as tar;
import 'package:path/path.dart' as path;

import '../../../core/files/zstd_file.dart';
import '../../../core/files/zstd_tar.dart';
import '../domain/speech_model.dart';

typedef _Entry = ({int size, Future<void> Function(File) write});
typedef SpeechPackageModel = ({SpeechModelFormat format, String name});

abstract final class SpeechModelPackage {
  static const _archiveBytes = 1024 * 1024 * 1024;
  static const _entryCount = 4096;
  static final _controlCharacters = RegExp(r'[\x00-\x1f]');
  static final _unsafeFileName = RegExp(r'[<>:"/\\|?*\x00-\x1f]');
  static final _windowsDeviceName = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  );

  static String fileName(String name) {
    final normalized = name.replaceAll(_unsafeFileName, '_').trim();
    final safe = normalized.replaceFirst(RegExp(r'[. ]+$'), '');
    final stem = safe.isEmpty || _windowsDeviceName.hasMatch(safe)
        ? 'voice-model'
        : safe;
    return ZstdTar.withSuffix(stem);
  }

  static Future<SpeechPackageModel> extract(
    String sourcePath,
    String workPath,
    String modelPath,
  ) => Isolate.run(() => _extract(sourcePath, workPath, modelPath));

  static Future<SpeechPackageModel> _extract(
    String sourcePath,
    String workPath,
    String modelPath,
  ) async {
    final input = File(sourcePath);
    if (await input.length() > _archiveBytes) {
      throw const SpeechFailure(.packageTooLarge);
    }
    final name = path.basename(input.path);
    try {
      return await _readTar(input.path, workPath, modelPath, name);
    } on tar.ArchiveLimitException {
      throw const SpeechFailure(.packageTooLarge);
    } on SpeechFailure {
      rethrow;
    } on FileSystemException {
      rethrow;
    } catch (_) {
      throw const SpeechFailure(.invalidPackage);
    }
  }

  static Future<void> write(
    String outputPath,
    Map<String, String> modelFiles,
  ) => Isolate.run(() => _write(outputPath, modelFiles));

  static void _write(String outputPath, Map<String, String> modelFiles) {
    final output = tar.OutputFileStream(outputPath);
    try {
      final writer = ZstdTar.writer(output);
      for (final MapEntry(key: relative, value: sourcePath)
          in modelFiles.entries) {
        final input = tar.InputFileStream(sourcePath);
        try {
          writer.add(tar.ArchiveFile.stream(relative, input));
        } finally {
          input.closeSync();
        }
      }
      writer.close();
    } finally {
      output.closeSync();
    }
  }

  static Future<SpeechPackageModel> _readTar(
    String sourcePath,
    String workPath,
    String modelPath,
    String name,
  ) async {
    final tarPath = path.join(workPath, 'source.tar');
    final input = tar.InputFileStream(sourcePath);
    try {
      final header = input.peekBytes(4).toUint8List();
      final isZstd = ZstdFile.matches(header);
      final isBzip2 =
          header.length == 4 &&
          header[0] == 0x42 &&
          header[1] == 0x5a &&
          header[2] == 0x68 &&
          header[3] >= 0x31 &&
          header[3] <= 0x39;
      if (!isZstd && !isBzip2) throw const SpeechFailure(.invalidPackage);
      final output = tar.OutputFileStream(tarPath);
      try {
        if (isZstd) {
          ZstdFile.decompress(input, output, maxBytes: _archiveBytes);
        } else if (!tar.BZip2Decoder().decodeStream(
          input,
          output,
          verify: true,
          maxOutputSize: _archiveBytes,
        )) {
          throw const SpeechFailure(.invalidPackage);
        }
      } finally {
        output.closeSync();
      }
    } finally {
      input.closeSync();
    }

    final tarInput = tar.InputFileStream(tarPath);
    try {
      final entries = <String, _Entry>{};
      var entryCount = 0;
      tar.TarDecoder().decodeStream(
        tarInput,
        verify: true,
        keepEntries: false,
        callback: (entry) {
          if (++entryCount > _entryCount) {
            throw const SpeechFailure(.packageTooLarge);
          }
          final relative = _entryPath(entry.name);
          if (entry.isSymbolicLink || entry.isHardLink) {
            throw const SpeechFailure(.invalidPackage);
          }
          if (!entry.isFile) return;
          _add(entries, relative, (
            size: entry.size,
            write: (target) async {
              final output = tar.OutputFileStream(target.path);
              try {
                entry.writeContent(output, freeMemory: false);
              } finally {
                output.closeSync();
              }
            },
          ));
        },
      );
      return await _writeModel(entries, modelPath, name);
    } finally {
      tarInput.closeSync();
    }
  }

  static String _entryPath(String name) {
    final normalized = name.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (normalized.startsWith('/') ||
        parts.contains('..') ||
        normalized.contains(':') ||
        _controlCharacters.hasMatch(normalized)) {
      throw const SpeechFailure(.invalidPackage);
    }
    return parts.where((part) => part.isNotEmpty && part != '.').join('/');
  }

  static void _add(Map<String, _Entry> entries, String name, _Entry entry) {
    if (name.isEmpty || entries.containsKey(name)) {
      throw const SpeechFailure(.invalidPackage);
    }
    entries[name] = entry;
  }

  static Future<SpeechPackageModel> _writeModel(
    Map<String, _Entry> entries,
    String modelPath,
    String name,
  ) async {
    final candidates = [
      for (final format in SpeechModelFormat.values)
        for (final entry in entries.keys)
          if (path.posix.basename(entry) == format.files.first)
            (
              format: format,
              prefix: entry.substring(
                0,
                entry.length - format.files.first.length,
              ),
            ),
    ];
    if (candidates case [final candidate]) {
      final (:format, :prefix) = candidate;
      var bytes = 0;
      for (final relative in format.files) {
        final entry = entries['$prefix$relative'];
        if (entry == null || entry.size <= 0) {
          throw const SpeechFailure(.missingFiles);
        }
        bytes += entry.size;
        if (bytes > SpeechModel.maxBytes) {
          throw const SpeechFailure(.packageTooLarge);
        }
      }
      for (final relative in format.files) {
        final entry = entries['$prefix$relative']!;
        final target = File(
          path.joinAll([modelPath, ...path.posix.split(relative)]),
        );
        await target.parent.create(recursive: true);
        await entry.write(target);
        if (await target.length() != entry.size) {
          throw const SpeechFailure(.invalidPackage);
        }
      }
      final modelName = prefix.isEmpty
          ? name.replaceFirst(
              RegExp(r'\.tar\.(bz2|zst)$', caseSensitive: false),
              '',
            )
          : path.posix.basename(prefix);
      return (format: format, name: modelName.isEmpty ? name : modelName);
    }
    throw const SpeechFailure(.unsupportedModel);
  }
}
