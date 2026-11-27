/*
 * @Description: 在 Windows 子进程中调用 sherpa-onnx 并通过管道传输音频。
 */

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../domain/speech_model.dart';
import 'speech_engine.dart';

Future<void> runSpeechWorker({String? dllDirectory}) async {
  stdout.encoding = utf8;
  try {
    final directory = dllDirectory ?? path.dirname(Platform.resolvedExecutable);
    DynamicLibrary.open(path.join(directory, 'onnxruntime.dll'));
    sherpa.initBindings(directory);
  } catch (_) {
    exit(78);
  }

  try {
    final input = StreamIterator(
      stdin.transform(utf8.decoder).transform(const LineSplitter()),
    );
    if (!await input.moveNext()) throw const FormatException();
    final request = jsonDecode(input.current);
    if (request case {
      'operation': 'synthesize-session',
    }) {
      await _runSynthesisSession(input);
      exit(0);
    }
    if (request case {
      'operation': 'recognize-continuous',
      'format': final String formatName,
      'directory': final String directory,
      'partialResults': final bool partialResults,
    }) {
      final format = SpeechModelFormat.values.byName(formatName);
      final silence = switch (request['silenceSeconds']) {
        final num value => clampSpeechSendSilenceSeconds(value.toDouble()),
        _ => defaultSpeechSendSilenceSeconds,
      };
      if (format == .senseVoice) {
        await _recognizeContinuousOffline(
          directory,
          format,
          input,
          silenceSeconds: silence,
        );
      } else {
        await _recognizeContinuous(
          directory,
          format,
          input,
          partialResults,
          silenceSeconds: silence,
        );
      }
      exit(0);
    }
    final response = switch (request) {
      {
        'operation': 'recognize',
        'format': final String formatName,
        'directory': final String directory,
        'partialResults': final bool partialResults,
      } =>
        {
          'text': SpeechModelFormat.values.byName(formatName) == .senseVoice
              ? await _recognizeOffline(
                  directory,
                  SpeechModelFormat.values.byName(formatName),
                  input,
                )
              : await _recognize(
                  directory,
                  SpeechModelFormat.values.byName(formatName),
                  input,
                  partialResults,
                ),
        },
      _ => _process(request),
    };
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
      ('check', .bilingualZipformer || .streamingParaformer || .senseVoice, _) =>
        _checkRecognizer(directory, format),
      ('check', .chineseVits || .kokoroMultiLanguage || .matchaZh, _) =>
        _checkSynthesis(directory, format),
      (
        'synthesize',
        .chineseVits || .kokoroMultiLanguage || .matchaZh,
        {'text': final String text, 'voice': final int voice},
      ) =>
        {
          'wav': base64Encode(
            _synthesize(
              directory,
              format,
              text,
              voice,
              gain: switch (request['gain']) {
                final num v => clampSpeechSynthesisGain(v.toDouble()),
                _ => defaultSpeechSynthesisGain,
              },
              speed: switch (request['speed']) {
                final num v => clampSpeechSynthesisSpeed(v.toDouble()),
                _ => defaultSpeechSynthesisSpeed,
              },
            ),
          ),
        },
      _ => throw const FormatException(),
    };
  }
  throw const FormatException();
}

ResolvedSpeechModel _resolveInDirectory(
  String directory,
  SpeechModelFormat format,
) {
  final root = Directory(directory);
  final relativePaths = <String>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = path.relative(entity.path, from: directory);
    relativePaths.add(path.split(relative).join('/'));
  }
  final resolved = resolveSpeechModelFiles(format, relativePaths);
  if (resolved == null) throw const FormatException();
  return resolved;
}

