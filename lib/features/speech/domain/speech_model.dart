/*
 * @Description: 定义离线语音模型、会话绑定和故障类型。
 */

import 'dart:typed_data';

enum SpeechModelKind { recognition, synthesis }

enum SpeechCapturePhase { starting, recording, transcribing }

enum SpeechModelFormat {
  bilingualZipformer(SpeechModelKind.recognition, [
    'encoder-epoch-99-avg-1.int8.onnx',
    'decoder-epoch-99-avg-1.onnx',
    'joiner-epoch-99-avg-1.int8.onnx',
    'tokens.txt',
  ]),
  chineseVits(SpeechModelKind.synthesis, [
    'model.onnx',
    'tokens.txt',
    'lexicon.txt',
    'phone.fst',
    'date.fst',
    'number.fst',
    'dict/hmm_model.utf8',
    'dict/idf.utf8',
    'dict/jieba.dict.utf8',
    'dict/stop_words.utf8',
    'dict/user.dict.utf8',
    'dict/pos_dict/char_state_tab.utf8',
    'dict/pos_dict/prob_emit.utf8',
    'dict/pos_dict/prob_start.utf8',
    'dict/pos_dict/prob_trans.utf8',
  ]),
  kokoroMultiLanguage(SpeechModelKind.synthesis, [
    'model.onnx',
    'voices.bin',
    'tokens.txt',
    'lexicon-us-en.txt',
    'lexicon-zh.txt',
    'phone-zh.fst',
    'date-zh.fst',
    'number-zh.fst',
    'espeak-ng-data/phondata',
    'espeak-ng-data/phonindex',
    'espeak-ng-data/phontab',
    'espeak-ng-data/intonations',
    'espeak-ng-data/en_dict',
    'espeak-ng-data/lang/gmw/en-US',
  ], resourceDirectory: 'espeak-ng-data'),
  streamingParaformer(SpeechModelKind.recognition, [
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'tokens.txt',
  ]),
  senseVoice(SpeechModelKind.recognition, [
    'model.int8.onnx',
    'tokens.txt',
  ]),
  matchaZh(SpeechModelKind.synthesis, [
    'model-steps-3.onnx',
    'vocos-22khz-univ.onnx',
    'tokens.txt',
    'lexicon.txt',
  ]);

  const SpeechModelFormat(this.kind, this.files, {this.resourceDirectory});

  final SpeechModelKind kind;
  final List<String> files;
  final String? resourceDirectory;
}

class ResolvedSpeechModel {
  const ResolvedSpeechModel({
    required this.requiredFiles,
    this.encoder,
    this.decoder,
    this.joiner,
    this.model,
    this.vocoder,
    this.voices,
    required this.tokens,
    this.lexicons = const [],
    this.ruleFsts = const [],
    this.dictDir,
    this.dataDir,
  });

  final List<String> requiredFiles;
  final String? encoder;
  final String? decoder;
  final String? joiner;
  final String? model;
  final String? vocoder;
  final String? voices;
  final String tokens;
  final List<String> lexicons;
  final List<String> ruleFsts;
  final String? dictDir;
  final String? dataDir;
}

String? _pickOnnx(Iterable<String> files, bool Function(String lower) match) {
  final hits = files.where((f) => match(f.toLowerCase())).toList()..sort();
  if (hits.isEmpty) return null;
  return hits.where((f) => f.toLowerCase().endsWith('.int8.onnx')).firstOrNull ??
      hits.first;
}

bool isSpeechModelAsset(String relative) {
  final lower = relative.toLowerCase();
  if (lower.startsWith('dict/') || lower.startsWith('espeak-ng-data/')) {
    return true;
  }
  if (lower.contains('/')) return false;
  return lower.endsWith('.txt') ||
      lower.endsWith('.bin') ||
      lower.endsWith('.fst');
}

