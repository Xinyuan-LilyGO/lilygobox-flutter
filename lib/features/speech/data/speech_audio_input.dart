/*
 * @Description: 在内存中采集 Windows 默认麦克风的 PCM 数据。
 */

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../domain/speech_model.dart';
import 'speech_aec3.dart';
import 'speech_engine.dart';

abstract interface class SpeechAudioInput {
  Future<void> record({
    required Future<bool> stop,
    required void Function() started,
    required void Function(SpeechAudioChunk) onAudio,
    bool continuous = false,
    String? captureDeviceId,
    String? playbackDeviceId,
  });
}

class WindowsSpeechAudioInput implements SpeechAudioInput {
  const WindowsSpeechAudioInput();

  @override
  Future<void> record({
    required Future<bool> stop,
    required void Function() started,
    required void Function(SpeechAudioChunk) onAudio,
    bool continuous = false,
    String? captureDeviceId,
    String? playbackDeviceId,
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
      final aec3 = WebRtcAec3LiveCapture.start(
        speechSampleRate,
        captureDeviceId: captureDeviceId,
        playbackDeviceId: playbackDeviceId,
      );
      if (aec3 != null) {
        try {
          var running = true;
          final done = Completer<bool>();
          if (!continuous) {
            limit = Timer(
              const Duration(seconds: speechMaxRecordingSeconds),
              () {
                if (!done.isCompleted) done.complete(true);
              },
            );
          }
          unawaited(
            stop.then((value) {
              if (!done.isCompleted) done.complete(value);
            }),
          );
          started();
          while (running && !done.isCompleted) {
            final pcm = aec3.readAvailablePcm();
            if (pcm == null) {
              throw const SpeechFailure(.microphone);
            }
            if (pcm.isNotEmpty) {
              if (continuous) {
                onAudio((
                  pcm: pcm,
                  sampleRate: speechSampleRate,
                  channels: 1,
                ));
              } else {
                const maximum =
                    speechSampleRate * 2 * speechMaxRecordingSeconds;
                final remaining = maximum - capturedBytes;
                if (remaining > 0) {
                  final slice = pcm.length <= remaining
                      ? pcm
                      : Uint8List.sublistView(pcm, 0, remaining);
                  capturedBytes += slice.length;
                  onAudio((
                    pcm: slice,
                    sampleRate: speechSampleRate,
                    channels: 1,
                  ));
                }
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
            running = !done.isCompleted;
          }
          return;
        } finally {
          limit?.cancel();
          aec3.close();
          await recorder.dispose();
        }
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
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      subscription = stream.listen(
        (data) {
          if (closed.isCompleted || data.isEmpty) return;
          if (continuous) {
            onAudio((pcm: data, sampleRate: sampleRate, channels: channels));
            return;
          }
          final maximum = sampleRate * channels * 2 * speechMaxRecordingSeconds;
          final remaining = maximum - capturedBytes;
          if (remaining > 0) {
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
      if (!continuous) {
        limit = Timer(
          const Duration(seconds: speechMaxRecordingSeconds),
          () => limitReached.complete(true),
        );
      }
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
