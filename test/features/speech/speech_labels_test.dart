import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/speech/domain/speech_model.dart';
import 'package:lilygobox/features/speech/presentation/speech_labels.dart';

void main() {
  test('VITS uses the speaker IDs from the reference training config', () {
    const model = SpeechModel(
      id: '24ace828d3627daa8b18c93eea344967a73ca7c4566ffdff7e57e0266824c99a',
      format: .chineseVits,
      name: 'Renamed reference VITS model',
      voiceCount: 5,
    );

    expect(
      [
        for (var voice = 0; voice < model.voiceCount; voice++)
          speechVoiceName(model, voice),
      ],
      ['suyingxue', 'gunian', 'fushiyu', 'bingjiao', 'bazong'],
    );
  });

  test('Kokoro preserves the voice order recorded in the ONNX metadata', () {
    const model = SpeechModel(
      id: '28fe21e73421fc31f0f2d553945964d835f450b95c870dc69a6c0ade6e911cc4',
      format: .kokoroMultiLanguage,
      name: 'kokoro-multi-lang-v1_0',
      voiceCount: 54,
    );

    expect(speechVoiceName(model, 0), 'af_alloy');
    expect(speechVoiceName(model, 44), 'pm_santa');
    expect(speechVoiceName(model, 53), 'em_santa');
  });

  test('unverified models are not labeled by speaker count or file name', () {
    const model = SpeechModel(
      id: 'other-model',
      format: .chineseVits,
      name: 'sherpa-onnx-vits-zh-ll',
      voiceCount: 5,
    );

    expect(speechVoiceName(model, 0), isNull);
  });
}