SpeechModelFormat? detectSpeechModelFormat(Iterable<String> relativePaths) {
  final paths = relativePaths.toSet();
  final topLevel = paths.where((p) => !p.contains('/')).toList();
  final onnx = topLevel.where((f) => f.toLowerCase().endsWith('.onnx')).toList();
  if (onnx.isEmpty) return null;

  final hasVoices = topLevel.any((f) => f.toLowerCase() == 'voices.bin');
  final hasLexicon = topLevel.any(
    (f) => f.toLowerCase().startsWith('lexicon') && f.toLowerCase().endsWith('.txt'),
  );
  final hasDict = paths.any((p) => p.toLowerCase().startsWith('dict/'));
  final modelOnnx = _pickOnnx(
    onnx,
    (f) => f.contains('model') && !f.contains('vocos') && !f.contains('vocoder'),
  );

  // 1. TTS: Kokoro
  if (hasVoices && modelOnnx != null) {
    return SpeechModelFormat.kokoroMultiLanguage;
  }
  // 2. TTS: Matcha + Vocoder
  final vocoder = _pickOnnx(
    onnx,
    (f) => f.contains('vocos') || f.contains('vocoder'),
  );
  final hasMatchaAcoustic = onnx.any((f) => f.toLowerCase().contains('model-steps'));
  if ((vocoder != null || hasMatchaAcoustic) && hasLexicon) {
    final acoustic = _pickOnnx(
      onnx,
      (f) => f != vocoder?.toLowerCase() && !f.contains('vocos') && !f.contains('vocoder'),
    );
    if (acoustic != null) return SpeechModelFormat.matchaZh;
  }
  // 3. ASR: Streaming Zipformer (encoder + decoder + joiner)
  final encoder = _pickOnnx(onnx, (f) => f.contains('encoder'));
  final decoder = _pickOnnx(onnx, (f) => f.contains('decoder'));
  final joiner = _pickOnnx(onnx, (f) => f.contains('joiner'));
  if (encoder != null && decoder != null && joiner != null) {
    return SpeechModelFormat.bilingualZipformer;
  }
  // 4. ASR: Streaming Paraformer (encoder + decoder, no joiner)
  if (encoder != null && decoder != null) {
    return SpeechModelFormat.streamingParaformer;
  }
  // 5. TTS: General VITS (lexicon or dict/ + single onnx)
  if (hasLexicon || hasDict) {
    final vitsModel =
        modelOnnx ??
        _pickOnnx(
          onnx,
          (f) => !f.contains('encoder') && !f.contains('decoder') && !f.contains('joiner'),
        );
    if (vitsModel != null) return SpeechModelFormat.chineseVits;
  }
  // 6. ASR: SenseVoice (single model*.onnx + tokens.txt, no lexicon/voices)
  if (modelOnnx != null) {
    return SpeechModelFormat.senseVoice;
  }
  return null;
}

