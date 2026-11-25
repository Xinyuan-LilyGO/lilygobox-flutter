/*
 * @Description: 管理本机语音库及独占录音和播放任务。
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/files/package_transfer.dart';
import '../data/speech_audio_input.dart';
import '../data/speech_audio_output.dart';
import '../data/speech_engine.dart';
import '../data/speech_model_store.dart';
import '../domain/speech_model.dart';

class SpeechProvider extends ChangeNotifier {
  SpeechProvider({
    required this._store,
    required this._engine,
    required this._output,
    this._input = const WindowsSpeechAudioInput(),
  });

  final SpeechModelStore _store;
  final SpeechEngine _engine;
  final SpeechAudioOutput _output;
  final SpeechAudioInput _input;

  SpeechLibrary _library = SpeechLibrary();
  SpeechLibrary get library => _library;

  bool _busy = false;
  bool _loaded = false;
  bool _disposed = false;
  bool get busy => _busy;
  bool get loaded => _loaded;

  _SpeechPlayback? _playback;
  _SpeechCapture? _capture;
  bool get hasCapture => _capture != null;

  SpeechCapturePhase? capturePhase(SpeechConversation owner) {
    final capture = _capture;
    return capture != null &&
            capture.owner == owner &&
            !capture.cancellation.isCompleted
        ? capture.phase
        : null;
  }

  bool isPlaying(Object owner) =>
      _playback?.owner == owner && !_playback!.cancellation.isCompleted;

  Future<void> load() async {
    _loaded = await _change(_store.read) == null;
    _notify();
  }

  Future<SpeechFailureReason?> import(
    String packagePath, {
    PackageTransfer? transfer,
  }) => _change(
    () => _store.import(
      library,
      packagePath,
      transfer: transfer,
      check: (format, directory) => _engine.check(
        format,
        directory,
        cancellation: transfer?.cancellation,
      ),
    ),
  );

  Future<int?> readStorageBytes() => _store.readStorageBytes();

  Future<SpeechFailureReason?> export(
    List<SpeechModel> models,
    String outputPath, {
    PackageTransfer? transfer,
  }) => _change(() async {
    await _store.export(models, outputPath, transfer: transfer);
    return library;
  }, unexpectedError: .exportFailed);

  Future<SpeechFailureReason?> deleteModels(Set<String> ids) =>
      _change(() async {
        final capture = _capture;
        if (capture != null && ids.contains(capture.modelId)) {
          capture.cancel();
          await capture.finished.future;
        }
        final playback = _playback;
        if (playback != null && ids.contains(playback.modelId)) {
          playback.cancel();
          await playback.finished.future;
        }
        return _store.deleteModels(library, ids);
      });

  Future<SpeechFailureReason?> play(
    Object owner,
    String text, {
    SpeechVoiceSelection? selection,
  }) async {
    if (_disposed || _busy || hasCapture) return null;
    final selected = library.synthesisModel(selection);
    if (selected == null) return .missingFiles;
    final voice = selection?.voice ?? 0;
    final previous = _playback;
    previous?.cancel();
    final task = _SpeechPlayback(owner, selected.id);
    _playback = task;
    _notify();
    try {
      await previous?.finished.future;
      if (task.cancellation.isCompleted) return null;
      final directory = await _store.directoryFor(selected);
      if (task.cancellation.isCompleted) return null;
      final wav = await _engine.synthesize(
        selected.format,
        directory,
        text,
        voice,
        cancellation: task.cancellation.future,
      );
      if (task.cancellation.isCompleted) return null;
      await _output.play(wav, task.cancellation.future);
      return null;
    } on SpeechFailure catch (error) {
      return task.cancellation.isCompleted ? null : error.reason;
    } catch (_) {
      return task.cancellation.isCompleted ? null : .playback;
    } finally {
      task.cancel();
      task.finished.complete();
      if (identical(task, _playback)) {
        _playback = null;
        _notify();
      }
    }
  }

  void stopPlayback(Object owner) {
    if (!isPlaying(owner)) return;
    _playback!.cancel();
    _notify();
  }

  void stopConversation(SpeechConversation owner, {SpeechModelKind? kind}) {
    var changed = false;
    final playback = _playback;
    if (playback?.owner case (final SpeechConversation scope, String _)
        when scope == owner && kind != .recognition) {
      playback!.cancel();
      changed = true;
    }
    final capture = _capture;
    if (capture != null && capture.owner == owner && kind != .synthesis) {
      capture.cancel();
      changed = true;
    }
    if (changed) _notify();
  }

  Future<({String? text, SpeechFailureReason? error})> startRecording(
    SpeechConversation owner, {
    required String? modelId,
    void Function(String)? onPartial,
  }) async {
    if (_disposed || _busy || hasCapture) return (text: null, error: null);
    final selected = library.recognitionModel(modelId);
    if (selected == null) {
      return (text: null, error: SpeechFailureReason.missingFiles);
    }
    final task = _SpeechCapture(owner, selected.id);
    _capture = task;
    final playback = _playback;
    playback?.cancel();
    _notify();
    try {
      await playback?.finished.future;
      final directory = await _store.directoryFor(selected);
      if (task.cancellation.isCompleted) return (text: null, error: null);
      final audio = StreamController<SpeechAudioChunk>();
      final abortRecognition = Completer<void>();
      Future<void> record() async {
        try {
          await _input.record(
            stop: task.stop.future,
            started: () {
              if (task.cancellation.isCompleted) return;
              task.phase = .recording;
              _notify();
            },
            onAudio: (chunk) {
              if (!task.cancellation.isCompleted) audio.add(chunk);
            },
          );
          if (!task.cancellation.isCompleted && task.phase != .transcribing) {
            task.phase = .transcribing;
            _notify();
          }
        } on SpeechFailure {
          rethrow;
        } catch (_) {
          throw const SpeechFailure(.microphone);
        } finally {
          unawaited(audio.close());
        }
      }

      final recording = record();
      final recognition = _engine.recognize(
        directory,
        audio.stream,
        cancellation: Future.any<void>([
          task.cancellation.future,
          abortRecognition.future,
        ]),
        onPartial: onPartial == null
            ? null
            : (text) {
                if (!task.cancellation.isCompleted &&
                    task.phase == .recording) {
                  onPartial(text);
                }
              },
      );
      final String text;
      try {
        final results = await Future.wait<Object?>([
          recording,
          recognition,
        ], eagerError: true);
        text = (results[1] as String).trim();
      } catch (_) {
        if (!task.stop.isCompleted) task.stop.complete(false);
        abortRecognition.complete();
        await Future.wait<void>([
          recording.then<void>((_) {}, onError: (Object _) {}),
          recognition.then<void>((_) {}, onError: (Object _) {}),
        ]);
        rethrow;
      }
      if (task.cancellation.isCompleted) return (text: null, error: null);
      return text.isEmpty
          ? (text: null, error: SpeechFailureReason.noSpeech)
          : (text: text, error: null);
    } on SpeechFailure catch (error) {
      return (
        text: null,
        error: task.cancellation.isCompleted ? null : error.reason,
      );
    } catch (_) {
      return (
        text: null,
        error: task.cancellation.isCompleted
            ? null
            : SpeechFailureReason.engine,
      );
    } finally {
      task.cancel();
      task.finished.complete();
      _capture = null;
      _notify();
    }
  }

  void finishRecording(SpeechConversation owner) {
    final capture = _capture;
    if (capture == null ||
        capturePhase(owner) != .recording ||
        capture.stop.isCompleted) {
      return;
    }
    capture.phase = .transcribing;
    capture.stop.complete(true);
    _notify();
  }

  Future<SpeechFailureReason?> _change(
    Future<SpeechLibrary> Function() action, {
    SpeechFailureReason unexpectedError = .storage,
  }) async {
    if (_busy || _disposed) return null;
    _busy = true;
    _notify();
    try {
      _library = await action();
      return null;
    } on PackageCancelled {
      rethrow;
    } on SpeechFailure catch (error) {
      return error.reason;
    } catch (_) {
      return unexpectedError;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _playback?.cancel();
    _capture?.cancel();
    super.dispose();
  }
}

class SpeechConversation {}

class _SpeechCapture {
  _SpeechCapture(this.owner, this.modelId);

  final SpeechConversation owner;
  final String modelId;
  final stop = Completer<bool>();
  final cancellation = Completer<void>();
  final finished = Completer<void>();
  SpeechCapturePhase phase = .starting;

  void cancel() {
    if (!stop.isCompleted) stop.complete(false);
    if (!cancellation.isCompleted) cancellation.complete();
  }
}

class _SpeechPlayback {
  _SpeechPlayback(this.owner, this.modelId);

  final Object owner;
  final String modelId;
  final cancellation = Completer<void>();
  final finished = Completer<void>();

  void cancel() {
    if (!cancellation.isCompleted) cancellation.complete();
  }
}
