/*
 * @Description: 在内存中采集 Windows 默认麦克风的 PCM 数据。
 */

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../domain/speech_model.dart';
import 'speech_engine.dart';

typedef SpeechRecording = ({Uint8List pcm, int sampleRate, int channels});

abstract interface class SpeechAudioInput {
  Future<SpeechRecording?> record({
    required Future<bool> stop,
    required void Function() started,
  });
}

class WindowsSpeechAudioInput implements SpeechAudioInput {
  const WindowsSpeechAudioInput();

  @override
  Future<SpeechRecording?> record({
    required Future<bool> stop,
    required void Function() started,
  }) async {
    final recorder = AudioRecorder();
    final bytes = BytesBuilder(copy: false);
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
        if (bytes.isNotEmpty &&
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
          final remaining = maximum - bytes.length;
          if (remaining > 0) {
            bytes.add(
              data.length <= remaining
                  ? data
                  : Uint8List.sublistView(data, 0, remaining),
            );
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
      if (!transcribe) return null;
      stopping = true;
      await recorder.stop();
      if (!await closed.future) throw const SpeechFailure(.microphone);
      return (
        pcm: bytes.takeBytes(),
        sampleRate: sampleRate,
        channels: channels,
      );
    } finally {
      limit?.cancel();
      await subscription?.cancel();
      await recorder.dispose();
    }
  }
}