ResolvedSpeechModel? resolveSpeechModelFiles(
  SpeechModelFormat format,
  Iterable<String> relativePaths,
) {
  final paths = relativePaths.toSet();
  final topLevel = paths.where((p) => !p.contains('/')).toList()..sort();
  final tokens =
      topLevel.where((f) => f.toLowerCase() == 'tokens.txt').firstOrNull ??
      topLevel.where((f) => f.toLowerCase().endsWith('tokens.txt')).firstOrNull;
  if (tokens == null) return null;
  final onnx = topLevel.where((f) => f.toLowerCase().endsWith('.onnx')).toList();
  final lexicons = topLevel
      .where(
        (f) =>
            f.toLowerCase().startsWith('lexicon') &&
            f.toLowerCase().endsWith('.txt'),
      )
      .toList()
    ..sort();
  final ruleFsts = topLevel
      .where((f) => f.toLowerCase().endsWith('.fst'))
      .toList()
    ..sort();
  final dictDir = paths.any((p) => p.toLowerCase().startsWith('dict/'))
      ? 'dict'
      : null;
  final dataDir = paths.any((p) => p.toLowerCase().startsWith('espeak-ng-data/'))
      ? 'espeak-ng-data'
      : null;

  switch (format) {
    case SpeechModelFormat.bilingualZipformer:
      final encoder = _pickOnnx(onnx, (f) => f.contains('encoder'));
      final decoder = _pickOnnx(onnx, (f) => f.contains('decoder'));
      final joiner = _pickOnnx(onnx, (f) => f.contains('joiner'));
      if (encoder == null || decoder == null || joiner == null) return null;
      return ResolvedSpeechModel(
        requiredFiles: [encoder, decoder, joiner, tokens],
        encoder: encoder,
        decoder: decoder,
        joiner: joiner,
        tokens: tokens,
      );
    case SpeechModelFormat.streamingParaformer:
      final encoder = _pickOnnx(onnx, (f) => f.contains('encoder'));
      final decoder = _pickOnnx(onnx, (f) => f.contains('decoder'));
      if (encoder == null || decoder == null) return null;
      return ResolvedSpeechModel(
        requiredFiles: [encoder, decoder, tokens],
        encoder: encoder,
        decoder: decoder,
        tokens: tokens,
      );
    case SpeechModelFormat.senseVoice:
      final model = _pickOnnx(
        onnx,
        (f) =>
            f.contains('model') &&
            !f.contains('encoder') &&
            !f.contains('decoder') &&
            !f.contains('joiner'),
      );
      if (model == null) return null;
      return ResolvedSpeechModel(
        requiredFiles: [model, tokens],
        model: model,
        tokens: tokens,
      );
    case SpeechModelFormat.chineseVits:
      final model =
          _pickOnnx(onnx, (f) => f.contains('model')) ??
          _pickOnnx(
            onnx,
            (f) =>
                !f.contains('encoder') &&
                !f.contains('decoder') &&
                !f.contains('joiner'),
          );
      if (model == null) return null;
      return ResolvedSpeechModel(
        requiredFiles: [model, tokens, if (lexicons.isNotEmpty) lexicons.first],
        model: model,
        tokens: tokens,
        lexicons: lexicons,
        ruleFsts: ruleFsts,
        dictDir: dictDir,
      );
    case SpeechModelFormat.kokoroMultiLanguage:
      final model = _pickOnnx(onnx, (f) => f.contains('model'));
      final voices =
          topLevel.where((f) => f.toLowerCase() == 'voices.bin').firstOrNull;
      final phondata = paths
          .where((p) => p.toLowerCase() == 'espeak-ng-data/phondata')
          .firstOrNull;
      if (model == null || voices == null || phondata == null) return null;
      return ResolvedSpeechModel(
        requiredFiles: [model, voices, tokens, phondata],
        model: model,
        voices: voices,
        tokens: tokens,
        lexicons: lexicons,
        ruleFsts: ruleFsts,
        dataDir: dataDir,
      );
    case SpeechModelFormat.matchaZh:
      final vocoder = _pickOnnx(
        onnx,
        (f) => f.contains('vocos') || f.contains('vocoder'),
      );
      final acoustic = _pickOnnx(
        onnx,
        (f) =>
            f != vocoder?.toLowerCase() &&
            !f.contains('vocos') &&
            !f.contains('vocoder'),
      );
      if (acoustic == null || vocoder == null || lexicons.isEmpty) return null;
      return ResolvedSpeechModel(
        requiredFiles: [acoustic, vocoder, tokens, lexicons.first],
        model: acoustic,
        vocoder: vocoder,
        tokens: tokens,
        lexicons: lexicons,
        ruleFsts: ruleFsts,
        dictDir: dictDir,
      );
  }
}

enum SpeechFailureReason {
  unsupportedModel,
  missingFiles,
  invalidModel,
  duplicateModel,
  invalidPackage,
  packageTooLarge,
  exportFailed,
  storage,
  engine,
  microphone,
  noSpeech,
  playback,
}

class SpeechFailure implements Exception {
  const SpeechFailure(this.reason);

  final SpeechFailureReason reason;
}

class SpeechModel {
  static const maxBytes = 2 * 1024 * 1024 * 1024;

  const SpeechModel({
    required this.id,
    required this.format,
    required this.name,
    required this.voiceCount,
    this.available = true,
  });

  final String id;
  final SpeechModelFormat format;
  final String name;
  final int voiceCount;
  final bool available;

  SpeechModelKind get kind => format.kind;
}

const defaultSpeechIdleTimeoutSeconds = 60;
const defaultSpeechSendSilenceSeconds = 1.0;
const defaultSpeechMinTriggerLength = 2;
const defaultSpeechMicGain = 1.0;
const defaultSpeechSynthesisGain = 1.0;
const defaultSpeechSynthesisSpeed = 1.0;

double clampSpeechSendSilenceSeconds(double value) =>
    value.isNaN ? defaultSpeechSendSilenceSeconds : value.clamp(0.5, 10.0);

