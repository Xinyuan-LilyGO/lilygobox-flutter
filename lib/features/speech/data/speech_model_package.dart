/*
 * @Description: 在后台导入和导出标准格式的离线语音模型包。
 */

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart' as tar;
import 'package:path/path.dart' as path;

import '../../../core/files/package_transfer.dart';
import '../../../core/files/zstd_file.dart';
import '../../../core/files/zstd_tar.dart';
import '../domain/speech_model.dart';

typedef SpeechPackageModel = ({SpeechModelFormat format, String name});
typedef _ModelLocation = ({
  SpeechModelFormat format,
  String name,
  String prefix,
});

abstract final class SpeechModelPackage {
  static const _archiveBytes = 1024 * 1024 * 1024;
  static const _entryCount = 4096;
  static const _manifestPath = 'voice-models.json';
  static const _manifestBytes = 64 * 1024;
  static final _controlCharacters = RegExp(r'[\x00-\x1f]');
  static final _unsafeResourceName = RegExp(
    r'[<>"|?*]|[ .]$|^(con|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³])(?:\.|$)',
    caseSensitive: false,
  );

  static String modelFolder(int index) => 'models/$index';

  static Future<List<SpeechPackageModel>> extract(
    String sourcePath,
    String workPath,
    String modelPath, {
    PackageTransfer? transfer,
  }) {
    final input = (sourcePath, workPath, modelPath);
    return transfer == null
        ? Isolate.run(() => _extract(input, PackageTransfer()))
        : transfer.runWorker(input, _extract);
  }

  static Future<List<SpeechPackageModel>> _extract(
    (String, String, String) paths,
    PackageTransfer transfer,
  ) async {
    final (sourcePath, workPath, modelPath) = paths;
    final input = File(sourcePath);
    final length = await input.length();
    if (length > _archiveBytes) {
      throw const SpeechFailure(.packageTooLarge);
    }
    final name = path.basename(input.path);
    try {
      return await _readTar(input, length, workPath, modelPath, name, transfer);
    } on PackageCancelled {
      rethrow;
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
    List<SpeechPackageModel> models,
    Map<String, String> modelFiles, {
    PackageTransfer? transfer,
  }) {
    final input = (outputPath, models, modelFiles);
    return transfer == null
        ? Isolate.run(() => _write(input, PackageTransfer()))
        : transfer.runWorker(input, _write);
  }

  static Future<void> _write(
    (String, List<SpeechPackageModel>, Map<String, String>) input,
    PackageTransfer transfer,
  ) async {
    final (outputPath, models, modelFiles) = input;
    final manifest = utf8.encode(
      jsonEncode([
        for (final model in models)
          {'name': model.name, 'format': model.format.name},
      ]),
    );
    if (models.isEmpty) throw const SpeechFailure(.exportFailed);
    if (manifest.length > _manifestBytes ||
        modelFiles.length + 1 > _entryCount) {
      throw const SpeechFailure(.packageTooLarge);
    }
    var bytes = _tarEntryBytes(manifest.length) + 1024;
    final lengths = <String, int>{};
    var total = 0;
    for (final sourcePath in modelFiles.values) {
      final length = await File(sourcePath).length();
      lengths[sourcePath] = length;
      total += length;
      bytes += _tarEntryBytes(length);
      if (bytes > _archiveBytes) throw const SpeechFailure(.packageTooLarge);
    }
    final output = tar.OutputFileStream(outputPath);
    try {
      final writer = ZstdTar.writer(output);
      writer.add(tar.ArchiveFile(_manifestPath, manifest.length, manifest));
      var compressed = 0;
      transfer.report(
        PackageProgress(.compressing, completed: compressed, total: total),
      );
      for (final MapEntry(key: relative, value: sourcePath)
          in modelFiles.entries) {
        final source = tar.InputFileStream(sourcePath);
        final length = lengths[sourcePath]!;
        try {
          if (source.totalLength != length) {
            throw const SpeechFailure(.exportFailed);
          }
          final entry = writer.addHeader(
            tar.ArchiveFile.stream(relative, source),
          )!;
          writer.flush();
          final chunk = Uint8List(256 * 1024);
          while (!source.isEOS) {
            transfer.check();
            final count = source.readInto(chunk, 0, chunk.length);
            if (count == 0) throw const SpeechFailure(.exportFailed);
            writer.output.add(Uint8List.sublistView(chunk, 0, count));
            compressed += count;
            transfer.report(
              PackageProgress(
                .compressing,
                completed: compressed,
                total: total,
              ),
            );
            await transfer.checkpoint();
          }
          if (entry.padding > 0) writer.output.add(Uint8List(entry.padding));
        } finally {
          source.closeSync();
        }
      }
      writer.close();
    } finally {
      output.closeSync();
    }
    if (File(outputPath).lengthSync() > _archiveBytes) {
      throw const SpeechFailure(.packageTooLarge);
    }
  }

  static int _tarEntryBytes(int bytes) => 512 + ((bytes + 511) ~/ 512) * 512;

  static Future<List<SpeechPackageModel>> _readTar(
    File source,
    int length,
    String workPath,
    String modelPath,
    String name,
    PackageTransfer transfer,
  ) async {
    final tarPath = path.join(workPath, 'source.tar');
    final input = await source.open();
    final List<int> header;
    try {
      header = await input.read(4);
    } finally {
      await input.close();
    }
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
      await transfer.decompress(
        source,
        output,
        length: length,
        limit: _archiveBytes,
        decoder: isZstd
            ? const tar.ZstdDecoderConverter(maxWindowSize: _archiveBytes)
            : const tar.BZip2DecoderConverter(),
      );
    } finally {
      output.closeSync();
    }

    transfer.report(const PackageProgress(.analyzing));
    final tarInput = tar.InputFileStream(tarPath);
    try {
      final entries = <String, tar.ArchiveFile>{};
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
          if (relative.isEmpty || entries.containsKey(relative)) {
            throw const SpeechFailure(.invalidPackage);
          }
          entries[relative] = entry;
        },
      );
      final locations = switch (entries[_manifestPath]) {
        final manifest? => _readManifest(manifest),
        null => [_upstreamModel(entries, name)],
      };
      return [
        for (final (index, location) in locations.indexed)
          await _writeModel(
            entries,
            path.join(modelPath, modelFolder(index)),
            location,
            transfer,
          ),
      ];
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

