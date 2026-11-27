/*
 * @Description: 管理本机语音库及独占录音和播放任务。
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/files/package_transfer.dart';
import '../data/speech_aec3.dart';
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

  final Map<String, String> _knownHardwareNames = {};

  List<SpeechAudioDevice> listAudioDevices(SpeechModelKind kind) {
    final devices = WebRtcAec3Library.listAudioDevices(
      isCapture: kind == .recognition,
    );
    var changed = false;
    for (final device in devices) {
      if (device.name.isNotEmpty &&
          _knownHardwareNames[device.id] != device.name) {
        _knownHardwareNames[device.id] = device.name;
        changed = true;
      }
    }
    if (changed) _persistHardwareNames();
    return devices;
  }

  String? knownHardwareName(String id) => _knownHardwareNames[id];

  void rememberHardwareName(String id, String name) {
    if (name.isNotEmpty && _knownHardwareNames[id] != name) {
      _knownHardwareNames[id] = name;
      _persistHardwareNames();
    }
  }

  void _persistHardwareNames() {
    if (_disposed) return;
    unawaited(
      _store
          .saveHardwareNames(Map<String, String>.of(_knownHardwareNames))
          .catchError((Object _, StackTrace _) {}),
    );
  }

  bool _busy = false;
  bool _loaded = false;
  bool _disposed = false;
  bool _warming = false;
  bool get busy => _busy;
  bool get loaded => _loaded;

  final Map<Object, _SpeechPlayback> _playbacks = {};
  final Map<SpeechConversation, _SpeechCapture> _captures = {};
  String? _lastPlayedText;
  DateTime? _lastPlaybackEndedAt;
  final Map<SpeechConversation, String> _lastPlayedTextByOwner = {};
  final Map<SpeechConversation, DateTime> _lastPlaybackEndedAtByOwner = {};
  final Set<String> _autoReadMessageIds = {};
  final Map<
    ({String modelId, int voice, String text, double gain, double speed}),
    List<Uint8List>
  >
  _synthesisCache = {};

  bool hasAutoRead(String messageId) => _autoReadMessageIds.contains(messageId);

  void markAutoRead(String messageId) => _autoReadMessageIds.add(messageId);
  static const _maxCachedClips = 12;
  bool get hasCapture => _captures.isNotEmpty;
  bool get hasManualCapture => _captures.values.any((c) => !c.continuous);
  bool get hasPlayback => _playbacks.isNotEmpty;

  bool hasCaptureFor(SpeechConversation owner) {
    final capture = _captures[owner];
    return capture != null && !capture.cancellation.isCompleted;
  }

  bool hasManualCaptureFor(SpeechConversation owner) {
    final capture = _captures[owner];
    return capture != null &&
        !capture.continuous &&
        !capture.cancellation.isCompleted;
  }

  SpeechConversation? _conversationOf(Object owner) => switch (owner) {
    final SpeechConversation c => c,
    (final SpeechConversation c, _) => c,
    _ => null,
  };

  bool hasPlaybackFor(SpeechConversation owner) => _playbacks.values.any(
    (p) => _conversationOf(p.owner) == owner && !p.cancellation.isCompleted,
  );

  String? playingTextFor(SpeechConversation owner) {
    for (final playback in _playbacks.values) {
      if (_conversationOf(playback.owner) == owner &&
          !playback.cancellation.isCompleted) {
        return playback.text;
      }
    }
    return null;
  }

  String? get playingText {
    for (final playback in _playbacks.values) {
      if (!playback.cancellation.isCompleted) return playback.text;
    }
    return null;
  }

  String? activeOrRecentPlayingTextFor(SpeechConversation owner) {
    if (playingTextFor(owner) case final active?) return active;
    final endedAt = _lastPlaybackEndedAtByOwner[owner];
    final window = WebRtcAec3Library.tryLoad() != null
        ? const Duration(seconds: 2)
        : const Duration(seconds: 12);
    if (endedAt != null && DateTime.now().difference(endedAt) < window) {
      return _lastPlayedTextByOwner[owner];
    }
    return null;
  }

  void clearRecentPlayingTextFor(SpeechConversation owner) {
    _lastPlayedTextByOwner.remove(owner);
    _lastPlaybackEndedAtByOwner.remove(owner);
  }

  String? get activeOrRecentPlayingText {
    if (playingText case final active?) return active;
    final endedAt = _lastPlaybackEndedAt;
    final window = WebRtcAec3Library.tryLoad() != null
        ? const Duration(seconds: 2)
        : const Duration(seconds: 12);
    if (endedAt != null && DateTime.now().difference(endedAt) < window) {
      return _lastPlayedText;
    }
    return null;
  }

  void clearRecentPlayingText() {
    _lastPlayedText = null;
    _lastPlaybackEndedAt = null;
  }

  bool isContinuousListening(SpeechConversation owner) {
    final capture = _captures[owner];
    return capture != null &&
        capture.continuous &&
        !capture.cancellation.isCompleted;
  }

  SpeechCapturePhase? capturePhase(SpeechConversation owner) {
    final capture = _captures[owner];
    return capture != null && !capture.cancellation.isCompleted
        ? capture.phase
        : null;
  }

  String? _playbackDeviceIdFor(Object owner) =>
      _conversationOf(owner)?.synthesisHardwareId;

  bool isPlaying(Object owner) {
    final playback = _playbacks[owner];
    return playback != null && !playback.cancellation.isCompleted;
  }

  void updateConversationStandby(SpeechConversation owner, bool standby) {
    if (owner._standby == standby) return;
    owner._standby = standby;
    if (hasCaptureFor(owner)) {
      _notify();
    }
  }

  bool isAgentPlaying(Object agent) => _playbacks.values.any(
    (p) =>
        !p.cancellation.isCompleted &&
        identical(_conversationOf(p.owner)?.agent, agent),
  );

  ({bool continuous, bool standby, SpeechCapturePhase phase})? agentCaptureState(
    Object agent,
  ) {
    for (final capture in _captures.values) {
      if (!capture.cancellation.isCompleted &&
          identical(capture.owner.agent, agent)) {
        return (
          continuous: capture.continuous,
          standby: capture.owner._standby,
          phase: capture.phase,
        );
      }
    }
    return null;
  }

  Future<void> load() async {
    _loaded = await _change(_store.read) == null;
    final storedNames = await _store.loadHardwareNames();
    if (!_disposed && storedNames.isNotEmpty) {
      for (final entry in storedNames.entries) {
        _knownHardwareNames.putIfAbsent(entry.key, () => entry.value);
      }
    }
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
        for (final capture in _captures.values.toList()) {
          if (ids.contains(capture.modelId)) {
            capture.cancel();
            await capture.finished.future;
          }
        }
        for (final playback in _playbacks.values.toList()) {
          if (ids.contains(playback.modelId)) {
            playback.cancel();
            await playback.finished.future;
          }
        }
        _synthesisCache.removeWhere((key, _) => ids.contains(key.modelId));
        if (library.models.any(
          (model) => ids.contains(model.id) && model.kind == .synthesis,
        )) {
          _engine.disposeSynthesisSession();
        }
        return _store.deleteModels(library, ids);
      });

  Future<void> warmUpSynthesis(SpeechVoiceSelection? selection) async {
    if (_disposed || _busy || hasManualCapture || _warming) return;
    final selected = library.synthesisModel(selection);
    if (selected == null) return;
    _warming = true;
    try {
      final directory = await _store.directoryFor(selected);
      if (_disposed || _busy || hasManualCapture) return;
      await _engine.warmUpSynthesis(selected.format, directory);
    } catch (_) {
      // 预热失败不向用户弹窗报错。
    } finally {
      _warming = false;
    }
  }

  /// 在空闲时后台预合成台词并写入缓存，点击播放即可秒开。
  Future<void> preSynthesize(
    String text, {
    SpeechVoiceSelection? selection,
    double gain = defaultSpeechSynthesisGain,
    double speed = defaultSpeechSynthesisSpeed,
  }) async {
    if (_disposed ||
        _busy ||
        hasManualCapture ||
        _playbacks.isNotEmpty ||
        _warming ||
        text.trim().isEmpty) {
      return;
    }
    final selected = library.synthesisModel(selection);
    if (selected == null) return;
    final voice = selection?.voice ?? 0;
    final clampedGain = clampSpeechSynthesisGain(gain);
    final clampedSpeed = clampSpeechSynthesisSpeed(speed);
    final cacheKey = (
      modelId: selected.id,
      voice: voice,
      text: text,
      gain: clampedGain,
      speed: clampedSpeed,
    );
    if (_synthesisCache.containsKey(cacheKey)) return;
    _warming = true;
    final cancellation = Completer<void>();
    try {
      final directory = await _store.directoryFor(selected);
      if (_disposed || _busy || hasManualCapture || _playbacks.isNotEmpty) {
        return;
      }
      final generated = <Uint8List>[];
      await for (final chunk in _engine.synthesizeStream(
        selected.format,
        directory,
        text,
        voice,
        gain: clampedGain,
        speed: clampedSpeed,
        cancellation: cancellation.future,
      )) {
        if (_disposed || _busy || hasManualCapture || _playbacks.isNotEmpty) {
          if (!cancellation.isCompleted) cancellation.complete();
          return;
        }
        generated.add(chunk);
      }
      if (generated.isNotEmpty) {
        _synthesisCache[cacheKey] = List.unmodifiable(generated);
        if (_synthesisCache.length > _maxCachedClips) {
          _synthesisCache.remove(_synthesisCache.keys.first);
        }
      }
    } catch (_) {
      // 预合成失败不向用户弹窗报错。
    } finally {
      if (!cancellation.isCompleted) cancellation.complete();
      _warming = false;
    }
  }

  Future<SpeechFailureReason?> play(
    Object owner,
    String text, {
    SpeechVoiceSelection? selection,
    bool allowContinuousCapture = false,
    double gain = defaultSpeechSynthesisGain,
    double speed = defaultSpeechSynthesisSpeed,
  }) async {
    final scope = _conversationOf(owner);
    if (_disposed ||
        _busy ||
        (scope != null ? hasManualCaptureFor(scope) : hasManualCapture)) {
      return null;
    }
    final selected = library.synthesisModel(selection);
    if (selected == null) return .missingFiles;
    final currentPlayback = _playbacks[owner];
    if (isPlaying(owner) &&
        currentPlayback!.modelId == selected.id &&
        currentPlayback.text == text) {
      return null;
    }
    final voice = selection?.voice ?? 0;
    final clampedGain = clampSpeechSynthesisGain(gain);
    final clampedSpeed = clampSpeechSynthesisSpeed(speed);
    final activeCapture = scope == null ? null : _captures[scope];
    if (!allowContinuousCapture &&
        activeCapture != null &&
        activeCapture.continuous) {
      activeCapture.cancel();
    }
    final deviceId = _playbackDeviceIdFor(owner);
    if (scope?.agent != null && deviceId == null) return null;
    final conflictingPlaybacks = <_SpeechPlayback>[
      for (final entry in _playbacks.entries)
        if (entry.key == owner ||
            (scope != null && _conversationOf(entry.key) == scope) ||
            (deviceId != null && _playbackDeviceIdFor(entry.key) == deviceId))
          entry.value,
    ];
    for (final prev in conflictingPlaybacks) {
      prev.cancel();
    }
    final task = _SpeechPlayback(owner, selected.id, text);
    _playbacks[owner] = task;
    _lastPlayedText = text;
    if (scope != null) _lastPlayedTextByOwner[scope] = text;
    _notify();
    try {
      if (!allowContinuousCapture &&
          activeCapture != null &&
          activeCapture.continuous) {
        await activeCapture.finished.future;
      }
      for (final prev in conflictingPlaybacks) {
        await prev.finished.future;
      }
      if (task.cancellation.isCompleted) return null;
      final directory = await _store.directoryFor(selected);
      if (task.cancellation.isCompleted) return null;
      final cacheKey = (
        modelId: selected.id,
        voice: voice,
        text: text,
        gain: clampedGain,
        speed: clampedSpeed,
      );
      final cached = _synthesisCache.remove(cacheKey);
      if (cached != null) {
        _synthesisCache[cacheKey] = cached;
        await _output.playStream(
          Stream.fromIterable(cached),
          task.cancellation.future,
          deviceId: _playbackDeviceIdFor(owner),
        );
        return null;
      }
      final generated = <Uint8List>[];
      var streamCompleted = false;
      final chunks = _engine
          .synthesizeStream(
            selected.format,
            directory,
            text,
            voice,
            gain: clampedGain,
            speed: clampedSpeed,
            cancellation: task.cancellation.future,
          )
          .transform(
            StreamTransformer<Uint8List, Uint8List>.fromHandlers(
              handleData: (chunk, sink) {
                generated.add(chunk);
                sink.add(chunk);
              },
              handleDone: (sink) {
                streamCompleted = true;
                sink.close();
              },
            ),
          );
      await _output.playStream(
        chunks,
        task.cancellation.future,
        deviceId: _playbackDeviceIdFor(owner),
      );
      if (streamCompleted && generated.isNotEmpty) {
        _synthesisCache[cacheKey] = List.unmodifiable(generated);
        if (_synthesisCache.length > _maxCachedClips) {
          _synthesisCache.remove(_synthesisCache.keys.first);
        }
      }
      return null;
    } on SpeechFailure catch (error) {
      return task.cancellation.isCompleted ? null : error.reason;
    } catch (_) {
      return task.cancellation.isCompleted ? null : .playback;
    } finally {
      task.cancel();
      task.finished.complete();
      final now = DateTime.now();
      _lastPlaybackEndedAt = now;
      if (scope != null) _lastPlaybackEndedAtByOwner[scope] = now;
      if (identical(task, _playbacks[owner])) {
        _playbacks.remove(owner);
        _notify();
      }
    }
  }

  void stopPlayback(Object owner) {
    if (!isPlaying(owner)) return;
    _playbacks[owner]!.cancel();
    _notify();
  }

  void stopConversation(SpeechConversation owner, {SpeechModelKind? kind}) {
    var changed = false;
    if (kind != .recognition) {
      for (final playback in _playbacks.values) {
        if (_conversationOf(playback.owner) == owner &&
            !playback.cancellation.isCompleted) {
          playback.cancel();
          changed = true;
        }
      }
    }
    final capture = _captures[owner];
    if (capture != null && kind != .synthesis) {
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
    if (_disposed ||
        _busy ||
        hasCaptureFor(owner) ||
        (owner.agent != null && owner.recognitionHardwareId == null)) {
      return (text: null, error: null);
    }
    final selected = library.recognitionModel(modelId);
    if (selected == null) {
      return (text: null, error: SpeechFailureReason.missingFiles);
    }
    final previousCapture = _captures[owner];
    previousCapture?.cancel();
    final task = _SpeechCapture(owner, selected.id);
    _captures[owner] = task;
    final ownerPlaybacks = [
      for (final playback in _playbacks.values)
        if (_conversationOf(playback.owner) == owner) playback,
    ];
    for (final playback in ownerPlaybacks) {
      playback.cancel();
    }
    _notify();
    try {
      await previousCapture?.finished.future;
      for (final playback in ownerPlaybacks) {
        await playback.finished.future;
      }
      final directory = await _store.directoryFor(selected);
      if (task.cancellation.isCompleted) return (text: null, error: null);
      final audio = StreamController<SpeechAudioChunk>();
      final abortRecognition = Completer<void>();
      Future<void> record() async {
        try {
          await _input.record(
            stop: task.stop.future,
            captureDeviceId: owner.recognitionHardwareId,
            playbackDeviceId: owner.synthesisHardwareId,
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
        selected.format,
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
      if (identical(task, _captures[owner])) {
        _captures.remove(owner);
      }
      _notify();
    }
  }

  void finishRecording(SpeechConversation owner) {
    final capture = _captures[owner];
    if (capture == null ||
        capturePhase(owner) != .recording ||
        capture.stop.isCompleted) {
      return;
    }
    capture.phase = .transcribing;
    capture.stop.complete(true);
    _notify();
  }

  Future<SpeechFailureReason?> startContinuousListening(
    SpeechConversation owner, {
    required String? modelId,
    bool allowDuringPlayback = false,
    double silenceSeconds = defaultSpeechSendSilenceSeconds,
    double micGain = defaultSpeechMicGain,
    void Function(String)? onPartial,
    required void Function(String) onUtterance,
  }) async {
    if (_disposed ||
        _busy ||
        hasCaptureFor(owner) ||
        (owner.agent != null && owner.recognitionHardwareId == null)) {
      return null;
    }
    final selected = library.recognitionModel(modelId);
    if (selected == null) return .missingFiles;
    final previousCapture = _captures[owner];
    previousCapture?.cancel();
    final task = _SpeechCapture(owner, selected.id, continuous: true);
    _captures[owner] = task;
    final ownerPlaybacks = allowDuringPlayback
        ? const <_SpeechPlayback>[]
        : [
            for (final playback in _playbacks.values)
              if (_conversationOf(playback.owner) == owner) playback,
          ];
    for (final playback in ownerPlaybacks) {
      playback.cancel();
    }
    _notify();
    try {
      await previousCapture?.finished.future;
      for (final playback in ownerPlaybacks) {
        await playback.finished.future;
      }
      final directory = await _store.directoryFor(selected);
      if (task.cancellation.isCompleted) return null;
      final audio = StreamController<SpeechAudioChunk>();
      final abortRecognition = Completer<void>();
      Future<void> record() async {
        try {
          await _input.record(
            stop: task.stop.future,
            continuous: true,
            captureDeviceId: owner.recognitionHardwareId,
            playbackDeviceId: owner.synthesisHardwareId,
            started: () {
              if (task.cancellation.isCompleted) return;
              task.phase = .recording;
              _notify();
            },
            onAudio: (chunk) {
              if (task.cancellation.isCompleted) return;
              final scaled = applySpeechPcmGain(chunk.pcm, micGain);
              audio.add(
                identical(scaled, chunk.pcm)
                    ? chunk
                    : (
                        pcm: scaled,
                        sampleRate: chunk.sampleRate,
                        channels: chunk.channels,
                      ),
              );
            },
          );
        } on SpeechFailure {
          rethrow;
        } catch (_) {
          throw const SpeechFailure(.microphone);
        } finally {
          unawaited(audio.close());
        }
      }

      final recording = record();
      final recognition = _engine.recognizeContinuous(
        selected.format,
        directory,
        audio.stream,
        silenceSeconds: silenceSeconds,
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
        onUtterance: (text) {
          if (!task.cancellation.isCompleted && task.phase == .recording) {
            onUtterance(text);
          }
        },
      );
      try {
        await Future.wait<void>([recording, recognition], eagerError: true);
      } catch (_) {
        if (!task.stop.isCompleted) task.stop.complete(false);
        abortRecognition.complete();
        await Future.wait<void>([
          recording.then<void>((_) {}, onError: (Object _) {}),
          recognition.then<void>((_) {}, onError: (Object _) {}),
        ]);
        rethrow;
      }
      return null;
    } on SpeechFailure catch (error) {
      return task.cancellation.isCompleted ? null : error.reason;
    } catch (_) {
      return task.cancellation.isCompleted ? null : .engine;
    } finally {
      task.cancel();
      task.finished.complete();
      if (identical(task, _captures[owner])) {
        _captures.remove(owner);
      }
      _notify();
    }
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
    for (final playback in _playbacks.values) {
      playback.cancel();
    }
    for (final capture in _captures.values) {
      capture.cancel();
    }
    _engine.disposeSynthesisSession();
    super.dispose();
  }
}

class SpeechConversation {
  SpeechConversation({
    this.agent,
    this.recognitionHardwareId,
    this.synthesisHardwareId,
  });

  Object? agent;
  String? recognitionHardwareId;
  String? synthesisHardwareId;
  bool _standby = false;
  bool get standby => _standby;
}

class _SpeechCapture {
  _SpeechCapture(this.owner, this.modelId, {this.continuous = false});

  final SpeechConversation owner;
  final String modelId;
  final bool continuous;
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
  _SpeechPlayback(this.owner, this.modelId, this.text);

  final Object owner;
  final String modelId;
  final String text;
  final cancellation = Completer<void>();
  final finished = Completer<void>();

  void cancel() {
    if (!cancellation.isCompleted) cancellation.complete();
  }
}
