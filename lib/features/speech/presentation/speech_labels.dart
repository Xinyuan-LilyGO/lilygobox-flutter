/*
 * @Description: 将语音处理故障映射为项目本地化提示。
 */

import '../../../generated/l10n/app_localizations.dart';
import '../domain/speech_model.dart';

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
