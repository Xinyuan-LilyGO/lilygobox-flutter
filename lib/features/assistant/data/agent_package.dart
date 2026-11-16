import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:koni_archive_core/koni_archive_core.dart';
import 'package:koni_sevenz/koni_sevenz.dart';
import 'package:lilygobox_codecs/lilygobox_codecs.dart';

import '../domain/agent_package_progress.dart';
export '../domain/agent_package_progress.dart';

/// 独立的 7z/LZMA2 数据包，不向文件系统解压内容。
abstract final class AgentPackage {
  static Future<void> write(
    String path,
    Map<String, Object?> payload, {
    void Function(AgentPackageProgress)? onProgress,
    AgentPackageCancellation? cancellation,
  }) async {
    final temporary = File(
      '$path.${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    try {
      await _run('write', temporary.path, payload, onProgress, cancellation);
      cancellation?.throwIfCancelled();
      // 文件替换是短暂的提交阶段，此时不能中断。
      onProgress?.call(
        const AgentPackageProgress(
          AgentPackageStage.committing,
          canCancel: false,
        ),
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
  }) async => Map<String, dynamic>.from(
    await _run('read', path, null, onProgress, cancellation) as Map,
  );

  static Future<Object?> _run(
    String kind,
    String path,
    Map<String, Object?>? payload,
    void Function(AgentPackageProgress)? onProgress,
    AgentPackageCancellation? cancellation,
  ) async {
    cancellation?.throwIfCancelled();
    final flag = CodecCancellation();
    final port = ReceivePort();
    final result = Completer<Object?>();
    cancellation?.addListener(flag.cancel);
    final subscription = port.listen((dynamic message) {
      if (result.isCompleted) return;
      if (message is List && message.isNotEmpty) {
        switch (message.first) {
          case 'progress':
            onProgress?.call(message[1] as AgentPackageProgress);
          case 'done':
            result.complete(message[1]);
          case 'error':
            result.completeError(
              message[1] as Object,
              StackTrace.fromString(message[2] as String),
            );
          default:
            result.completeError(StateError('Package worker failed: $message'));
        }
      } else if (message == null) {
        result.completeError(StateError('Package worker stopped unexpectedly'));
      }
    });
    try {
      await Isolate.spawn(
        _packageWorker,
        _PackageJob(kind, path, payload, port.sendPort, flag.address),
        onError: port.sendPort,
        onExit: port.sendPort,
      );
      return await result.future;
    } finally {
      cancellation?.removeListener(flag.cancel);
      await subscription.cancel();
      port.close();
      flag.dispose();
    }
  }
}

class _PackageJob {
  const _PackageJob(
    this.kind,
    this.path,
    this.payload,
    this.port,
    this.cancelAddress,
  );
  final String kind;
  final String path;
  final Map<String, Object?>? payload;
  final SendPort port;
  final int cancelAddress;
}

Future<void> _packageWorker(_PackageJob job) async {
  final cancellation = CodecCancellation.borrowed(job.cancelAddress);
  void check() {
    if (cancellation.isCancelled) throw const AgentPackageCancelled();
  }

  void report(AgentPackageStage stage, {int? completed, int? total}) {
    job.port.send([
      'progress',
      AgentPackageProgress(stage, completed: completed, total: total),
    ]);
  }

  try {
    Object? result;
    if (job.kind == 'write') {
      report(AgentPackageStage.preparing);
      final payload = job.payload!;
      final content = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
      check();
      final manifest = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 'LilygoBox.agent-data',
            'version': 1,
            'type': payload['type'],
            'sha256': sha256.convert(content).toString(),
            'size': content.length,
          }),
        ),
      );
      report(
        AgentPackageStage.compressing,
        completed: 0,
        total: content.length,
      );
      var lastPercent = -1;
      final compressed = LilygoBoxCodecs.lzma2(
        content,
        cancellation: cancellation,
        onProgress: (input, output) {
          final percent = content.isEmpty ? 100 : input * 100 ~/ content.length;
          if (percent != lastPercent) {
            lastPercent = percent;
            report(
              AgentPackageStage.compressing,
              completed: input,
              total: content.length,
            );
          }
        },
      );
      report(
        AgentPackageStage.compressing,
        completed: content.length,
        total: content.length,
      );
      final sink = BytesBuilderSink();
      final writer = const SevenZWriteFormat().openWriter(
        sink,
        const ArchiveWriteOptions(compression: ArchiveCompression.stored),
      );
      await writer.addBytes(ArchiveEntrySpec(path: 'manifest.json'), manifest);
      await writer.addBytes(ArchiveEntrySpec(path: 'data.lzma2'), compressed);
      await writer.close();
      await sink.close();
      final bytes = sink.takeBytes();
      await _decode(bytes, cancellation, report, verifyingExport: true);
      check();
      final file = await File(job.path).open(mode: FileMode.write);
      try {
        const chunkSize = 256 * 1024;
        report(AgentPackageStage.writing, completed: 0, total: bytes.length);
        for (var offset = 0; offset < bytes.length; offset += chunkSize) {
          check();
          final end = (offset + chunkSize).clamp(0, bytes.length);
          await file.writeFrom(bytes, offset, end);
          report(
            AgentPackageStage.writing,
            completed: end,
            total: bytes.length,
          );
        }
        await file.flush();
      } finally {
        await file.close();
      }
    } else {
      final input = File(job.path);
      final length = await input.length();
      if (length > 512 * 1024 * 1024) {
        throw const FormatException('Package exceeds import memory budget');
      }
      final builder = BytesBuilder();
      var count = 0;
      report(AgentPackageStage.reading, completed: 0, total: length);
      await for (final chunk in input.openRead()) {
        check();
        builder.add(chunk);
        count += chunk.length;
        report(AgentPackageStage.reading, completed: count, total: length);
      }
      result = await _decode(builder.takeBytes(), cancellation, report);
    }
    check();
    job.port.send(['done', result]);
  } on CodecCancelled {
    job.port.send([
      'error',
      const AgentPackageCancelled(),
      StackTrace.current.toString(),
    ]);
  } catch (error, stack) {
    job.port.send(['error', error, stack.toString()]);
  }
}

