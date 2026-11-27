import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/speech/domain/speech_model.dart';
import 'package:lilygobox/features/speech/presentation/speech_labels.dart';
import 'package:lilygobox/generated/l10n/app_localizations_zh.dart';

void main() {
  test('speechVoiceLabel uses uniform numbered labels for all synthesis models', () {
    final l10n = AppLocalizationsZh();
    const vits = SpeechModel(
      id: 'vits-model',
      format: .chineseVits,
      name: 'vits-zh',
      voiceCount: 5,
    );
    const kokoro = SpeechModel(
      id: 'kokoro-model',
      format: .kokoroMultiLanguage,
      name: 'kokoro-int8-multi-lang-v1_1',
      voiceCount: 103,
    );

    expect(speechVoiceLabel(l10n, vits, 0), l10n.speechVoiceNumber(1));
    expect(speechVoiceLabel(l10n, kokoro, 3), l10n.speechVoiceNumber(4));
  });
}
