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

typedef SpeechVoiceSelection = ({String modelId, int voice});
typedef SpeechBindings = ({
  SpeechVoiceSelection? voice,
  String? recognitionId,
  bool synthesisPaused,
  bool recognitionPaused,
  bool autoPlay,
});

const SpeechBindings emptySpeechBindings = (
  voice: null,
  recognitionId: null,
  synthesisPaused: false,
  recognitionPaused: false,
  autoPlay: true,
);

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
  );

  SpeechBindings withRecognition(String? id) => (
    voice: voice,
    recognitionId: id,
    synthesisPaused: synthesisPaused,
    recognitionPaused: id != null && id == recognitionId && recognitionPaused,
    autoPlay: autoPlay,
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
  );

  SpeechBindings withAutoPlay(bool enabled) => (
    voice: voice,
    recognitionId: recognitionId,
    synthesisPaused: synthesisPaused,
    recognitionPaused: recognitionPaused,
    autoPlay: enabled,
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