  static List<_ModelLocation> _readManifest(tar.ArchiveFile manifest) {
    if (manifest.size <= 0 || manifest.size > _manifestBytes) {
      throw const SpeechFailure(.invalidPackage);
    }
    final decoded = jsonDecode(utf8.decode(manifest.content));
    if (decoded is! List<Object?> ||
        decoded.isEmpty ||
        decoded.length >= _entryCount) {
      throw const SpeechFailure(.invalidPackage);
    }
    return [
      for (final (index, entry) in decoded.indexed)
        if (entry
            case {'name': final String name, 'format': final String formatName}
            when name.trim().isNotEmpty && !_controlCharacters.hasMatch(name))
          (
            name: name,
            format: SpeechModelFormat.values.byName(formatName),
            prefix: '${modelFolder(index)}/',
          )
        else
          throw const SpeechFailure(.invalidPackage),
    ];
  }

  static _ModelLocation _upstreamModel(
    Map<String, tar.ArchiveFile> entries,
    String name,
  ) {
    final prefixes = <String>{};
    for (final entry in entries.keys) {
      final slash = entry.indexOf('/');
      prefixes.add(slash < 0 ? '' : '${entry.substring(0, slash)}/');
    }
    final candidates = [
      for (final prefix in prefixes)
        if (detectSpeechModelFormat([
              for (final entry in entries.keys)
                if (entry.startsWith(prefix)) entry.substring(prefix.length),
            ])
            case final format?)
          (format: format, prefix: prefix),
    ];
    if (candidates case [final candidate]) {
      final (:format, :prefix) = candidate;
      final modelName = prefix.isEmpty
          ? name.replaceFirst(
              RegExp(r'\.tar\.(bz2|zst)$', caseSensitive: false),
              '',
            )
          : path.posix.basename(prefix);
      return (
        format: format,
        name: modelName.trim().isEmpty ? name : modelName,
        prefix: prefix,
      );
    }
    throw const SpeechFailure(.unsupportedModel);
  }

  static Future<SpeechPackageModel> _writeModel(
    Map<String, tar.ArchiveFile> entries,
    String modelPath,
    _ModelLocation location,
    PackageTransfer transfer,
  ) async {
    final (:format, :name, :prefix) = location;
    final relativePaths = [
      for (final entry in entries.keys)
        if (entry.startsWith(prefix)) entry.substring(prefix.length),
    ];
    final resolved = resolveSpeechModelFiles(format, relativePaths);
    if (resolved == null) throw const SpeechFailure(.missingFiles);
    final requiredSet = resolved.requiredFiles.toSet();
    final files = {
      ...requiredSet,
      for (final relative in relativePaths)
        if (isSpeechModelAsset(relative)) relative,
    };
    _checkResourcePaths(files);
    var bytes = 0;
    for (final relative in files) {
      final entry = entries['$prefix$relative'];
      if (entry == null || (entry.size <= 0 && requiredSet.contains(relative))) {
        throw const SpeechFailure(.missingFiles);
      }
      bytes += entry.size;
      if (bytes > SpeechModel.maxBytes) {
        throw const SpeechFailure(.packageTooLarge);
      }
    }
    var written = 0;
    for (final relative in files) {
      final entry = entries['$prefix$relative']!;
      final target = File(
        path.joinAll([modelPath, ...path.posix.split(relative)]),
      );
      await target.parent.create(recursive: true);
      final output = tar.OutputFileStream(target.path);
      try {
        final content = entry.getContent();
        final chunk = Uint8List(256 * 1024);
        while (content != null && !content.isEOS) {
          final count = content.readInto(chunk, 0, chunk.length);
          if (count == 0) break;
          output.writeBytes(chunk, length: count);
          written += count;
          transfer.report(
            PackageProgress(.writing, completed: written, total: bytes),
          );
          await transfer.checkpoint();
        }
      } finally {
        output.closeSync();
      }
      if (await target.length() != entry.size) {
        throw const SpeechFailure(.invalidPackage);
      }
    }
    return (format: format, name: name);
  }

  static void _checkResourcePaths(Set<String> files) {
    final seenFiles = <String>{};
    final seenDirectories = <String, String>{};
    for (final relative in files) {
      final parts = relative.split('/');
      if (parts.any(_unsafeResourceName.hasMatch) ||
          !seenFiles.add(relative.toLowerCase())) {
        throw const SpeechFailure(.invalidPackage);
      }
      for (var length = 1; length < parts.length; length++) {
        final directory = parts.take(length).join('/');
        final previous = seenDirectories.putIfAbsent(
          directory.toLowerCase(),
          () => directory,
        );
        if (previous != directory) throw const SpeechFailure(.invalidPackage);
      }
    }
    if (seenFiles.any(seenDirectories.containsKey)) {
      throw const SpeechFailure(.invalidPackage);
    }
  }
}