int clampSpeechMinTriggerLength(int value) => value.clamp(1, 10);

double clampSpeechMicGain(double value) =>
    value.isNaN ? defaultSpeechMicGain : value.clamp(0.1, 3.0);

double clampSpeechSynthesisGain(double value) =>
    value.isNaN ? defaultSpeechSynthesisGain : value.clamp(0.1, 3.0);

double clampSpeechSynthesisSpeed(double value) =>
    value.isNaN ? defaultSpeechSynthesisSpeed : value.clamp(0.5, 2.0);

/// 对 16-bit 小端 PCM 音频做软件增益并限幅，避免削波失真。
Uint8List applySpeechPcmGain(Uint8List pcm, double gain) {
  final clamped = clampSpeechMicGain(gain);
  if ((clamped - 1.0).abs() < 0.01 || pcm.length < 2) return pcm;
  final input = ByteData.sublistView(pcm);
  final out = Uint8List(pcm.length);
  final output = ByteData.sublistView(out);
  for (var offset = 0; offset + 1 < pcm.length; offset += 2) {
    final sample = input.getInt16(offset, Endian.little);
    final scaled = (sample * clamped).round().clamp(-32768, 32767);
    output.setInt16(offset, scaled, Endian.little);
  }
  return out;
}

typedef SpeechAudioDevice = ({String id, String name, bool isDefault});
typedef SpeechVoiceSelection = ({String modelId, int voice});
typedef SpeechBindings = ({
  SpeechVoiceSelection? voice,
  String? recognitionId,
  bool synthesisPaused,
  bool recognitionPaused,
  bool autoPlay,
  bool continuousRecognition,
  bool voiceInterrupt,
  List<String> wakeWords,
  int idleTimeoutSeconds,
  double sendSilenceSeconds,
  int minTriggerLength,
  bool interruptStopsGeneration,
  double micGain,
  double synthesisGain,
  double synthesisSpeed,
  bool fallbackReadBody,
  bool includeWakeWordInCommand,
  String? recognitionHardwareId,
  String? synthesisHardwareId,
});

const SpeechBindings emptySpeechBindings = (
  voice: null,
  recognitionId: null,
  synthesisPaused: false,
  recognitionPaused: false,
  autoPlay: true,
  continuousRecognition: true,
  voiceInterrupt: true,
  wakeWords: <String>[],
  idleTimeoutSeconds: defaultSpeechIdleTimeoutSeconds,
  sendSilenceSeconds: defaultSpeechSendSilenceSeconds,
  minTriggerLength: defaultSpeechMinTriggerLength,
  interruptStopsGeneration: false,
  micGain: defaultSpeechMicGain,
  synthesisGain: defaultSpeechSynthesisGain,
  synthesisSpeed: defaultSpeechSynthesisSpeed,
  fallbackReadBody: false,
  includeWakeWordInCommand: true,
  recognitionHardwareId: null,
  synthesisHardwareId: null,
);

List<String> normalizeWakeWords(Iterable<String> words) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in words) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed.toLowerCase())) {
      result.add(trimmed);
    }
  }
  return result.isEmpty ? const <String>[] : List.unmodifiable(result);
}

({bool matched, String command}) matchSpeechWakeWord(
  String transcript,
  List<String> wakeWords,
) {
  final text = transcript.trim();
  if (wakeWords.isEmpty) return (matched: text.isNotEmpty, command: text);
  final lower = text.toLowerCase();
  var bestIndex = -1;
  var bestLength = 0;
  for (final word in wakeWords) {
    final needle = word.trim().toLowerCase();
    if (needle.isEmpty) continue;
    final index = lower.indexOf(needle);
    if (index >= 0 &&
        (bestIndex < 0 ||
            index < bestIndex ||
            (index == bestIndex && needle.length > bestLength))) {
      bestIndex = index;
      bestLength = needle.length;
    }
  }
  if (bestIndex < 0) return (matched: false, command: '');
  final rest = text.substring(bestIndex + bestLength);
  final command = rest
      .replaceFirst(RegExp(r'^[\s,，.。!！?？:：;；、\-~—]+'), '')
      .trim();
  return (matched: true, command: command);
}

final _nonWordPattern = RegExp(r'[\s\p{P}\p{S}]+', unicode: true);

