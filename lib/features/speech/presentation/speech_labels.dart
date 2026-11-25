/*
 * @Description: 将语音处理故障映射为项目本地化提示。
 */

import '../../../generated/l10n/app_localizations.dart';
import '../domain/speech_model.dart';

const _kokoroVoiceNames = [
  'af_alloy',
  'af_aoede',
  'af_bella',
  'af_heart',
  'af_jessica',
  'af_kore',
  'af_nicole',
  'af_nova',
  'af_river',
  'af_sarah',
  'af_sky',
  'am_adam',
  'am_echo',
  'am_eric',
  'am_fenrir',
  'am_liam',
  'am_michael',
  'am_onyx',
  'am_puck',
  'am_santa',
  'bf_alice',
  'bf_emma',
  'bf_isabella',
  'bf_lily',
  'bm_daniel',
  'bm_fable',
  'bm_george',
  'bm_lewis',
  'ef_dora',
  'em_alex',
  'ff_siwis',
  'hf_alpha',
  'hf_beta',
  'hm_omega',
  'hm_psi',
  'if_sara',
  'im_nicola',
  'jf_alpha',
  'jf_gongitsune',
  'jf_nezumi',
  'jf_tebukuro',
  'jm_kumo',
  'pf_dora',
  'pm_alex',
  'pm_santa',
  'zf_xiaobei',
  'zf_xiaoni',
  'zf_xiaoxiao',
  'zf_xiaoyi',
  'zm_yunjian',
  'zm_yunxi',
  'zm_yunxia',
  'zm_yunyang',
  'em_santa',
];

const _zhLlVoiceNames = [
  'suyingxue',
  'gunian',
  'fushiyu',
  'bingjiao',
  'bazong',
];

String speechKindLabel(AppLocalizations l10n, SpeechModelKind kind) =>
    switch (kind) {
      .recognition => l10n.speechRecognition,
      .synthesis => l10n.speechSynthesis,
    };

String speechModelSubtitle(AppLocalizations l10n, SpeechModel model) =>
    switch (model) {
      SpeechModel(format: .chineseVits, :final voiceCount) =>
        l10n.speechChineseVitsCardSubtitle(voiceCount),
      SpeechModel(format: .kokoroMultiLanguage, :final voiceCount) =>
        l10n.speechKokoroCardSubtitle(voiceCount),
      SpeechModel(format: .bilingualZipformer) =>
        l10n.speechBilingualZipformerCardSubtitle,
    };

String? speechVoiceName(SpeechModel model, int voice) {
  final names = switch (model) {
    SpeechModel(
      format: .chineseVits,
      id: '24ace828d3627daa8b18c93eea344967a73ca7c4566ffdff7e57e0266824c99a',
      voiceCount: 5,
    ) =>
      _zhLlVoiceNames,
    SpeechModel(
      format: .kokoroMultiLanguage,
      id: '28fe21e73421fc31f0f2d553945964d835f450b95c870dc69a6c0ade6e911cc4',
      voiceCount: 54,
    ) =>
      _kokoroVoiceNames,
    _ => null,
  };
  return names != null && voice >= 0 && voice < names.length
      ? names[voice]
      : null;
}

String speechVoiceLabel(AppLocalizations l10n, SpeechModel model, int voice) =>
    switch (speechVoiceName(model, voice)) {
      final name? => l10n.speechVoiceNamed(voice + 1, name),
      null => l10n.speechVoiceNumber(voice + 1),
    };

String speechFormatLabel(AppLocalizations l10n, SpeechModelFormat format) =>
    l10n.speechModelFormat(switch (format) {
      .bilingualZipformer => l10n.speechRecognitionFormat,
      .chineseVits => l10n.speechSynthesisFormat,
      .kokoroMultiLanguage => l10n.speechKokoroFormat,
    });

String speechErrorLabel(AppLocalizations l10n, SpeechFailureReason reason) =>
    switch (reason) {
      .unsupportedModel => l10n.speechUnsupportedModel,
      .missingFiles => l10n.speechMissingFiles,
      .invalidModel => l10n.speechInvalidModel,
      .duplicateModel => l10n.speechDuplicateModel,
      .invalidPackage => l10n.speechInvalidPackage,
      .packageTooLarge => l10n.speechPackageTooLarge,
      .exportFailed => l10n.speechExportFailed,
      .storage => l10n.speechStorageError,
      .engine => l10n.speechEngineError,
      .microphone => l10n.speechMicrophoneError,
      .noSpeech => l10n.speechNoSpeech,
      .playback => l10n.speechPlaybackError,
    };
