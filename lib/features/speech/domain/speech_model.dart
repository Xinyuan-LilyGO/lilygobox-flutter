/*
 * @Description: 定义离线语音模型、默认选项和故障类型。
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
  ]);

  const SpeechModelFormat(this.kind, this.files);

  final SpeechModelKind kind;
  final List<String> files;
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

class SpeechLibrary {
  SpeechLibrary({
    Iterable<SpeechModel> models = const [],
    this.recognitionId,
    this.synthesisId,
    this.voice = 0,
  }) : models = List.unmodifiable(models);

  final List<SpeechModel> models;
  final String? recognitionId;
  final String? synthesisId;
  final int voice;

  String? selectedId(SpeechModelKind kind) => switch (kind) {
    .recognition => recognitionId,
    .synthesis => synthesisId,
  };

  SpeechModel? selectedModel(SpeechModelKind kind) => models
      .where((model) => model.id == selectedId(kind) && model.available)
      .firstOrNull;
}
