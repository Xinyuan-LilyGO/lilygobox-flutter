/*
 * @Description: 使用 Windows 默认输出设备播放内存中的语音。
 */

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

abstract interface class SpeechAudioOutput {
  Future<void> play(Uint8List wav, Future<void> cancellation);

  Future<void> playStream(
    Stream<Uint8List> wavChunks,
    Future<void> cancellation,
  );
}

class WindowsSpeechAudioOutput implements SpeechAudioOutput {
  const WindowsSpeechAudioOutput();

  @override
  Future<void> play(Uint8List wav, Future<void> cancellation) =>
      playStream(Stream.value(wav), cancellation);

  @override
  Future<void> playStream(
    Stream<Uint8List> wavChunks,
    Future<void> cancellation,
  ) async {
    final queue = StreamIterator(wavChunks);
    var active = AudioPlayer();
    AudioPlayer? standby = AudioPlayer();
    var cancelled = false;
    var disposed = false;
    var activeCompleted = Completer<void>();
    late StreamSubscription<void> subscription;

    void attach(AudioPlayer player) {
      subscription = player.onPlayerComplete.listen(
        (_) {
          if (!activeCompleted.isCompleted) activeCompleted.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!activeCompleted.isCompleted) {
            activeCompleted.completeError(error, stack);
          }
        },
      );
    }

    attach(active);
    final stopping = cancellation.then((_) {
      cancelled = true;
      if (disposed) return;
      unawaited(active.setVolume(0));
      unawaited(active.pause());
      unawaited(active.stop());
      if (standby case final preloaded?) {
        unawaited(preloaded.setVolume(0));
      }
      if (!activeCompleted.isCompleted) activeCompleted.complete();
    });
    try {
      if (!await queue.moveNext() || cancelled) return;
      await active.setSource(BytesSource(queue.current, mimeType: 'audio/wav'));
      while (!cancelled) {
        activeCompleted = Completer<void>();
        final playing = active.resume();
        Future<bool>? preload;
        if (standby != null) {
          final nextPlayer = standby;
          preload = () async {
            if (!await queue.moveNext() || cancelled) return false;
            await nextPlayer.setSource(
              BytesSource(queue.current, mimeType: 'audio/wav'),
            );
            return !cancelled;
          }();
        }
        await Future.any<void>([
          stopping,
          Future.wait([playing, activeCompleted.future]),
        ]);
        if (cancelled) {
          await active.setVolume(0);
          await active.stop();
          await playing;
          break;
        }
        final hasNext = preload != null ? await preload : false;
        if (!hasNext || cancelled) break;
        await subscription.cancel();
        final previous = active;
        active = standby!;
        standby = previous;
        attach(active);
      }
    } finally {
      disposed = true;
      await queue.cancel();
      await subscription.cancel();
      await active.dispose();
      await standby?.dispose();
    }
  }
}
