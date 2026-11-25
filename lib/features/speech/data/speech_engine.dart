/*
 * @Description: 通过独立进程校验语音模型并运行离线推理。
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../domain/speech_model.dart';

const speechWorkerArgument = '--lilygobox-speech-worker';
const speechWorkerResultPrefix = 'LILYGOBOX_SPEECH:';
const speechSampleRate = 16000;
const speechMaxRecordingSeconds = 90;

typedef SpeechAudioChunk = ({Uint8List pcm, int sampleRate, int channels});

class SpeechEngine {
  const SpeechEngine();

  Future<int> check(
    SpeechModelFormat format,
    Directory directory, {
    Future<void>? cancellation,
  }) async {
    final result = await _invoke(
      format,
      directory,
      'check',
      const {},
      cancellation: cancellation,
    );
    if (result case {'voices': final int voices}) return voices;
    throw const SpeechFailure(.invalidModel);
  }

  Future<String> recognize(
    Directory directory,
    Stream<SpeechAudioChunk> audio, {
    void Function(String)? onPartial,
    required Future<void> cancellation,
  }) async {
    final result = await _invoke(
      .bilingualZipformer,
      directory,
      'recognize',
      const {},
      audio: audio,
      onPartial: onPartial,
      cancellation: cancellation,
    );
    if (result case {'text': final String text}) return text;
    throw const SpeechFailure(.engine);
  }

  Future<Uint8List> synthesize(
    SpeechModelFormat format,
    Directory directory,
    String text,
    int voice, {
    Future<void>? cancellation,
  }) async {
    final result = await _invoke(format, directory, 'synthesize', {
      'text': text,
      'voice': voice,
    }, cancellation: cancellation);
    if (result case {'wav': final String wav}) return base64Decode(wav);
    throw const SpeechFailure(.engine);
  }

  Future<Object?> _invoke(
    SpeechModelFormat format,
    Directory directory,
    String operation,
    Map<String, Object?> arguments, {
    Future<void>? cancellation,
    Stream<SpeechAudioChunk>? audio,
    void Function(String)? onPartial,
  }) async {
    final executable = Platform.resolvedExecutable;
    final executableDirectory = path.dirname(executable);
    if (!Platform.isWindows ||
        !await File(path.join(executableDirectory, 'sherpa-onnx-c-api.dll'))
            .exists() ||
        !await File(path.join(executableDirectory, 'onnxruntime.dll'))
            .exists()) {
      throw const SpeechFailure(.engine);
    }
    final process = await Process.start(executable, [
      speechWorkerArgument,
    ], workingDirectory: executableDirectory);
    unawaited(cancellation?.then<void>((_) => process.kill()));
    process.stdin.encoding = utf8;
    final response = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .where((line) => line.startsWith(speechWorkerResultPrefix))
        .map(
          (line) => jsonDecode(line.substring(speechWorkerResultPrefix.length)),
        )
        .fold<Object?>(null, (previous, result) {
          if (result case {'partial': final String text}) {
            onPartial?.call(text);
            return previous;
          }
          return previous ?? result;
        });
    final errors = process.stderr.drain<void>();
    final status = process.exitCode;
    Future<void> send() async {
      process.stdin.writeln(
        jsonEncode({
          'operation': operation,
          'format': format.name,
          'directory': directory.absolute.path,
          'partialResults': onPartial != null,
          ...arguments,
        }),
      );
      if (audio != null) {
        await process.stdin.addStream(
          audio.map(
            (chunk) => utf8.encode(
              '${jsonEncode({'pcm': base64Encode(chunk.pcm), 'sampleRate': chunk.sampleRate, 'channels': chunk.channels})}\n',
            ),
          ),
        );
      }
      await process.stdin.close();
    }

    try {
      final results = await Future.wait<Object?>([
        status.then((code) {
          if (code == 0) return;
          throw SpeechFailure(
            operation == 'check' && code != 78 ? .invalidModel : .engine,
          );
        }),
        response,
        errors,
        send(),
      ], eagerError: true).timeout(const Duration(minutes: 2));
      return results[1];
    } on TimeoutException {
      throw const SpeechFailure(.engine);
    } finally {
      process.kill();
      await status;
    }
  }
}
