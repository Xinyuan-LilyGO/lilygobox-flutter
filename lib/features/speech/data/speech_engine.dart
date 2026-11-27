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
    SpeechModelFormat format,
    Directory directory,
    Stream<SpeechAudioChunk> audio, {
    void Function(String)? onPartial,
    required Future<void> cancellation,
  }) async {
    final result = await _invoke(
      format,
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

  Future<void> recognizeContinuous(
    SpeechModelFormat format,
    Directory directory,
    Stream<SpeechAudioChunk> audio, {
    double silenceSeconds = defaultSpeechSendSilenceSeconds,
    void Function(String)? onPartial,
    required void Function(String) onUtterance,
    required Future<void> cancellation,
  }) => _invoke(
    format,
    directory,
    'recognize-continuous',
    {'silenceSeconds': silenceSeconds},
    audio: audio,
    onPartial: onPartial,
    onUtterance: onUtterance,
    cancellation: cancellation,
    timeout: null,
  );

  Future<Uint8List> synthesize(
    SpeechModelFormat format,
    Directory directory,
    String text,
    int voice, {
    double gain = defaultSpeechSynthesisGain,
    double speed = defaultSpeechSynthesisSpeed,
    Future<void>? cancellation,
  }) async {
    final result = await _invoke(format, directory, 'synthesize', {
      'text': text,
      'voice': voice,
      'gain': gain,
      'speed': speed,
    }, cancellation: cancellation);
    if (result case {'wav': final String wav}) return base64Decode(wav);
    throw const SpeechFailure(.engine);
  }

  Stream<Uint8List> synthesizeStream(
    SpeechModelFormat format,
    Directory directory,
    String text,
    int voice, {
    double gain = defaultSpeechSynthesisGain,
    double speed = defaultSpeechSynthesisSpeed,
    Future<void>? cancellation,
  }) async* {
    var emitted = false;
    try {
      await for (final chunk in _ResidentSynthesisSession.shared
          .synthesizeStream(
            format,
            directory,
            text,
            voice,
            gain: gain,
            speed: speed,
            cancellation: cancellation,
          )) {
        emitted = true;
        yield chunk;
      }
    } on SpeechFailure {
      if (emitted) rethrow;
      yield await synthesize(
        format,
        directory,
        text,
        voice,
        gain: gain,
        speed: speed,
        cancellation: cancellation,
      );
    }
  }

  Future<void> warmUpSynthesis(
    SpeechModelFormat format,
    Directory directory,
  ) => _ResidentSynthesisSession.shared.warmUp(format, directory);

  void disposeSynthesisSession() => _ResidentSynthesisSession.shared.dispose();

  Future<Object?> _invoke(
    SpeechModelFormat format,
    Directory directory,
    String operation,
    Map<String, Object?> arguments, {
    Future<void>? cancellation,
    Stream<SpeechAudioChunk>? audio,
    void Function(String)? onPartial,
    void Function(String)? onUtterance,
    Duration? timeout = const Duration(minutes: 2),
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
          if (result case {'utterance': final String text}) {
            onUtterance?.call(text);
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
      final pending = Future.wait<Object?>([
        status.then((code) {
          if (code == 0) return;
          throw SpeechFailure(
            operation == 'check' && code != 78 ? .invalidModel : .engine,
          );
        }),
        response,
        errors,
        send(),
      ], eagerError: true);
      final results = timeout == null
          ? await pending
          : await pending.timeout(timeout);
      return results[1];
    } on TimeoutException {
      throw const SpeechFailure(.engine);
    } finally {
      process.kill();
      await status;
    }
  }
}

class _ResidentSynthesisSession {
  static final shared = _ResidentSynthesisSession();
  static const _idleTimeout = Duration(minutes: 10);

  Process? _process;
  int _nextId = 1;
  int? _activeId;
  StreamController<Uint8List>? _activeController;
  String? _warmedModelKey;
  Future<void>? _warming;
  Timer? _idleTimer;

  Future<void> warmUp(SpeechModelFormat format, Directory directory) {
    final key = '${format.name}|${directory.absolute.path}';
    if (_process != null && _warmedModelKey == key) return Future.value();
    if (_warming case final pending?) return pending;
    if (_activeController != null) return Future.value();
    final task = _doWarmUp(format, directory, key);
    _warming = task;
    return task.whenComplete(() {
      if (identical(_warming, task)) _warming = null;
    });
  }

  Future<void> _doWarmUp(
    SpeechModelFormat format,
    Directory directory,
    String key,
  ) async {
    _idleTimer?.cancel();
    try {
      final process = await _ensureProcess();
      if (_activeController != null) return;
      final id = _nextId++;
      final controller = StreamController<Uint8List>();
      _activeId = id;
      _activeController = controller;
      process.stdin.writeln(
        jsonEncode({
          'id': id,
          'operation': 'warm',
          'format': format.name,
          'directory': directory.absolute.path,
        }),
      );
      await process.stdin.flush();
      await controller.stream.drain<void>();
      _warmedModelKey = key;
    } catch (_) {
      // 预热失败不阻塞后续正常按需合成。
    }
  }

  Stream<Uint8List> synthesizeStream(
    SpeechModelFormat format,
    Directory directory,
    String text,
    int voice, {
    double gain = defaultSpeechSynthesisGain,
    double speed = defaultSpeechSynthesisSpeed,
    Future<void>? cancellation,
  }) {
    final controller = StreamController<Uint8List>();
    unawaited(
      _run(
        controller,
        format,
        directory,
        text,
        voice,
        gain: gain,
        speed: speed,
        cancellation: cancellation,
      ),
    );
    return controller.stream;
  }

  Future<void> _run(
    StreamController<Uint8List> controller,
    SpeechModelFormat format,
    Directory directory,
    String text,
    int voice, {
    double gain = defaultSpeechSynthesisGain,
    double speed = defaultSpeechSynthesisSpeed,
    Future<void>? cancellation,
  }) async {
    _idleTimer?.cancel();
    var cancelled = false;
    unawaited(
      cancellation?.then<void>((_) {
        cancelled = true;
        if (_activeController == controller) {
          // 合成尚未完成时终止常驻子进程，立即释放 CPU 计算。
          dispose();
        }
        if (!controller.isClosed) unawaited(controller.close());
      }),
    );
    try {
      await _warming;
      if (cancelled) return;
      final process = await _ensureProcess();
      if (cancelled) return;
      final id = _nextId++;
      _activeId = id;
      _activeController = controller;
      process.stdin.writeln(
        jsonEncode({
          'id': id,
          'format': format.name,
          'directory': directory.absolute.path,
          'text': text,
          'voice': voice,
          'gain': gain,
          'speed': speed,
        }),
      );
      await process.stdin.flush();
    } catch (error, stack) {
      if (!cancelled && !controller.isClosed) {
        controller.addError(
          error is SpeechFailure ? error : const SpeechFailure(.engine),
          stack,
        );
        await controller.close();
      }
      dispose();
    }
  }

  Future<Process> _ensureProcess() async {
    if (_process case final existing?) return existing;
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
    _process = process;
    process.stdin.encoding = utf8;
    unawaited(process.stderr.drain<void>());
    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .where((line) => line.startsWith(speechWorkerResultPrefix))
        .listen(
          (line) {
            final payload = jsonDecode(
              line.substring(speechWorkerResultPrefix.length),
            );
            if (payload case {'id': final int id} when id == _activeId) {
              final controller = _activeController;
              if (controller == null || controller.isClosed) return;
              if (payload case {'chunk': final String encoded}) {
                controller.add(base64Decode(encoded));
              } else if (payload case {'done': true}) {
                _finishActive(controller);
              } else if (payload case {'error': _}) {
                controller.addError(const SpeechFailure(.engine));
                _finishActive(controller);
              }
            }
          },
          onDone: () {
            if (identical(_process, process)) {
              _process = null;
            }
            final controller = _activeController;
            if (controller != null && !controller.isClosed) {
              controller.addError(const SpeechFailure(.engine));
              _finishActive(controller);
            }
          },
        );
    process.stdin.writeln(jsonEncode({'operation': 'synthesize-session'}));
    await process.stdin.flush();
    return process;
  }

  void _finishActive(StreamController<Uint8List> controller) {
    if (_activeController == controller) {
      _activeController = null;
      _activeId = null;
    }
    if (!controller.isClosed) unawaited(controller.close());
    _scheduleIdleDispose();
  }

  void _scheduleIdleDispose() {
    _idleTimer?.cancel();
    if (_process != null) {
      _idleTimer = Timer(_idleTimeout, dispose);
    }
  }

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    final controller = _activeController;
    _activeController = null;
    _activeId = null;
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
    final process = _process;
    _process = null;
    _warmedModelKey = null;
    process?.kill();
  }
}
