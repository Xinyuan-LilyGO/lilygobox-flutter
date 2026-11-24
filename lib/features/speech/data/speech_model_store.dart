/*
 * @Description: 验证并保存本机语音模型文件和语音库索引。
 */

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

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
    if (decoded case {
      'models': final List<Object?> entries,
      'recognition': final String? recognition,
      'synthesis': final String? synthesis,
      'voice': final int voice,
    }) {
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
      final recognitionModel = models
          .where(
            (model) => model.kind == .recognition && model.id == recognition,
          )
          .firstOrNull;
      final synthesisModel = models
          .where((model) => model.kind == .synthesis && model.id == synthesis)
          .firstOrNull;
      return SpeechLibrary(
        models: models,
        recognitionId: recognitionModel?.id,
        synthesisId: synthesisModel?.id,
        voice: voice >= 0 && voice < (synthesisModel?.voiceCount ?? 0)
            ? voice
            : 0,
      );
    }
    throw const SpeechFailure(.storage);
  }

  Future<SpeechLibrary> import(
    SpeechLibrary library,
    String sourcePath, {
    required SpeechModelCheck check,
  }) async {
    final root = await _ensureRoot();
    final scratch = await root.createTemp('import-');
    final staging = Directory(path.join(scratch.path, 'model'));
    try {
      final (:format, :name) = await SpeechModelPackage.extract(
        sourcePath,
        scratch.path,
        staging.path,
      );
      final hashes = <String, String>{};
      for (final relative in format.files) {
        final file = await _checkedFile(staging, relative);
        hashes[relative] = (await sha256.bind(file.openRead()).single)
            .toString();
      }
      final id = sha256
          .convert(utf8.encode(jsonEncode([format.name, hashes])))
          .toString();
      final existing = library.models
          .where((model) => model.id == id)
          .firstOrNull;
      final target = _modelDirectory(id);
      if (existing != null && await _hasFiles(target, format)) {
        throw const SpeechFailure(.duplicateModel);
      }
      final voiceCount = await check(format, staging);
      if (!_validVoiceCount(format, voiceCount)) {
        throw const SpeechFailure(.invalidModel);
      }
      final model = SpeechModel(
        id: id,
        format: format,
        name: existing?.name ?? name,
        voiceCount: voiceCount,
      );
      final updated = SpeechLibrary(
        models: [
          for (final entry in library.models)
            if (entry.id == id) model else entry,
          if (existing == null) model,
        ],
        recognitionId:
            library.recognitionId ?? (format.kind == .recognition ? id : null),
        synthesisId:
            library.synthesisId ?? (format.kind == .synthesis ? id : null),
        voice: library.voice,
      );
      await _deleteDirectory(target);
      await staging.rename(target.path);
      try {
        await _write(updated);
      } catch (_) {
        await _deleteDirectory(target);
        rethrow;
      }
      return updated;
    } finally {
      await _cleanTemporary(scratch);
    }
  }

  Future<void> export(SpeechModel model, String outputPath) async {
    final source = await directoryFor(model);
    final files = {
      for (final relative in model.format.files)
        relative: (await _checkedFile(source, relative)).path,
    };
    final destination = File(
      await ZstdTar.exportPath(File(outputPath).absolute.path),
    );
    final scratch = await destination.parent.createTemp('.speech-export-');
    final temporary = File(path.join(scratch.path, 'model${ZstdTar.suffix}'));
    try {
      await SpeechModelPackage.write(temporary.path, files);
      await temporary.rename(destination.path);
    } finally {
      await _cleanTemporary(scratch);
    }
  }

  Future<SpeechLibrary> select(SpeechLibrary library, SpeechModel model) async {
    await directoryFor(model);
    final updated = SpeechLibrary(
      models: library.models,
      recognitionId: model.kind == .recognition
          ? model.id
          : library.recognitionId,
      synthesisId: model.kind == .synthesis ? model.id : library.synthesisId,
      voice: model.kind == .synthesis && model.id != library.synthesisId
          ? 0
          : library.voice,
    );
    await _write(updated);
    return updated;
  }

  Future<SpeechLibrary> selectVoice(SpeechLibrary library, int voice) async {
    final model = library.selectedModel(.synthesis);
    if (model == null || voice < 0 || voice >= model.voiceCount) {
      throw const SpeechFailure(.invalidModel);
    }
    final updated = SpeechLibrary(
      models: library.models,
      recognitionId: library.recognitionId,
      synthesisId: library.synthesisId,
      voice: voice,
    );
    await _write(updated);
    return updated;
  }

  Future<SpeechLibrary> delete(SpeechLibrary library, SpeechModel model) async {
    final directory = _modelDirectory(model.id);
    final root = await _ensureRoot();
    final staging = await root.createTemp('delete-');
    final movedPath = path.join(staging.path, model.id);
    var keepStaging = false;
    var moved = false;
    try {
      final type = await _type(directory.path);
      if (type == .directory) {
        await directory.rename(movedPath);
        moved = true;
      } else if (type != .notFound) {
        throw const SpeechFailure(.storage);
      }
      final deletedSynthesis = library.synthesisId == model.id;
      final updated = SpeechLibrary(
        models: library.models.where((entry) => entry.id != model.id),
        recognitionId: library.recognitionId == model.id
            ? null
            : library.recognitionId,
        synthesisId: deletedSynthesis ? null : library.synthesisId,
        voice: deletedSynthesis ? 0 : library.voice,
      );
      try {
        await _write(updated);
      } catch (_) {
        if (moved) {
          keepStaging = true;
          await Directory(movedPath).rename(directory.path);
          keepStaging = false;
        }
        rethrow;
      }
      return updated;
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
          'recognition': library.recognitionId,
          'synthesis': library.synthesisId,
          'voice': library.voice,
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
    if (await _type(directory.path) != .directory) return false;
    var size = 0;
    try {
      for (final relative in format.files) {
        final file = await _checkedFile(directory, relative);
        final length = await file.length();
        if (length == 0) return false;
        size += length;
        if (size > SpeechModel.maxBytes) return false;
      }
      return true;
    } on SpeechFailure {
      return false;
    } on FileSystemException {
      return false;
    }
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
