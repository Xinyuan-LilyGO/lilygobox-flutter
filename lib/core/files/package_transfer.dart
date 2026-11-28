import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

enum PackageStage {
  preparing,
  reading,
  compressing,
  decompressing,
  verifying,
  checksumming,
  analyzing,
  writing,
  committing,
}

class PackageProgress {
  const PackageProgress(
    this.stage, {
    this.completed,
    this.total,
    this.itemCompleted,
    this.itemTotal,
    this.canCancel = true,
  });

  final PackageStage stage;
  final int? completed;
  final int? total;
  final int? itemCompleted;
  final int? itemTotal;
  final bool canCancel;

  double? get fraction => completed != null && total != null && total! > 0
      ? (completed! / total!).clamp(0, 1)
      : null;

  PackageProgress withBatch(int? completedItems, int? totalItems) =>
      PackageProgress(
        stage,
        completed: completed,
        total: total,
        itemCompleted: completedItems,
        itemTotal: totalItems,
        canCancel: canCancel,
      );
}

class PackageCancelled implements Exception {
  const PackageCancelled();
}

class PackageTransfer {
  PackageTransfer({this.onProgress});

  final void Function(PackageProgress)? onProgress;
  final _cancelled = Completer<void>();
  final _finished = Completer<void>();
  PackageProgress _progress = const PackageProgress(.preparing);
  int? _itemCompleted;
  int? _itemTotal;

  Future<void> get cancellation => _cancelled.future;
  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (_progress.canCancel && !isCancelled && !_finished.isCompleted) {
      _cancelled.complete();
    }
  }

  void check() {
    if (isCancelled) throw const PackageCancelled();
  }

  void reportBatch({required int completed, required int total}) {
    _itemCompleted = completed;
    _itemTotal = total;
    report(_progress.withBatch(completed, total));
  }

  void report(PackageProgress progress) {
    check();
    final effective =
        progress.itemTotal != null || _itemTotal == null
        ? progress
        : progress.withBatch(_itemCompleted, _itemTotal);
    if (effective.stage == _progress.stage &&
        effective.canCancel == _progress.canCancel &&
        effective.itemCompleted == _progress.itemCompleted &&
        effective.itemTotal == _progress.itemTotal &&
        _percent(effective) == _percent(_progress)) {
      return;
    }
    _progress = effective;
    onProgress?.call(effective);
  }

  void commit() => report(const PackageProgress(.committing, canCancel: false));

  static int? _percent(PackageProgress progress) =>
      progress.fraction == null ? null : (progress.fraction! * 100).floor();

  Future<Result> runWorker<Input, Result>(
    Input input,
    FutureOr<Result> Function(Input, PackageTransfer) work,
  ) async {
    check();
    final port = ReceivePort();
    final result = Completer<Result>();
    SendPort? control;
    final completion = Completer<void>();
    unawaited(
      Future.any([cancellation, completion.future]).then((_) {
        if (isCancelled) control?.send(null);
      }),
    );
    final subscription = port.listen((Object? message) {
      if (result.isCompleted) return;
      switch (message) {
        case final SendPort commands:
          control = commands;
          if (isCancelled) commands.send(null);
        case final PackageProgress progress:
          if (!isCancelled) report(progress);
        case (final Object error, final StackTrace stack):
          result.completeError(error, stack);
        case (final Result value,):
          result.complete(value);
        case [final String error, final String stack]:
          result.completeError(StateError(error), StackTrace.fromString(stack));
        default:
          result.completeError(
            StateError('Package worker stopped unexpectedly'),
          );
      }
    });
    try {
      await Isolate.spawn(
        _packageWorker<Input, Result>,
        (input, work, port.sendPort),
        onError: port.sendPort,
        onExit: port.sendPort,
      );
      final value = await result.future;
      check();
      return value;
    } catch (_) {
      check();
      rethrow;
    } finally {
      completion.complete();
      await subscription.cancel();
      port.close();
    }
  }

  Future<void> checkpoint() async {
    await Future<void>.delayed(Duration.zero);
    check();
  }

  Future<void> decompress(
    File source,
    OutputStream output, {
    required int length,
    int? limit,
    required ChunkedConverter decoder,
  }) async {
    final sink = decoder.startChunkedConversion(_LimitedOutput(output, limit));
    var read = 0;
    report(PackageProgress(.decompressing, completed: read, total: length));
    await for (final bytes in source.openRead()) {
      check();
      sink.add(bytes);
      read += bytes.length;
      report(PackageProgress(.decompressing, completed: read, total: length));
      await checkpoint();
    }
    sink.close();
  }

  void finish() => _finished.complete();
}

Future<void> _packageWorker<Input, Result>(
  (Input, FutureOr<Result> Function(Input, PackageTransfer), SendPort) job,
) async {
  final (input, work, reply) = job;
  final commands = ReceivePort();
  final transfer = PackageTransfer(onProgress: reply.send);
  commands.listen((_) => transfer.cancel());
  reply.send(commands.sendPort);
  try {
    final value = await work(input, transfer);
    Isolate.exit(reply, (value,));
  } catch (error, stack) {
    Isolate.exit(reply, (error, stack));
  }
}

class _LimitedOutput implements Sink<List<int>> {
  _LimitedOutput(this.output, this.limit);

  final OutputStream output;
  final int? limit;

  @override
  void add(List<int> bytes) {
    final maxBytes = limit;
    if (maxBytes != null && bytes.length > maxBytes - output.length) {
      throw ArchiveLimitException('Package exceeds unpacked size limit');
    }
    output.writeBytes(bytes);
  }

  @override
  void close() => output.flush();
}
