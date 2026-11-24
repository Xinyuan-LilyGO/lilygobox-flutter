/*
 * @Description: 使用 Windows 默认输出设备播放内存中的语音。
 */

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

abstract interface class SpeechAudioOutput {
  Future<void> play(Uint8List wav, Future<void> cancellation);
}

class WindowsSpeechAudioOutput implements SpeechAudioOutput {
  const WindowsSpeechAudioOutput();

  @override
  Future<void> play(Uint8List wav, Future<void> cancellation) async {
    final player = AudioPlayer();
    final completion = Completer<void>();
    final subscription = player.onPlayerComplete.listen(
      (_) {
        if (!completion.isCompleted) completion.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (!completion.isCompleted) completion.completeError(error, stack);
      },
    );
    final stopping = cancellation.then((_) {
      if (!completion.isCompleted) completion.complete();
    });
    try {
      final playing = player.play(BytesSource(wav, mimeType: 'audio/wav'));
      await Future.any<void>([
        stopping,
        Future.wait([playing, completion.future]),
      ]);
      await player.stop();
      await playing;
    } finally {
      await subscription.cancel();
      await player.dispose();
    }
  }
}
