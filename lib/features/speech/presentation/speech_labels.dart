/*
 * @Description: 将语音处理故障映射为项目本地化提示。
 */

import '../../../generated/l10n/app_localizations.dart';
import '../domain/speech_model.dart';

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
      SpeechModel(format: .matchaZh, :final voiceCount) =>
        l10n.speechMatchaCardSubtitle(voiceCount),
      SpeechModel(format: .bilingualZipformer) =>
        l10n.speechBilingualZipformerCardSubtitle,
      SpeechModel(format: .streamingParaformer) =>
        l10n.speechStreamingParaformerCardSubtitle,
      SpeechModel(format: .senseVoice) => l10n.speechSenseVoiceCardSubtitle,
    };

String speechVoiceLabel(AppLocalizations l10n, SpeechModel model, int voice) =>
    l10n.speechVoiceNumber(voice + 1);

String speechFormatLabel(AppLocalizations l10n, SpeechModelFormat format) =>
    l10n.speechModelFormat(switch (format) {
      .bilingualZipformer => l10n.speechRecognitionFormat,
      .streamingParaformer => l10n.speechStreamingParaformerFormat,
      .senseVoice => l10n.speechSenseVoiceFormat,
      .chineseVits => l10n.speechSynthesisFormat,
      .kokoroMultiLanguage => l10n.speechKokoroFormat,
      .matchaZh => l10n.speechMatchaFormat,
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
