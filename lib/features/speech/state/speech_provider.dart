/*
 * @Description: 管理本机语音库、默认音色和独占播放任务。
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/speech_audio_input.dart';
import '../data/speech_audio_output.dart';
import '../data/speech_engine.dart';
import '../data/speech_model_package.dart';
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

  Future<SpeechFailureReason?> import(String packagePath) =>
      _change(() => _store.import(library, packagePath, check: _engine.check));

  String exportFileName(SpeechModel model) =>
      SpeechModelPackage.fileName(model.name);

  Future<SpeechFailureReason?> export(SpeechModel model, String outputPath) =>
      _change(() async {
        await _store.export(model, outputPath);
        return library;
      }, unexpectedError: .exportFailed);

  Future<SpeechFailureReason?> select(SpeechModel model) =>
      _change(() => _store.select(library, model));

  Future<SpeechFailureReason?> selectVoice(int voice) =>
      _change(() => _store.selectVoice(library, voice));

  Future<SpeechFailureReason?> delete(SpeechModel model) => _change(() async {
    final capture = _capture;
    if (capture != null && capture.modelId == model.id) {
      capture.cancel();
      await capture.finished.future;
    }
    final playback = _playback;
    if (playback?.modelId == model.id) {
      playback!.cancel();
      await playback.finished.future;
    }
    return _store.delete(library, model);
  });

  Future<SpeechFailureReason?> play(
    Object owner,
    String text, {
    SpeechModel? model,
  }) async {
    if (_disposed || _busy || hasCapture) return null;
    final selected = model ?? library.selectedModel(.synthesis);
    if (selected == null ||
        selected.kind != .synthesis ||
        !selected.available) {
      return .missingFiles;
    }
    final voice = selected.id == library.synthesisId ? library.voice : 0;
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

  void stopConversation(SpeechConversation owner) {
    var changed = false;
    final playback = _playback;
    if (playback?.owner case (final SpeechConversation scope, String _)
        when scope == owner) {
      playback!.cancel();
      changed = true;
    }
    final capture = _capture;
    if (capture != null && capture.owner == owner) {
      capture.cancel();
      changed = true;
    }
    if (changed) _notify();
  }

  Future<({String? text, SpeechFailureReason? error})> startRecording(
    SpeechConversation owner,
  ) async {
    if (_disposed || _busy || hasCapture) return (text: null, error: null);
    final selected = library.selectedModel(.recognition);
    if (selected == null) {
      return (text: null, error: SpeechFailureReason.missingFiles);
    }
    final task = _SpeechCapture(owner, selected.id);
    _capture = task;
    final playback = _playback;
    playback?.cancel();
    _notify();
    var readingMicrophone = false;
    try {
      await playback?.finished.future;
      final directory = await _store.directoryFor(selected);
      if (task.cancellation.isCompleted) return (text: null, error: null);
      readingMicrophone = true;
      final audio = await _input.record(
        stop: task.stop.future,
        started: () {
          if (task.cancellation.isCompleted) return;
          task.phase = .recording;
          _notify();
        },
      );
      readingMicrophone = false;
      if (audio == null || task.cancellation.isCompleted) {
        return (text: null, error: null);
      }
      if (audio.pcm.isEmpty) {
        return (text: null, error: SpeechFailureReason.noSpeech);
      }
      task.phase = .transcribing;
      _notify();
      final text = (await _engine.recognize(
        directory,
        audio.pcm,
        sampleRate: audio.sampleRate,
        channels: audio.channels,
        cancellation: task.cancellation.future,
      )).trim();
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
            : readingMicrophone
            ? SpeechFailureReason.microphone
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
