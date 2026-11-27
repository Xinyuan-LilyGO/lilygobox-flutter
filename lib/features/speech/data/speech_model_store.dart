/*
 * @Description: 验证并保存本机语音模型文件和语音库索引。
 */

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../../core/files/package_transfer.dart';
import '../../../core/files/zstd_tar.dart';
import '../domain/speech_model.dart';
import 'speech_model_package.dart';

typedef SpeechModelCheck = Future<int> Function(
  SpeechModelFormat format,
  Directory directory,
);

class SpeechModelStore {
  SpeechModelStore({this._directory});

  final Directory? _directory;

  static final _idPattern = RegExp(r'^[0-9a-f]{64}$');

  Directory get _root {
    if (_directory case final directory?) return directory;
    final localData = Platform.environment['LOCALAPPDATA'];
    if (localData == null || localData.isEmpty) {
      throw const SpeechFailure(.storage);
    }
    return Directory(path.join(localData, 'LILYGO', 'LilygoBox', 'speech'));
  }

  File get _index => File(path.join(_root.path, 'library.json'));
  File get _hardwareNamesFile =>
      File(path.join(_root.path, 'hardware_names.json'));

  Future<Map<String, String>> loadHardwareNames() async {
    try {
      final file = _hardwareNamesFile;
      if (await _type(file.path) != .file) return const {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String &&
              entry.value is String &&
              (entry.value as String).isNotEmpty)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveHardwareNames(Map<String, String> names) async {
    try {
      final root = _root;
      await root.create(recursive: true);
      await _hardwareNamesFile.writeAsString(jsonEncode(names));
    } catch (_) {
      return;
    }
  }

  Future<int?> readStorageBytes() async {
    try {
      final root = _root;
      final type = await _type(root.path);
      if (type == .notFound) return 0;
      if (type != .directory) return null;
      var bytes = 0;
      await for (final entry in root.list(followLinks: false)) {
        if (entry is! Directory ||
            !_idPattern.hasMatch(path.basename(entry.path))) {
          continue;
        }
        await for (final file in entry.list(
          recursive: true,
          followLinks: false,
        )) {
          if (file is File) {
            final info = await file.stat();
            if (info.type == .file) bytes += info.size;
          }
        }
      }
      return bytes;
    } on FileSystemException {
      return null;
    } on SpeechFailure {
      return null;
    }
  }

  Directory _modelDirectory(String id) {
    if (!_idPattern.hasMatch(id)) throw const SpeechFailure(.storage);
    return Directory(path.join(_root.path, id));
  }

  Future<SpeechLibrary> read() async {
    final rootType = await _type(_root.path);
    if (rootType == .notFound) return SpeechLibrary();
    if (rootType != .directory) throw const SpeechFailure(.storage);
    final index = _index;
    final type = await _type(index.path);
    if (type == .notFound) return SpeechLibrary();
    if (type != .file) throw const SpeechFailure(.storage);

    final decoded = jsonDecode(await index.readAsString());
    if (decoded case {'models': final List<Object?> entries}) {
      final models = <SpeechModel>[];
      final ids = <String>{};
      for (final entry in entries) {
        if (entry
            case {
              'id': final String id,
              'format': final String formatName,
              'name': final String name,
              'voiceCount': final int voiceCount,
            }
            when _idPattern.hasMatch(id) && name.isNotEmpty && ids.add(id)) {
          final format = SpeechModelFormat.values.byName(formatName);
          if (!_validVoiceCount(format, voiceCount)) {
            throw const SpeechFailure(.storage);
          }
          models.add(
            SpeechModel(
              id: id,
              format: format,
              name: name,
              voiceCount: voiceCount,
              available: await _hasFiles(_modelDirectory(id), format),
            ),
          );
        } else {
          throw const SpeechFailure(.storage);
        }
      }
      return SpeechLibrary(models: models);
    }
    throw const SpeechFailure(.storage);
  }

  Future<SpeechLibrary> import(
    SpeechLibrary library,
    String sourcePath, {
    required SpeechModelCheck check,
    PackageTransfer? transfer,
  }) async {
    final root = await _ensureRoot();
    final scratch = await root.createTemp('import-');
    final staging = path.join(scratch.path, 'staging');
    try {
      final models = await SpeechModelPackage.extract(
        sourcePath,
        scratch.path,
        staging,
        transfer: transfer,
      );
      final updatedModels = {
        for (final model in library.models) model.id: model,
      };
      final pending = <String, Directory>{};
      for (final (index, (:format, :name)) in models.indexed) {
        final source = Directory(
          path.join(staging, SpeechModelPackage.modelFolder(index)),
        );
        transfer?.report(const PackageProgress(.checksumming));
        final id = await _modelId(source, format, transfer);
        if (pending.containsKey(id)) continue;
        final existing = updatedModels[id];
        if (existing != null && await _hasFiles(_modelDirectory(id), format)) {
          continue;
        }
        transfer?.report(
          PackageProgress(.verifying, completed: index, total: models.length),
        );
        final int voiceCount;
        try {
          voiceCount = await check(format, source);
        } catch (_) {
          transfer?.check();
          rethrow;
        }
        transfer?.check();
        if (!_validVoiceCount(format, voiceCount)) {
          throw const SpeechFailure(.invalidModel);
        }
        updatedModels[id] = SpeechModel(
          id: id,
          format: format,
          name: existing?.name ?? name,
          voiceCount: voiceCount,
        );
        pending[id] = source;
      }
      transfer?.check();
      if (pending.isEmpty) throw const SpeechFailure(.duplicateModel);
      final updated = SpeechLibrary(models: updatedModels.values);
      final installed = <Directory>[];
      transfer?.commit();
      try {
        for (final MapEntry(key: id, value: source) in pending.entries) {
          final target = _modelDirectory(id);
          await _deleteDirectory(target);
          await source.rename(target.path);
          installed.add(target);
        }
        await _write(updated);
      } catch (_) {
        for (final directory in installed) {
          await _deleteDirectory(directory);
        }
        rethrow;
      }
      return updated;
    } finally {
      await _cleanTemporary(scratch);
    }
  }

  static Future<String> _modelId(
    Directory source,
    SpeechModelFormat format,
    PackageTransfer? transfer,
  ) async {
    final hashes = <String, String>{};
    final files = await _modelFiles(source, format);
    for (final MapEntry(key: relative, value: file) in files.entries) {
      final chunks = file.openRead().map((bytes) {
        transfer?.check();
        return bytes;
      });
      hashes[relative] = (await sha256.bind(chunks).single).toString();
    }
    return sha256
        .convert(utf8.encode(jsonEncode([format.name, hashes])))
        .toString();
  }

  Future<void> export(
    List<SpeechModel> models,
    String outputPath, {
    PackageTransfer? transfer,
  }) async {
    if (models.isNotEmpty && await _type(_root.path) != .directory) {
      throw const SpeechFailure(.missingFiles);
    }
    final files = <String, String>{};
    for (final (index, model) in models.indexed) {
      transfer?.report(
        PackageProgress(.reading, completed: index, total: models.length),
      );
      final modelFiles = await _modelFiles(
        _modelDirectory(model.id),
        model.format,
      );
      for (final MapEntry(key: relative, value: file) in modelFiles.entries) {
        files['${SpeechModelPackage.modelFolder(index)}/$relative'] = file.path;
      }
    }
    final destination = File(
      await ZstdTar.exportPath(File(outputPath).absolute.path),
    );
    final scratch = await destination.parent.createTemp('.speech-export-');
    final temporary = File(path.join(scratch.path, 'model${ZstdTar.suffix}'));
    try {
      await SpeechModelPackage.write(
        temporary.path,
        [for (final model in models) (format: model.format, name: model.name)],
        files,
        transfer: transfer,
      );
      transfer?.commit();
      await temporary.rename(destination.path);
    } finally {
      await _cleanTemporary(scratch);
    }
  }

  Future<SpeechLibrary> delete(SpeechLibrary library, SpeechModel model) =>
      deleteModels(library, {model.id});

  Future<SpeechLibrary> deleteModels(
    SpeechLibrary library,
    Set<String> ids,
  ) async {
    final models = library.models.where((model) => ids.contains(model.id));
    if (models.isEmpty) return library;
    final root = await _ensureRoot();
    final staging = await root.createTemp('delete-');
    final moved = <(Directory, Directory)>[];
    var keepStaging = false;
    try {
      for (final model in models) {
        final directory = _modelDirectory(model.id);
        final type = await _type(directory.path);
        if (type == .directory) {
          final staged = await directory.rename(
            path.join(staging.path, model.id),
          );
          moved.add((directory, staged));
        } else if (type != .notFound) {
          throw const SpeechFailure(.storage);
        }
      }
      final updated = SpeechLibrary(
        models: library.models.where((model) => !ids.contains(model.id)),
      );
      await _write(updated);
      return updated;
    } catch (_) {
      for (final (original, staged) in moved.reversed) {
        try {
          await staged.rename(original.path);
        } on FileSystemException {
          keepStaging = true;
        }
      }
      rethrow;
    } finally {
      if (!keepStaging) await _cleanTemporary(staging);
    }
  }

  Future<Directory> directoryFor(SpeechModel model) async {
    final directory = _modelDirectory(model.id);
    if (await _type(_root.path) != .directory ||
        !await _hasFiles(directory, model.format)) {
      throw const SpeechFailure(.missingFiles);
    }
    return directory;
  }

  Future<Directory> _ensureRoot() async {
    final root = _root;
    final type = await _type(root.path);
    if (type == .notFound) return root.create(recursive: true);
    if (type != .directory) throw const SpeechFailure(.storage);
    return root;
  }

  Future<void> _write(SpeechLibrary library) async {
    final root = await _ensureRoot();
    final temporary = await root.createTemp('index-');
    try {
      final index = _index;
      final type = await _type(index.path);
      if (type != .file && type != .notFound) {
        throw const SpeechFailure(.storage);
      }
      final file = File(path.join(temporary.path, 'library.json'));
      await file.writeAsString(
        jsonEncode({
          'models': [
            for (final model in library.models)
              {
                'id': model.id,
                'format': model.format.name,
                'name': model.name,
                'voiceCount': model.voiceCount,
              },
          ],
        }),
        flush: true,
      );
      await file.rename(index.path);
    } finally {
      await _cleanTemporary(temporary);
    }
  }

  static Future<bool> _hasFiles(
    Directory directory,
    SpeechModelFormat format,
  ) async {
    try {
      await _modelFiles(directory, format);
      return true;
    } on SpeechFailure {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  static Future<Map<String, File>> _modelFiles(
    Directory directory,
    SpeechModelFormat format,
  ) async {
    if (await _type(directory.path) != .directory) {
      throw const SpeechFailure(.missingFiles);
    }
    final files = <String, File>{};
    var size = 0;
    Future<void> addFile(
      String relative,
      File file, {
      bool required = false,
    }) async {
      final length = await file.length();
      if (required && length == 0) throw const SpeechFailure(.missingFiles);
      size += length;
      if (size > SpeechModel.maxBytes) {
        throw const SpeechFailure(.packageTooLarge);
      }
      files[relative] = file;
    }

    for (final relative in format.files) {
      await addFile(
        relative,
        await _checkedFile(directory, relative),
        required: true,
      );
    }
    if (format.resourceDirectory case final resourceDirectory?) {
      final extraFiles = <String, File>{};
      final resources = Directory(path.join(directory.path, resourceDirectory));
      await for (final entity in resources.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Directory) continue;
        if (entity is! File || await _type(entity.path) != .file) {
          throw const SpeechFailure(.missingFiles);
        }
        final relative = path.relative(entity.path, from: directory.path);
        final canonical = path.split(relative).join('/');
        if (!files.containsKey(canonical)) extraFiles[canonical] = entity;
      }
      for (final relative in extraFiles.keys.toList()..sort()) {
        await addFile(relative, extraFiles[relative]!);
      }
    }
    return files;
  }

  static Future<File> _checkedFile(Directory directory, String relative) async {
    var current = directory.path;
    final segments = path.posix.split(relative);
    for (final (index, segment) in segments.indexed) {
      current = path.join(current, segment);
      final isFile = index == segments.length - 1;
      final FileSystemEntityType expected = isFile ? .file : .directory;
      if (await _type(current) != expected) {
        throw const SpeechFailure(.missingFiles);
      }
    }
    return File(current);
  }

  static Future<FileSystemEntityType> _type(String source) =>
      FileSystemEntity.type(source, followLinks: false);

  static bool _validVoiceCount(SpeechModelFormat format, int voices) =>
      format.kind == .recognition ? voices == 0 : voices > 0;

  static Future<void> _deleteDirectory(Directory directory) async {
    final type = await _type(directory.path);
    if (type == .directory) {
      await directory.delete(recursive: true);
    } else if (type != .notFound) {
      throw const SpeechFailure(.storage);
    }
  }

  static Future<void> _cleanTemporary(Directory directory) async {
    try {
      await _deleteDirectory(directory);
    } on FileSystemException {
      return;
    }
  }
}
