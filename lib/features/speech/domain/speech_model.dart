/*
 * @Description: 定义离线语音模型、会话绑定和故障类型。
 */

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
  ], resourceDirectory: 'espeak-ng-data');

  const SpeechModelFormat(this.kind, this.files, {this.resourceDirectory});

  final SpeechModelKind kind;
  final List<String> files;
  final String? resourceDirectory;
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
  static const maxBytes = 512 * 1024 * 1024;

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
});

const SpeechBindings emptySpeechBindings = (
  voice: null,
  recognitionId: null,
  synthesisPaused: false,
  recognitionPaused: false,
  autoPlay: true,
  continuousRecognition: true,
  voiceInterrupt: false,
  wakeWords: <String>[],
  idleTimeoutSeconds: defaultSpeechIdleTimeoutSeconds,
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
  );
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
