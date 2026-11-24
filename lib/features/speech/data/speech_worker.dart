/*
 * @Description: 在 Windows 子进程中调用 sherpa-onnx 并通过管道传输音频。
 */

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../domain/speech_model.dart';
import 'speech_engine.dart';

Future<void> runSpeechWorker({String? dllDirectory}) async {
  try {
    final directory = dllDirectory ?? path.dirname(Platform.resolvedExecutable);
    DynamicLibrary.open(path.join(directory, 'onnxruntime.dll'));
    sherpa.initBindings(directory);
  } catch (_) {
    exit(78);
  }

  try {
    final request = jsonDecode(await stdin.transform(utf8.decoder).join());
    final response = _process(request);
    stdout.writeln('$speechWorkerResultPrefix${jsonEncode(response)}');
    await stdout.flush();
    exit(0);
  } catch (_) {
    exit(65);
  }
}

Map<String, Object> _process(Object? request) {
  if (request case {
    'operation': final String operation,
    'format': final String formatName,
    'directory': final String directory,
  }) {
    final format = SpeechModelFormat.values.byName(formatName);
    return switch ((operation, format, request)) {
      ('check', .bilingualZipformer, _) => _checkRecognizer(directory),
      ('check', .chineseVits, _) => _checkSynthesis(directory),
      (
        'recognize',
        .bilingualZipformer,
        {
          'pcm': final String pcm,
          'sampleRate': final int sampleRate,
          'channels': final int channels,
        },
      ) =>
        {
          'text': _recognize(
            directory,
            base64Decode(pcm),
            sampleRate,
            channels,
          ),
        },
      (
        'synthesize',
        .chineseVits,
        {'text': final String text, 'voice': final int voice},
      ) =>
        {'wav': base64Encode(_synthesize(directory, text, voice))},
      _ => throw const FormatException(),
    };
  }
  throw const FormatException();
}

sherpa.OnlineRecognizer _recognizer(String directory) {
  final [encoder, decoder, joiner, tokens] =
      SpeechModelFormat.bilingualZipformer.files;
  return sherpa.OnlineRecognizer(
    sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: path.join(directory, encoder),
          decoder: path.join(directory, decoder),
          joiner: path.join(directory, joiner),
        ),
        tokens: path.join(directory, tokens),
        numThreads: 2,
        debug: false,
      ),
    ),
  );
}

Map<String, int> _checkRecognizer(String directory) {
  final recognizer = _recognizer(directory);
  recognizer.free();
  return {'voices': 0};
}

String _recognize(
  String directory,
  Uint8List pcm,
  int sampleRate,
  int channels,
) {
  final frameSize = channels * 2;
  if (sampleRate < 8000 ||
      sampleRate > 96000 ||
      channels < 1 ||
      channels > 2 ||
      pcm.length < frameSize ||
      pcm.length % frameSize != 0 ||
      pcm.length > sampleRate * speechMaxRecordingSeconds * frameSize) {
    throw const FormatException();
  }
  final input = ByteData.sublistView(pcm);
  final frames = pcm.length ~/ frameSize;
  final samples = Float32List(frames + sampleRate ~/ 2);
  for (var index = 0; index < frames; index++) {
    final offset = index * frameSize;
    final first = input.getInt16(offset, Endian.little);
    samples[index] = channels == 1
        ? first / 32768
        : (first + input.getInt16(offset + 2, Endian.little)) / 65536;
  }

  final recognizer = _recognizer(directory);
  try {
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      stream.inputFinished();
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}

sherpa.OfflineTts _synthesizer(String directory) => sherpa.OfflineTts(
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

Map<String, int> _checkSynthesis(String directory) {
  final tts = _synthesizer(directory);
  try {
    final preview = tts.generate(text: '你好。', sid: 0);
    if (preview.samples.isEmpty || preview.sampleRate <= 0) {
      throw const FormatException();
    }
    return {'voices': tts.numSpeakers};
  } finally {
    tts.free();
  }
}

Uint8List _synthesize(String directory, String text, int voice) {
  if (text.trim().isEmpty) throw const FormatException();
  final tts = _synthesizer(directory);
  try {
    if (voice < 0 || voice >= tts.numSpeakers) throw const FormatException();
    final pcm = BytesBuilder(copy: false);
    var sampleRate = 0;
    for (final chunk in _utterances(text)) {
      final audio = tts.generate(text: chunk, sid: voice);
      if (audio.samples.isEmpty) continue;
      if (audio.sampleRate <= 0 ||
          (sampleRate != 0 && sampleRate != audio.sampleRate)) {
        throw const FormatException();
      }
      sampleRate = audio.sampleRate;
      final bytes = ByteData(audio.samples.length * 2);
      for (final (index, sample) in audio.samples.indexed) {
        final value = sample.isFinite ? sample.clamp(-1.0, 1.0) : 0.0;
        bytes.setInt16(index * 2, (value * 32767).round(), Endian.little);
      }
      pcm.add(bytes.buffer.asUint8List());
    }
    if (pcm.isEmpty) throw const FormatException();
    final header = ByteData(44)
      ..setUint32(0, 0x52494646)
      ..setUint32(4, pcm.length + 36, Endian.little)
      ..setUint32(8, 0x57415645)
      ..setUint32(12, 0x666d7420)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x64617461)
      ..setUint32(40, pcm.length, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(pcm.takeBytes()))
        .takeBytes();
  } finally {
    tts.free();
  }
}

Iterable<String> _utterances(String text) sync* {
  final buffer = StringBuffer();
  const punctuation = {0x3002, 0xff01, 0xff1f, 0x0a, 0x21, 0x3f, 0x2e};
  for (final rune in text.runes) {
    buffer.writeCharCode(rune);
    if (buffer.length >= 240 ||
        (buffer.length >= 24 && punctuation.contains(rune))) {
      final sentence = buffer.toString().trim();
      if (sentence.isNotEmpty) yield sentence;
      buffer.clear();
    }
  }
  final sentence = buffer.toString().trim();
  if (sentence.isNotEmpty) yield sentence;
}