sherpa.OnlineRecognizer _recognizer(
  String directory,
  SpeechModelFormat format, {
  bool enableEndpoint = false,
  double sendSilenceSeconds = defaultSpeechSendSilenceSeconds,
}) {
  final trailingSilence = clampSpeechSendSilenceSeconds(sendSilenceSeconds);
  final idleSilence = (trailingSilence * 2).clamp(1.5, 15.0);
  final resolved = _resolveInDirectory(directory, format);
  final model = switch (format) {
    .bilingualZipformer => sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: path.join(directory, resolved.encoder!),
        decoder: path.join(directory, resolved.decoder!),
        joiner: path.join(directory, resolved.joiner!),
      ),
      tokens: path.join(directory, resolved.tokens),
      numThreads: 2,
      debug: false,
    ),
    .streamingParaformer => sherpa.OnlineModelConfig(
      paraformer: sherpa.OnlineParaformerModelConfig(
        encoder: path.join(directory, resolved.encoder!),
        decoder: path.join(directory, resolved.decoder!),
      ),
      tokens: path.join(directory, resolved.tokens),
      numThreads: 2,
      debug: false,
    ),
    _ => throw const FormatException(),
  };
  return sherpa.OnlineRecognizer(
    sherpa.OnlineRecognizerConfig(
      model: model,
      enableEndpoint: enableEndpoint,
      rule1MinTrailingSilence: idleSilence,
      rule2MinTrailingSilence: trailingSilence,
      rule3MinUtteranceLength: 25.0,
    ),
  );
}

sherpa.OfflineRecognizer _offlineRecognizer(
  String directory,
  SpeechModelFormat format,
) {
  final resolved = _resolveInDirectory(directory, format);
  final threads = Platform.numberOfProcessors.clamp(2, 4);
  return switch (format) {
    .senseVoice => sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: path.join(directory, resolved.model!),
            language: 'auto',
            useInverseTextNormalization: true,
          ),
          tokens: path.join(directory, resolved.tokens),
          numThreads: threads,
          debug: false,
        ),
      ),
    ),
    _ => throw const FormatException(),
  };
}

Map<String, int> _checkRecognizer(String directory, SpeechModelFormat format) {
  if (format == .senseVoice) {
    final recognizer = _offlineRecognizer(directory, format);
    recognizer.free();
    return {'voices': 0};
  }
  final recognizer = _recognizer(directory, format);
  recognizer.free();
  return {'voices': 0};
}

