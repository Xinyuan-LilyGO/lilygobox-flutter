/*
 * @Description: 使用 Windows 默认输出设备播放内存中的语音。
 */

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'speech_aec3.dart';

abstract interface class SpeechAudioOutput {
  Future<void> play(
    Uint8List wav,
    Future<void> cancellation, {
    String? deviceId,
  });

  Future<void> playStream(
    Stream<Uint8List> wavChunks,
    Future<void> cancellation, {
    String? deviceId,
  });
}

class WindowsSpeechAudioOutput implements SpeechAudioOutput {
  const WindowsSpeechAudioOutput();

  @override
  Future<void> play(
    Uint8List wav,
    Future<void> cancellation, {
    String? deviceId,
  }) => playStream(Stream.value(wav), cancellation, deviceId: deviceId);

  @override
  Future<void> playStream(
    Stream<Uint8List> wavChunks,
    Future<void> cancellation, {
    String? deviceId,
  }) async {
    if (deviceId != null && deviceId.isNotEmpty) {
      await _playToTargetDevice(wavChunks, cancellation, deviceId);
      return;
    }
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

  Future<void> _playToTargetDevice(
    Stream<Uint8List> wavChunks,
    Future<void> cancellation,
    String deviceId,
  ) async {
    var cancelled = false;
    unawaited(cancellation.then((_) => cancelled = true));
    WebRtcAec3Playback? playback;
    try {
      await for (final wav in wavChunks) {
        if (cancelled) break;
        final parsed = _parseWavPcm16(wav);
        if (parsed == null) continue;
        playback ??= WebRtcAec3Playback.start(
          playbackDeviceId: deviceId,
          sampleRateHz: parsed.sampleRate,
          channels: parsed.channels,
        );
        if (playback == null) return;
        playback.writePcm16Bytes(parsed.pcm);
      }
      if (playback == null || cancelled) return;
      playback.finish();
      while (!cancelled && !playback.isFinished) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      playback?.stop();
    }
  }

  static ({int sampleRate, int channels, Uint8List pcm})? _parseWavPcm16(
    Uint8List wav,
  ) {
    if (wav.length < 44) return null;
    final data = ByteData.sublistView(wav);
    final channels = data.getUint16(22, Endian.little);
    final sampleRate = data.getUint32(24, Endian.little);
    var offset = 12;
    while (offset + 8 <= wav.length) {
      final chunkId = String.fromCharCodes(wav, offset, offset + 4);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final payloadStart = offset + 8;
      if (chunkId == 'data' && payloadStart <= wav.length) {
        final end = (payloadStart + chunkSize).clamp(payloadStart, wav.length);
        return (
          sampleRate: sampleRate,
          channels: channels,
          pcm: Uint8List.sublistView(wav, payloadStart, end),
        );
      }
      offset = payloadStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    return null;
  }
}
