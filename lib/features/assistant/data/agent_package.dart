/*
 * @Description: 读写使用 Zstd 压缩的智能体数据包。
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../../../core/files/zstd_file.dart';
import '../../../core/files/zstd_tar.dart';
import '../domain/agent_package_progress.dart';
export '../domain/agent_package_progress.dart';

const _format = 'LilygoBox.agent-data';
const _manifestName = 'manifest.json';
const _bodyName = 'data.json';
const _maxBodyBytes = 512 * 1024 * 1024;
const _maxManifestBytes = 4096;
const _maxTarBytes = _maxBodyBytes + _maxManifestBytes + 4 * 512;
const _maxArchiveBytes = _maxTarBytes + 1024 * 1024;
const _ioChunkBytes = 256 * 1024;
const _types = ['memory', 'chat', 'agent', 'workflow'];

abstract final class AgentPackage {
  static Future<void> write(
    String requestedPath,
    Map<String, Object?> payload, {
    void Function(AgentPackageProgress)? onProgress,
    AgentPackageCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final path = await ZstdTar.exportPath(requestedPath);
    final bytes = await _run<Uint8List>(payload, onProgress, cancellation);
    final temporary = File(
      '$path.${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    try {
      cancellation?.throwIfCancelled();
      final file = await temporary.open(mode: FileMode.write);
      try {
        onProgress?.call(
          AgentPackageProgress(.writing, completed: 0, total: bytes.length),
        );
        for (var offset = 0; offset < bytes.length; offset += _ioChunkBytes) {
          cancellation?.throwIfCancelled();
          final end = (offset + _ioChunkBytes).clamp(0, bytes.length);
          await file.writeFrom(bytes, offset, end);
          onProgress?.call(
            AgentPackageProgress(.writing, completed: end, total: bytes.length),
          );
        }
        await file.flush();
      } finally {
        await file.close();
      }
      cancellation?.throwIfCancelled();
      onProgress?.call(
        const AgentPackageProgress(.committing, canCancel: false),
      );
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<Map<String, dynamic>> read(
    String path, {
    void Function(AgentPackageProgress)? onProgress,
    AgentPackageCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final input = File(path);
    final length = await input.length();
    if (length > _maxArchiveBytes) {
      throw const FormatException('Package exceeds import memory budget');
    }
    onProgress?.call(
      AgentPackageProgress(.reading, completed: 0, total: length),
    );
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in input.openRead(0, length)) {
      cancellation?.throwIfCancelled();
      bytes.add(chunk);
      onProgress?.call(
        AgentPackageProgress(.reading, completed: bytes.length, total: length),
      );
    }
    return _run<Map<String, dynamic>>(
      bytes.takeBytes(),
      onProgress,
      cancellation,
    );
  }

  static Future<Result> _run<Result>(
    Object input,
    void Function(AgentPackageProgress)? onProgress,
    AgentPackageCancellation? cancellation,
  ) async {
    cancellation?.throwIfCancelled();
    final port = ReceivePort();
    final result = Completer<Result>();
    final subscription = port.listen((Object? message) {
      if (result.isCompleted) return;
      switch (message) {
        case AgentPackageProgress():
          if (!(cancellation?.isCancelled ?? false)) {
            try {
              onProgress?.call(message);
            } catch (error, stack) {
              result.completeError(error, stack);
            }
          }
        case (final Object error, final StackTrace stack):
          result.completeError(error, stack);
        case [final String error, final String stack]:
          result.completeError(StateError(error), StackTrace.fromString(stack));
        case null when cancellation?.isCancelled ?? false:
          result.completeError(const AgentPackageCancelled());
        case null:
          result.completeError(
            StateError('Package worker stopped unexpectedly'),
          );
        case final Result value:
          result.complete(value);
        default:
          result.completeError(StateError('Invalid package worker result'));
      }
    });
    Isolate? worker;
    void Function()? cancel;
    try {
      final isolate = await Isolate.spawn(
        _packageWorker,
        (input, port.sendPort),
        onError: port.sendPort,
        onExit: port.sendPort,
        paused: true,
      );
      worker = isolate;
      cancel = () => isolate.kill(priority: Isolate.immediate);
      cancellation?.addListener(cancel);
      if (!(cancellation?.isCancelled ?? false)) {
        isolate.resume(isolate.pauseCapability!);
      }
      final value = await result.future;
      cancellation?.throwIfCancelled();
      return value;
    } finally {
      if (cancel != null) cancellation?.removeListener(cancel);
      worker?.kill(priority: Isolate.immediate);
      await subscription.cancel();
      port.close();
    }
  }
}

Future<void> _packageWorker((Object, SendPort) job) async {
  final (input, port) = job;
  void report(AgentPackageStage stage, {int? completed, int? total}) => port
      .send(AgentPackageProgress(stage, completed: completed, total: total));

  try {
    final result = switch (input) {
      Map<String, Object?>() => await _encode(input, report),
      Uint8List() => (await _readArchive(input, report))!,
      _ => throw ArgumentError('Invalid package worker input'),
    };
    Isolate.exit(port, result);
  } catch (error, stack) {
    Isolate.exit(port, (error, stack));
  }
}

typedef _Report = void Function(
  AgentPackageStage, {
  int? completed,
  int? total,
});

Future<Uint8List> _encode(Map<String, Object?> payload, _Report report) async {
  report(.preparing);
  final type = payload['type'];
  if (!_types.contains(type)) {
    throw const FormatException('Invalid package type');
  }
  final encoded = JsonUtf8Encoder().convert(payload);
  if (encoded.length > _maxBodyBytes) {
    throw const FormatException('Package exceeds export memory budget');
  }
  final body = encoded is Uint8List ? encoded : Uint8List.fromList(encoded);
  final checksum = await _hash(_chunks(body), body.length, report);
  final manifest = utf8.encode(
    jsonEncode({
      'format': _format,
      'version': 1,
      'type': type,
      'sha256': checksum,
      'size': body.length,
    }),
  );
  report(.compressing);
  final output = OutputMemoryStream();
  ZstdTar.writer(output)
    ..add(ArchiveFile.bytes(_manifestName, manifest))
    ..add(ArchiveFile.bytes(_bodyName, body))
    ..close();
  final bytes = output.getBytes();
  await _readArchive(bytes, report, verifyingExport: true);
  return bytes;
}

Stream<Uint8List> _chunks(Uint8List data) async* {
  for (var offset = 0; offset < data.length; offset += _ioChunkBytes) {
    yield Uint8List.sublistView(
      data,
      offset,
      (offset + _ioChunkBytes).clamp(0, data.length),
    );
  }
}

Future<String> _hash(
  Stream<Uint8List> chunks,
  int length,
  _Report report, {
  ByteConversionSink? text,
}) async {
  Stream<List<int>> measured() async* {
    var count = 0;
    var percent = 0;
    await for (final chunk in chunks) {
      if (count == 0) report(.checksumming, completed: 0, total: length);
      count += chunk.length;
      if (count > length) throw const FormatException('Package size mismatch');
      text?.addSlice(chunk, 0, chunk.length, false);
      yield chunk;
      final next = count * 100 ~/ length;
      if (next != percent) {
        percent = next;
        report(.checksumming, completed: count, total: length);
      }
    }
    if (count != length) throw const FormatException('Package size mismatch');
    text?.close();
  }

  return (await sha256.bind(measured()).single).toString();
}

Future<Map<String, dynamic>?> _readArchive(
  Uint8List bytes,
  _Report report, {
  bool verifyingExport = false,
}) async {
  report(.verifying);
  if (!verifyingExport) report(.decompressing);
  final output = OutputMemoryStream();
  final entries = <String, ArchiveFile>{};
  try {
    ZstdFile.decompress(
      InputMemoryStream(bytes),
      output,
      maxBytes: _maxTarBytes,
    );
    TarDecoder().decodeBytes(
      output.getBytes(),
      verify: true,
      keepEntries: false,
      callback: (entry) {
        if (!entry.isFile ||
            entry.isSymbolicLink ||
            entry.isHardLink ||
            entry.size < 1 ||
            switch (entry.name) {
              _manifestName => entry.size > _maxManifestBytes,
              _bodyName => entry.size > _maxBodyBytes,
              _ => true,
            } ||
            entries.containsKey(entry.name)) {
          throw const FormatException('Invalid package structure');
        }
        entries[entry.name] = entry;
      },
    );
  } on ArchiveException catch (error) {
    throw FormatException('Invalid Zstd archive', error);
  }
  final manifest = entries[_manifestName];
  final body = entries[_bodyName];
  if (manifest == null || body == null) {
    throw const FormatException('Invalid package structure');
  }
  final metadata = jsonDecode(utf8.decode(manifest.content));
  if (metadata is! Map<String, dynamic> ||
      metadata['format'] != _format ||
      metadata['version'] != 1) {
    throw const FormatException('Unsupported package version');
  }
  final length = metadata['size'];
  final type = metadata['type'];
  if (length is! int || length != body.size || !_types.contains(type)) {
    throw const FormatException('Invalid package metadata');
  }
  final text = verifyingExport ? null : StringBuffer();
  final checksum = await _hash(
    _chunks(body.content),
    length,
    report,
    text: text == null
        ? null
        : utf8.decoder.startChunkedConversion(
            StringConversionSink.fromStringSink(text),
          ),
  );
  if (checksum != metadata['sha256']) {
    throw const FormatException('Package checksum mismatch');
  }
  if (text == null) return null;
  report(.analyzing);
  final payload = jsonDecode(text.toString());
  if (payload is! Map<String, dynamic> || payload['type'] != type) {
    throw const FormatException('Invalid package type');
  }
  return payload;
}