Future<String> _recognize(
  String directory,
  SpeechModelFormat format,
  StreamIterator<String> input,
  bool partialResults,
) async {
  final recognizer = _recognizer(directory, format);
  try {
    final stream = recognizer.createStream();
    try {
      var rate = 0;
      var frameSize = 0;
      var totalFrames = 0;
      var previous = '';
      while (await input.moveNext()) {
        if (jsonDecode(input.current)
            case {
              'pcm': final String encoded,
              'sampleRate': final int sampleRate,
              'channels': final int channels,
            }
            when sampleRate >= 8000 &&
                sampleRate <= 96000 &&
                channels >= 1 &&
                channels <= 2 &&
                (rate == 0 ||
                    rate == sampleRate && frameSize == channels * 2)) {
          rate = sampleRate;
          frameSize = channels * 2;
          final pcm = base64Decode(encoded);
          totalFrames += pcm.length ~/ frameSize;
          if (pcm.isEmpty ||
              pcm.length % frameSize != 0 ||
              totalFrames > rate * speechMaxRecordingSeconds) {
            throw const FormatException();
          }
          stream.acceptWaveform(
            samples: _pcmSamples(pcm, frameSize),
            sampleRate: rate,
          );
          if (!recognizer.isReady(stream)) continue;
          while (recognizer.isReady(stream)) {
            recognizer.decode(stream);
          }
          if (partialResults) {
            final text = recognizer.getResult(stream).text.trim();
            if (text == previous) continue;
            previous = text;
            stdout.writeln(
              '$speechWorkerResultPrefix${jsonEncode({'partial': text})}',
            );
            await stdout.flush();
          }
        } else {
          throw const FormatException();
        }
      }
      if (totalFrames == 0) return '';
      stream.acceptWaveform(samples: Float32List(rate ~/ 2), sampleRate: rate);
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

Future<void> _recognizeContinuous(
  String directory,
  SpeechModelFormat format,
  StreamIterator<String> input,
  bool partialResults, {
  double silenceSeconds = defaultSpeechSendSilenceSeconds,
}) async {
  final recognizer = _recognizer(
    directory,
    format,
    enableEndpoint: true,
    sendSilenceSeconds: silenceSeconds,
  );
  try {
    final stream = recognizer.createStream();
    try {
      var rate = 0;
      var frameSize = 0;
      var hasAudio = false;
      var previous = '';
      while (await input.moveNext()) {
        if (jsonDecode(input.current)
            case {
              'pcm': final String encoded,
              'sampleRate': final int sampleRate,
              'channels': final int channels,
            }
            when sampleRate >= 8000 &&
                sampleRate <= 96000 &&
                channels >= 1 &&
                channels <= 2 &&
                (rate == 0 ||
                    rate == sampleRate && frameSize == channels * 2)) {
          rate = sampleRate;
          frameSize = channels * 2;
          final pcm = base64Decode(encoded);
          if (pcm.isEmpty || pcm.length % frameSize != 0) {
            throw const FormatException();
          }
          hasAudio = true;
          stream.acceptWaveform(
            samples: _pcmSamples(pcm, frameSize),
            sampleRate: rate,
          );
          while (recognizer.isReady(stream)) {
            recognizer.decode(stream);
          }
          if (recognizer.isEndpoint(stream)) {
            final text = recognizer.getResult(stream).text.trim();
            recognizer.reset(stream);
            previous = '';
            if (text.isNotEmpty) {
              stdout.writeln(
                '$speechWorkerResultPrefix${jsonEncode({'utterance': text})}',
              );
              await stdout.flush();
            }
          } else if (partialResults) {
            final text = recognizer.getResult(stream).text.trim();
            if (text == previous) continue;
            previous = text;
            stdout.writeln(
              '$speechWorkerResultPrefix${jsonEncode({'partial': text})}',
            );
            await stdout.flush();
          }
        } else {
          throw const FormatException();
        }
      }
      if (!hasAudio) return;
      stream.acceptWaveform(samples: Float32List(rate ~/ 2), sampleRate: rate);
      stream.inputFinished();
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final text = recognizer.getResult(stream).text.trim();
      if (text.isNotEmpty) {
        stdout.writeln(
          '$speechWorkerResultPrefix${jsonEncode({'utterance': text})}',
        );
        await stdout.flush();
      }
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}

Future<String> _recognizeOffline(
  String directory,
  SpeechModelFormat format,
  StreamIterator<String> input,
) async {
  final recognizer = _offlineRecognizer(directory, format);
  try {
    var rate = 0;
    var frameSize = 0;
    final chunks = <Float32List>[];
    var totalSamples = 0;
    while (await input.moveNext()) {
      if (jsonDecode(input.current)
          case {
            'pcm': final String encoded,
            'sampleRate': final int sampleRate,
            'channels': final int channels,
          }
          when sampleRate >= 8000 &&
              sampleRate <= 96000 &&
              channels >= 1 &&
              channels <= 2 &&
              (rate == 0 ||
                  rate == sampleRate && frameSize == channels * 2)) {
        rate = sampleRate;
        frameSize = channels * 2;
        final pcm = base64Decode(encoded);
        if (pcm.isEmpty || pcm.length % frameSize != 0) {
          throw const FormatException();
        }
        final samples = _pcmSamples(pcm, frameSize);
        chunks.add(samples);
        totalSamples += samples.length;
      } else {
        throw const FormatException();
      }
    }
    if (totalSamples == 0) return '';
    final combined = Float32List(totalSamples);
    var offset = 0;
    for (final chunk in chunks) {
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return _decodeOfflineSegment(recognizer, combined, rate);
  } finally {
    recognizer.free();
  }
}

Future<void> _recognizeContinuousOffline(
  String directory,
  SpeechModelFormat format,
  StreamIterator<String> input, {
  double silenceSeconds = defaultSpeechSendSilenceSeconds,
}) async {
  final recognizer = _offlineRecognizer(directory, format);
  final trailingSilence = clampSpeechSendSilenceSeconds(silenceSeconds);
  try {
    var rate = 0;
    var frameSize = 0;
    final buffer = <Float32List>[];
    var bufferedSamples = 0;
    var speechSamples = 0;
    var silenceSamples = 0;
    var hasSpeech = false;

    Future<void> flush() async {
      if (!hasSpeech || bufferedSamples == 0) {
        buffer.clear();
        bufferedSamples = 0;
        speechSamples = 0;
        silenceSamples = 0;
        hasSpeech = false;
        return;
      }
      final combined = Float32List(bufferedSamples);
      var offset = 0;
      for (final chunk in buffer) {
        combined.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      buffer.clear();
      bufferedSamples = 0;
      speechSamples = 0;
      silenceSamples = 0;
      hasSpeech = false;
      final text = _decodeOfflineSegment(recognizer, combined, rate);
      if (text.isNotEmpty) {
        stdout.writeln(
          '$speechWorkerResultPrefix${jsonEncode({'utterance': text})}',
        );
        await stdout.flush();
      }
    }

    while (await input.moveNext()) {
      if (jsonDecode(input.current)
          case {
            'pcm': final String encoded,
            'sampleRate': final int sampleRate,
            'channels': final int channels,
          }
          when sampleRate >= 8000 &&
              sampleRate <= 96000 &&
              channels >= 1 &&
              channels <= 2 &&
              (rate == 0 ||
                  rate == sampleRate && frameSize == channels * 2)) {
        rate = sampleRate;
        frameSize = channels * 2;
        final pcm = base64Decode(encoded);
        if (pcm.isEmpty || pcm.length % frameSize != 0) {
          throw const FormatException();
        }
        final samples = _pcmSamples(pcm, frameSize);
        var sumSq = 0.0;
        for (var i = 0; i < samples.length; i++) {
          sumSq += samples[i] * samples[i];
        }
        final rms = math.sqrt(sumSq / samples.length);
        if (rms >= 0.012) {
          hasSpeech = true;
          silenceSamples = 0;
          speechSamples += samples.length;
          buffer.add(samples);
          bufferedSamples += samples.length;
        } else if (hasSpeech) {
          silenceSamples += samples.length;
          buffer.add(samples);
          bufferedSamples += samples.length;
          if (silenceSamples >= (rate * trailingSilence).round() ||
              bufferedSamples >= rate * 25) {
            await flush();
          }
        } else {
          // 保留最近 0.25 秒前置音频，避免吞掉首字。
          buffer.add(samples);
          bufferedSamples += samples.length;
          while (buffer.length > 1 && bufferedSamples > rate ~/ 4) {
            bufferedSamples -= buffer.removeAt(0).length;
          }
        }
        if (speechSamples >= rate * 25) {
          await flush();
        }
      } else {
        throw const FormatException();
      }
    }
    await flush();
  } finally {
    recognizer.free();
  }
}

String _decodeOfflineSegment(
  sherpa.OfflineRecognizer recognizer,
  Float32List samples,
  int sampleRate,
) {
  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    recognizer.decode(stream);
    return recognizer.getResult(stream).text.trim();
  } finally {
    stream.free();
  }
}

Float32List _pcmSamples(Uint8List pcm, int frameSize) {
  final input = ByteData.sublistView(pcm);
  final samples = Float32List(pcm.length ~/ frameSize);
  for (var index = 0; index < samples.length; index++) {
    final offset = index * frameSize;
    final first = input.getInt16(offset, Endian.little);
    samples[index] = frameSize == 2
        ? first / 32768
        : (first + input.getInt16(offset + 2, Endian.little)) / 65536;
  }
  return samples;
}

sherpa.OfflineTts _synthesizer(String directory, SpeechModelFormat format) {
  String modelFile(String name) => path.join(directory, name);
  final resolved = _resolveInDirectory(directory, format);
  final threads = Platform.numberOfProcessors.clamp(2, 6);
  final model = switch (format) {
    .chineseVits => sherpa.OfflineTtsModelConfig(
      vits: sherpa.OfflineTtsVitsModelConfig(
        model: modelFile(resolved.model!),
        lexicon: resolved.lexicons.isNotEmpty
            ? modelFile(resolved.lexicons.first)
            : '',
        tokens: modelFile(resolved.tokens),
        dictDir: resolved.dictDir != null ? modelFile(resolved.dictDir!) : '',
      ),
      numThreads: threads,
      debug: false,
    ),
    .kokoroMultiLanguage => sherpa.OfflineTtsModelConfig(
      kokoro: sherpa.OfflineTtsKokoroModelConfig(
        model: modelFile(resolved.model!),
        voices: modelFile(resolved.voices!),
        tokens: modelFile(resolved.tokens),
        dataDir: resolved.dataDir != null ? modelFile(resolved.dataDir!) : '',
        lexicon: resolved.lexicons.map(modelFile).join(','),
      ),
      numThreads: threads,
      debug: false,
    ),
    .matchaZh => sherpa.OfflineTtsModelConfig(
      matcha: sherpa.OfflineTtsMatchaModelConfig(
        acousticModel: modelFile(resolved.model!),
        vocoder: modelFile(resolved.vocoder!),
        lexicon: resolved.lexicons.map(modelFile).join(','),
        tokens: modelFile(resolved.tokens),
        dictDir: resolved.dictDir != null ? modelFile(resolved.dictDir!) : '',
      ),
      numThreads: threads,
      debug: false,
    ),
    .bilingualZipformer || .streamingParaformer || .senseVoice =>
      throw const FormatException(),
  };
  return sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      model: model,
      ruleFsts: resolved.ruleFsts.map(modelFile).join(','),
    ),
  );
}

Map<String, int> _checkSynthesis(String directory, SpeechModelFormat format) {
  final tts = _synthesizer(directory, format);
  try {
    final text = format == .kokoroMultiLanguage ? 'Hello，世界。' : '你好。';
    final preview = tts.generate(text: text, sid: 0);
    if (preview.samples.isEmpty || preview.sampleRate <= 0) {
      throw const FormatException();
    }
    return {'voices': tts.numSpeakers};
  } finally {
    tts.free();
  }
}

Uint8List _synthesize(
  String directory,
  SpeechModelFormat format,
  String text,
  int voice, {
  double gain = defaultSpeechSynthesisGain,
  double speed = defaultSpeechSynthesisSpeed,
}) {
  if (text.trim().isEmpty) throw const FormatException();
  final tts = _synthesizer(directory, format);
  try {
    if (voice < 0 || voice >= tts.numSpeakers) throw const FormatException();
    final clampedSpeed = clampSpeechSynthesisSpeed(speed);
    final pcm = BytesBuilder(copy: false);
    var sampleRate = 0;
    for (final chunk in _utterances(text)) {
      final audio = tts.generate(text: chunk, sid: voice, speed: clampedSpeed);
      if (audio.samples.isEmpty) continue;
      if (audio.sampleRate <= 0 ||
          (sampleRate != 0 && sampleRate != audio.sampleRate)) {
        throw const FormatException();
      }
      sampleRate = audio.sampleRate;
      pcm.add(_pcmBytes(audio.samples, gain: gain));
    }
    if (pcm.isEmpty) throw const FormatException();
    return _encodeWav(pcm.takeBytes(), sampleRate);
  } finally {
    tts.free();
  }
}

Future<void> _runSynthesisSession(StreamIterator<String> input) async {
  sherpa.OfflineTts? cachedTts;
  String? cachedDirectory;
  SpeechModelFormat? cachedFormat;
  try {
    while (await input.moveNext()) {
      final line = input.current.trim();
      if (line.isEmpty) continue;
      final message = jsonDecode(line);
      if (message case {'operation': 'close'}) break;
      if (message case {
        'id': final int id,
        'operation': 'warm',
        'format': final String formatName,
        'directory': final String directory,
      }) {
        try {
          final format = SpeechModelFormat.values.byName(formatName);
          if (format == .bilingualZipformer) throw const FormatException();
          if (cachedTts == null ||
              cachedDirectory != directory ||
              cachedFormat != format) {
            cachedTts?.free();
            cachedTts = _synthesizer(directory, format);
            cachedDirectory = directory;
            cachedFormat = format;
          }
          stdout.writeln(
            '$speechWorkerResultPrefix${jsonEncode({'id': id, 'done': true})}',
          );
          await stdout.flush();
        } catch (_) {
          stdout.writeln(
            '$speechWorkerResultPrefix${jsonEncode({'id': id, 'error': 'engine'})}',
          );
          await stdout.flush();
        }
        continue;
      }
      if (message case {
        'id': final int id,
        'format': final String formatName,
        'directory': final String directory,
        'text': final String text,
        'voice': final int voice,
      }) {
        try {
          if (text.trim().isEmpty) throw const FormatException();
          final format = SpeechModelFormat.values.byName(formatName);
          if (format == .bilingualZipformer) throw const FormatException();
          if (cachedTts == null ||
              cachedDirectory != directory ||
              cachedFormat != format) {
            cachedTts?.free();
            cachedTts = _synthesizer(directory, format);
            cachedDirectory = directory;
            cachedFormat = format;
          }
          if (voice < 0 || voice >= cachedTts.numSpeakers) {
            throw const FormatException();
          }
          final gain = switch (message['gain']) {
            final num v => clampSpeechSynthesisGain(v.toDouble()),
            _ => defaultSpeechSynthesisGain,
          };
          final speed = switch (message['speed']) {
            final num v => clampSpeechSynthesisSpeed(v.toDouble()),
            _ => defaultSpeechSynthesisSpeed,
          };
          var emitted = false;
          for (final chunk in _utterances(text)) {
            final audio = cachedTts.generate(
              text: chunk,
              sid: voice,
              speed: speed,
            );
            if (audio.samples.isEmpty) continue;
            if (audio.sampleRate <= 0) throw const FormatException();
            final wav = _encodeWav(
              _pcmBytes(audio.samples, gain: gain),
              audio.sampleRate,
            );
            emitted = true;
            stdout.writeln(
              '$speechWorkerResultPrefix${jsonEncode({'id': id, 'chunk': base64Encode(wav)})}',
            );
            await stdout.flush();
          }
          if (!emitted) throw const FormatException();
          stdout.writeln(
            '$speechWorkerResultPrefix${jsonEncode({'id': id, 'done': true})}',
          );
          await stdout.flush();
        } catch (_) {
          stdout.writeln(
            '$speechWorkerResultPrefix${jsonEncode({'id': id, 'error': 'engine'})}',
          );
          await stdout.flush();
        }
      } else {
        throw const FormatException();
      }
    }
  } finally {
    cachedTts?.free();
  }
}

Uint8List _pcmBytes(
  Float32List samples, {
  double gain = defaultSpeechSynthesisGain,
}) {
  final clampedGain = clampSpeechSynthesisGain(gain);
  final bytes = ByteData(samples.length * 2);
  for (final (index, sample) in samples.indexed) {
    final value = sample.isFinite
        ? (sample * clampedGain).clamp(-1.0, 1.0)
        : 0.0;
    bytes.setInt16(index * 2, (value * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Uint8List _encodeWav(Uint8List pcm, int sampleRate) {
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
        ..add(pcm))
      .takeBytes();
}

Iterable<String> _utterances(String text) sync* {
  final buffer = StringBuffer();
  const sentenceEnd = {0x3002, 0xff01, 0xff1f, 0x0a, 0x21, 0x3f, 0x2e};
  const clauseBreak = {0x2c, 0xff0c, 0x3b, 0xff1b};
  var first = true;
  for (final rune in text.runes) {
    buffer.writeCharCode(rune);
    final minSentence = first ? 2 : 24;
    final maxChunk = first ? 80 : 240;
    final split =
        buffer.length >= maxChunk ||
        (buffer.length >= minSentence && sentenceEnd.contains(rune)) ||
        (first && buffer.length >= 12 && clauseBreak.contains(rune));
    if (split) {
      final sentence = buffer.toString().trim();
      if (sentence.isNotEmpty) {
        yield sentence;
        first = false;
      }
      buffer.clear();
    }
  }
  final sentence = buffer.toString().trim();
  if (sentence.isNotEmpty) yield sentence;
}