typedef _Report = void Function(
  AgentPackageStage, {
  int? completed,
  int? total,
});

Future<Map<String, dynamic>> _decode(
  Uint8List bytes,
  CodecCancellation cancellation,
  _Report report, {
  bool verifyingExport = false,
}) async {
  final source = MemoryByteSource(bytes);
  report(AgentPackageStage.verifying);
  if (!await const SevenZFormat().matches(source)) {
    throw const FormatException('Not a LilygoBox package');
  }
  final reader = await const SevenZFormat().createReader(
    source,
    const ArchiveReadOptions(
      maxEntryCount: 2,
      maxEntrySize: 512 * 1024 * 1024,
      maxContainerDecodeSize: 512 * 1024 * 1024,
    ),
  );
  try {
    if (reader.entries.length != 2 ||
        reader.entries.map((e) => e.path).toSet().difference({
          'manifest.json',
          'data.lzma2',
        }).isNotEmpty) {
      throw const FormatException('Invalid package structure');
    }
    Future<Uint8List> read(String name) async {
      final builder = BytesBuilder();
      await for (final chunk in reader.openRead(
        reader.entries.singleWhere((e) => e.path == name),
      )) {
        if (cancellation.isCancelled) throw const AgentPackageCancelled();
        builder.add(chunk);
      }
      return builder.takeBytes();
    }

    final manifest =
        jsonDecode(utf8.decode(await read('manifest.json'))) as Map;
    if (manifest['format'] != 'LilygoBox.agent-data' ||
        manifest['version'] != 1) {
      throw const FormatException('Unsupported package version');
    }
    final compressed = await read('data.lzma2');
    final stage = verifyingExport
        ? AgentPackageStage.verifying
        : AgentPackageStage.decompressing;
    final expected = manifest['size'];
    if (expected is! int || expected < 0 || expected > 512 * 1024 * 1024) {
      throw const FormatException('Invalid package size');
    }
    var lastPercent = -1;
    report(stage, completed: 0, total: expected);
    final data = LilygoBoxCodecs.unlzma2(
      compressed,
      cancellation: cancellation,
      onProgress: (input, output) {
        final percent = expected == 0 ? 100 : output * 100 ~/ expected;
        if (lastPercent != percent) {
          lastPercent = percent;
          report(stage, completed: output, total: expected);
        }
      },
    );
    report(AgentPackageStage.verifying);
    if (data.length != manifest['size'] ||
        sha256.convert(data).toString() != manifest['sha256']) {
      throw const FormatException('Package checksum mismatch');
    }
    report(AgentPackageStage.analyzing);
    final payload = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    if (!['memory', 'chat', 'agent', 'workflow'].contains(payload['type']) ||
        payload['type'] != manifest['type']) {
      throw const FormatException('Invalid package type');
    }
    return payload;
  } finally {
    await reader.close();
    await source.close();
  }
}
