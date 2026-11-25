/*
 * @Description: 在内存中采集 Windows 默认麦克风的 PCM 数据。
 */

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../domain/speech_model.dart';
import 'speech_engine.dart';

abstract interface class SpeechAudioInput {
  Future<void> record({
    required Future<bool> stop,
    required void Function() started,
    required void Function(SpeechAudioChunk) onAudio,
  });
}

class WindowsSpeechAudioInput implements SpeechAudioInput {
  const WindowsSpeechAudioInput();

  @override
  Future<void> record({
    required Future<bool> stop,
    required void Function() started,
    required void Function(SpeechAudioChunk) onAudio,
  }) async {
    final recorder = AudioRecorder();
    var capturedBytes = 0;
    final closed = Completer<bool>();
    StreamSubscription<Uint8List>? subscription;
    var sampleRate = speechSampleRate;
    var channels = 1;
    Timer? limit;
    var stopping = false;
    try {
      if (!await recorder.hasPermission(request: false)) {
        throw const SpeechFailure(.microphone);
      }
      await recorder.setOnConfigChanged((config) {
        if (capturedBytes != 0 &&
            (config.sampleRate != sampleRate ||
                config.numChannels != channels)) {
          if (!closed.isCompleted) closed.complete(false);
        }
        sampleRate = config.sampleRate;
        channels = config.numChannels;
      });
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: speechSampleRate,
          numChannels: 1,
        ),
      );
      subscription = stream.listen(
        (data) {
          final maximum = sampleRate * channels * 2 * speechMaxRecordingSeconds;
          final remaining = maximum - capturedBytes;
          if (!closed.isCompleted && remaining > 0 && data.isNotEmpty) {
            final pcm = data.length <= remaining
                ? data
                : Uint8List.sublistView(data, 0, remaining);
            capturedBytes += pcm.length;
            onAudio((pcm: pcm, sampleRate: sampleRate, channels: channels));
          }
        },
        onError: (Object _) {
          if (!closed.isCompleted) closed.complete(false);
        },
        onDone: () {
          if (!closed.isCompleted) closed.complete(stopping);
        },
      );
      final limitReached = Completer<bool>();
      limit = Timer(
        const Duration(seconds: speechMaxRecordingSeconds),
        () => limitReached.complete(true),
      );
      started();
      final transcribe = await Future.any([
        stop,
        limitReached.future,
        closed.future,
      ]);
      if (closed.isCompleted && !await closed.future) {
        throw const SpeechFailure(.microphone);
      }
      if (!transcribe) return;
      stopping = true;
      await recorder.stop();
      if (!await closed.future) throw const SpeechFailure(.microphone);
    } finally {
      limit?.cancel();
      await subscription?.cancel();
      await recorder.dispose();
    }
  }
}