String _normalizeSpeechText(String input) =>
    input.toLowerCase().replaceAll(_nonWordPattern, '');

/// 判断识别到的文本是否属于扬声器播放或刚结束放音的回声。
bool isLikelyPlaybackEcho(
  String transcript,
  String? playingText, {
  bool rejectShort = true,
}) {
  if (playingText == null || playingText.isEmpty) return false;
  final candidate = _normalizeSpeechText(transcript);
  if (candidate.isEmpty) return true;
  final source = _normalizeSpeechText(playingText);
  if (source.isEmpty) return false;
  if (source.contains(candidate)) return true;
  // 极短的 1~2 字残音在放音期间极易由外放尾音误触发，视为回声忽略。
  if (rejectShort && candidate.runes.length <= 2) return true;
  if (candidate.runes.length <= 2) return false;
  final sourceRunes = source.runes.toSet();
  final candidateRunes = candidate.runes.toList();
  var matchedRunes = 0;
  for (final rune in candidateRunes) {
    if (sourceRunes.contains(rune)) matchedRunes++;
  }
  final overlap = matchedRunes / candidateRunes.length;
  if (overlap >= 0.58) return true;
  for (var i = 0; i <= candidate.length - 3; i++) {
    if (source.contains(candidate.substring(i, i + 3)) && overlap >= 0.45) {
      return true;
    }
  }
  return false;
}

extension SpeechBindingSelection on SpeechBindings {
  String? modelIdFor(SpeechModelKind kind) => switch (kind) {
    .synthesis => voice?.modelId,
    .recognition => recognitionId,
  };

  bool enabledFor(SpeechModelKind kind) => switch (kind) {
    .synthesis => voice != null && !synthesisPaused,
    .recognition => recognitionId != null && !recognitionPaused,
  };

  SpeechBindings withVoice(SpeechVoiceSelection? selection) => (
    voice: selection,
    recognitionId: recognitionId,
    synthesisPaused:
        selection != null &&
        selection.modelId == voice?.modelId &&
        synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withRecognition(String? id) => (
    voice: voice,
    recognitionId: id,
    synthesisPaused: synthesisPaused,
    recognitionPaused: id != null && id == recognitionId && recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withEnabled(SpeechModelKind kind, bool enabled) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: kind == .synthesis
        ? voice != null && !enabled
        : synthesisPaused,
    recognitionPaused: kind == .recognition
        ? recognitionId != null && !enabled
        : recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withAutoPlay(bool enabled) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: enabled,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withContinuousRecognition(bool enabled) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: enabled,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withVoiceInterrupt(bool enabled) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: enabled,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withWakeWords(Iterable<String> words) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: normalizeWakeWords(words),
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withIdleTimeoutSeconds(int seconds) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: seconds < 0 ? 0 : seconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withSendSilenceSeconds(double seconds) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: clampSpeechSendSilenceSeconds(seconds),
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withMinTriggerLength(int length) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: clampSpeechMinTriggerLength(length),
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withInterruptStopsGeneration(bool enabled) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: enabled,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withMicGain(double gain) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: clampSpeechMicGain(gain),
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withSynthesisGain(double gain) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: clampSpeechSynthesisGain(gain),
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withSynthesisSpeed(double speed) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: clampSpeechSynthesisSpeed(speed),
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withFallbackReadBody(bool enabled) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: enabled,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withIncludeWakeWordInCommand(bool enabled) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: enabled,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: synthesisHardwareId,
  );

  String? hardwareIdFor(SpeechModelKind kind) => switch (kind) {
    .recognition => recognitionHardwareId,
    .synthesis => synthesisHardwareId,
  };

  SpeechBindings withHardwareIdFor(SpeechModelKind kind, String? id) =>
      switch (kind) {
        .recognition => withRecognitionHardwareId(id),
        .synthesis => withSynthesisHardwareId(id),
      };

  SpeechBindings withRecognitionHardwareId(String? id) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: id,
    synthesisHardwareId: synthesisHardwareId,
  );

