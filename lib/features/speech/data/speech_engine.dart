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

class SpeechEngine {
  const SpeechEngine();

  Future<int> check(SpeechModelFormat format, Directory directory) async {
    final result = await _invoke(format, directory, 'check', const {});
    if (result case {'voices': final int voices}) return voices;
    throw const SpeechFailure(.invalidModel);
  }

  Future<String> recognize(
    Directory directory,
    Uint8List pcm, {
    int sampleRate = speechSampleRate,
    int channels = 1,
    Future<void>? cancellation,
  }) async {
    final result = await _invoke(.bilingualZipformer, directory, 'recognize', {
      'pcm': base64Encode(pcm),
      'sampleRate': sampleRate,
      'channels': channels,
    }, cancellation: cancellation);
    if (result case {'text': final String text}) return text;
    throw const SpeechFailure(.engine);
  }

  Future<Uint8List> synthesize(
    Directory directory,
    String text,
    int voice, {
    Future<void>? cancellation,
  }) async {
    final result = await _invoke(.chineseVits, directory, 'synthesize', {
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
    final response = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .where((line) => line.startsWith(speechWorkerResultPrefix))
        .map((line) => line.substring(speechWorkerResultPrefix.length))
        .fold<String?>(null, (previous, line) => previous ?? line);
    final errors = process.stderr.drain<void>();
    final status = process.exitCode;
    try {
      process.stdin.add(
        utf8.encode(
          jsonEncode({
            'operation': operation,
            'format': format.name,
            'directory': directory.absolute.path,
            ...arguments,
          }),
        ),
      );
      final results = await Future.wait<Object?>([
        status,
        response,
        errors,
        process.stdin.close(),
      ], eagerError: true).timeout(const Duration(minutes: 2));
      if (results case [0, final String text, ...]) {
        return jsonDecode(text);
      }
      if (results[0] == 78) throw const SpeechFailure(.engine);
      throw SpeechFailure(operation == 'check' ? .invalidModel : .engine);
    } on TimeoutException {
      throw const SpeechFailure(.engine);
    } finally {
      process.kill();
      await status;
    }
  }
}
