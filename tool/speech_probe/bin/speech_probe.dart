import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main(List<String> arguments) {
  if (!Platform.isWindows || arguments.length < 5 || arguments.length > 6) {
    stderr.writeln(
      'Usage (Windows): speech_probe <dll-dir> <zipformer-dir> <input.wav> '
      '<vits-zh-dir> <output.wav> [expected-asr-text]',
    );
    exitCode = 64;
    return;
  }

  final [dllDirectory, asrDirectory, input, ttsDirectory, output] = arguments
      .take(5)
      .map(path.absolute)
      .toList();
  DynamicLibrary.open(path.join(dllDirectory, 'onnxruntime.dll'));
  sherpa.initBindings(dllDirectory);

  final stopwatch = Stopwatch()..start();
  final text = _recognize(asrDirectory, input);
  final expected = arguments.length == 6 ? arguments.last : null;
  if (expected == null
      ? !RegExp(r'[\u3400-\u9fff]').hasMatch(text)
      : !text.contains(expected)) {
    throw StateError('Expected ${expected ?? 'a Chinese transcript'}, received: $text');
  }
  stdout.writeln('ASR (${stopwatch.elapsedMilliseconds} ms): $text');

  stopwatch.reset();
  final (sampleRate, samples, voices) = _synthesize(ttsDirectory, output);
  stdout.writeln(
    'TTS (${stopwatch.elapsedMilliseconds} ms): '
    '$samples frames at $sampleRate Hz, $voices voices, $output',
  );
}

String _recognize(String directory, String input) {
  final wave = sherpa.readWave(input);
  if (wave.sampleRate <= 0 || wave.samples.isEmpty) {
    throw StateError('Invalid input audio: $input');
  }
  final recognizer = sherpa.OnlineRecognizer(
    sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: path.join(directory, 'encoder-epoch-99-avg-1.int8.onnx'),
          decoder: path.join(directory, 'decoder-epoch-99-avg-1.onnx'),
          joiner: path.join(directory, 'joiner-epoch-99-avg-1.int8.onnx'),
        ),
        tokens: path.join(directory, 'tokens.txt'),
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    stream.acceptWaveform(
      samples: Float32List(wave.sampleRate ~/ 2),
      sampleRate: wave.sampleRate,
    );
    stream.inputFinished();
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    return recognizer.getResult(stream).text.trim();
  } finally {
    stream.free();
    recognizer.free();
  }
}

(int, int, int) _synthesize(String directory, String output) {
  final tts = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: path.join(directory, 'model.onnx'),
          lexicon: path.join(directory, 'lexicon.txt'),
          tokens: path.join(directory, 'tokens.txt'),
          dictDir: path.join(directory, 'dict'),
        ),
        numThreads: 2,
        debug: false,
      ),
      ruleFsts: [
        for (final name in ['phone.fst', 'date.fst', 'number.fst'])
          path.join(directory, name),
      ].join(','),
    ),
  );
  try {
    final audio = tts.generate(text: '你好，这是一段离线语音测试。', sid: 0);
    if (audio.sampleRate <= 0 ||
        audio.samples.length < audio.sampleRate ~/ 4 ||
        !audio.samples.any((sample) => sample.isFinite && sample.abs() > 0.01)) {
      throw StateError('No audible speech samples produced');
    }
    final written = sherpa.writeWave(
      filename: output,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    if (!written) throw StateError('Cannot write output WAV: $output');
    return (audio.sampleRate, audio.samples.length, tts.numSpeakers);
  } finally {
    tts.free();
  }
}