  SpeechBindings withSynthesisHardwareId(String? id) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: autoPlay,
    continuousRecognition: continuousRecognition,
    voiceInterrupt: voiceInterrupt,
    wakeWords: wakeWords,
    idleTimeoutSeconds: idleTimeoutSeconds,
    sendSilenceSeconds: sendSilenceSeconds,
    minTriggerLength: minTriggerLength,
    interruptStopsGeneration: interruptStopsGeneration,
    micGain: micGain,
    synthesisGain: synthesisGain,
    synthesisSpeed: synthesisSpeed,
    fallbackReadBody: fallbackReadBody,
    includeWakeWordInCommand: includeWakeWordInCommand,
    recognitionHardwareId: recognitionHardwareId,
    synthesisHardwareId: id,
  );

  /// 切换某个类型（识别/合成）的模型时，将该类型下的参数恢复为默认状态。
  SpeechBindings withResetModel(
    SpeechModelKind kind,
    String? modelId, {
    String? hardwareId,
  }) => switch (kind) {
    .synthesis => (
      voice: modelId == null ? null : (modelId: modelId, voice: 0),
      recognitionId: recognitionId,
      synthesisPaused: emptySpeechBindings.synthesisPaused,
      recognitionPaused: recognitionPaused,
      autoPlay: emptySpeechBindings.autoPlay,
      continuousRecognition: continuousRecognition,
      voiceInterrupt: voiceInterrupt,
      wakeWords: wakeWords,
      idleTimeoutSeconds: idleTimeoutSeconds,
      sendSilenceSeconds: sendSilenceSeconds,
      minTriggerLength: minTriggerLength,
      interruptStopsGeneration: interruptStopsGeneration,
      micGain: micGain,
      synthesisGain: emptySpeechBindings.synthesisGain,
      synthesisSpeed: emptySpeechBindings.synthesisSpeed,
      fallbackReadBody: emptySpeechBindings.fallbackReadBody,
      includeWakeWordInCommand: includeWakeWordInCommand,
      recognitionHardwareId: recognitionHardwareId,
      synthesisHardwareId: modelId == null ? null : hardwareId,
    ),
    .recognition => (
      voice: voice,
      recognitionId: modelId,
      synthesisPaused: synthesisPaused,
      recognitionPaused: emptySpeechBindings.recognitionPaused,
      autoPlay: autoPlay,
      continuousRecognition: emptySpeechBindings.continuousRecognition,
      voiceInterrupt: emptySpeechBindings.voiceInterrupt,
      wakeWords: emptySpeechBindings.wakeWords,
      idleTimeoutSeconds: emptySpeechBindings.idleTimeoutSeconds,
      sendSilenceSeconds: emptySpeechBindings.sendSilenceSeconds,
      minTriggerLength: emptySpeechBindings.minTriggerLength,
      interruptStopsGeneration: emptySpeechBindings.interruptStopsGeneration,
      micGain: emptySpeechBindings.micGain,
      synthesisGain: synthesisGain,
      synthesisSpeed: synthesisSpeed,
      fallbackReadBody: fallbackReadBody,
      includeWakeWordInCommand: emptySpeechBindings.includeWakeWordInCommand,
      recognitionHardwareId: modelId == null ? null : hardwareId,
      synthesisHardwareId: synthesisHardwareId,
    ),
  };
}

class SpeechLibrary {
  SpeechLibrary({Iterable<SpeechModel> models = const []})
    : models = List.unmodifiable(models);

  final List<SpeechModel> models;

  SpeechModel? modelFor(SpeechModelKind kind, String? id) => id == null
      ? null
      : models
            .where((model) => model.kind == kind && model.id == id)
            .firstOrNull;

  SpeechModel? recognitionModel(String? id) {
    final model = modelFor(.recognition, id);
    return model != null && model.available ? model : null;
  }

  SpeechModel? synthesisModel(SpeechVoiceSelection? selection) {
    if (selection == null) return null;
    final model = modelFor(.synthesis, selection.modelId);
    return model != null &&
            model.available &&
            selection.voice >= 0 &&
            selection.voice < model.voiceCount
        ? model
        : null;
  }
}

SpeechBindings sanitizeSpeechBindings(
  SpeechBindings bindings,
  SpeechLibrary library,
) {
  var result = bindings;
  if (result.voice != null && library.synthesisModel(result.voice) == null) {
    result = result.withVoice(null);
  }
  if (result.recognitionId != null &&
      library.recognitionModel(result.recognitionId) == null) {
    result = result.withRecognition(null);
  }
  return result;
}
