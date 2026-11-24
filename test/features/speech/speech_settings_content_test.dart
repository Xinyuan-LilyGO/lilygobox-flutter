import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/speech/data/speech_audio_output.dart';
import 'package:lilygobox/features/speech/data/speech_engine.dart';
import 'package:lilygobox/features/speech/data/speech_model_store.dart';
import 'package:lilygobox/features/speech/domain/speech_model.dart';
import 'package:lilygobox/features/speech/presentation/speech_settings_content.dart';
import 'package:lilygobox/features/speech/state/speech_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'speech_package_fixture.dart';

class _Engine implements SpeechEngine {
  @override
  Future<int> check(SpeechModelFormat format, Directory directory) async => 5;

  @override
  Future<String> recognize(
    Directory directory,
    Uint8List pcm, {
    int sampleRate = speechSampleRate,
    int channels = 1,
    Future<void>? cancellation,
  }) async => '';

  @override
  Future<Uint8List> synthesize(
    Directory directory,
    String text,
    int voice, {
    Future<void>? cancellation,
  }) async => Uint8List(1);
}

class _Output implements SpeechAudioOutput {
  @override
  Future<void> play(Uint8List wav, Future<void> cancellation) => cancellation;
}

void main() {
  testWidgets('voice model rows fit both themes and stop an active preview', (
    tester,
  ) async {
    final speech = (await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('speech-settings-');
      addTearDown(() => root.delete(recursive: true));
      const format = SpeechModelFormat.chineseVits;
      final source = await speechArchiveFixture(
        root,
        'Chinese voice model',
        format,
      );
      final provider = SpeechProvider(
        store: SpeechModelStore(
          directory: Directory(path.join(root.path, 'store')),
        ),
        engine: _Engine(),
        output: _Output(),
      );
      addTearDown(provider.dispose);
      await provider.load();
      expect(await provider.import(source), isNull);
      return provider;
    }))!;
    final model = speech.library.models.single;
    final preview = find.byKey(ValueKey('speech-preview-${model.id}'));

    final themes = ThemeProvider();
    addTearDown(themes.dispose);
    for (final theme in themes.allThemes) {
      for (final width in [760.0, 320.0]) {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: ChangeNotifierProvider.value(
                      value: speech,
                      child: SpeechSettingsContent(theme: theme),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Chinese voice model'), findsNWidgets(2));
        expect(
          find.byKey(ValueKey('speech-export-${model.id}')),
          findsOneWidget,
        );
        await tester.ensureVisible(preview);
        await tester.runAsync(() async => tester.tap(preview));
        await tester.pumpAndSettle();
        expect(find.text('Stop playback'), findsOneWidget);
        await tester.tap(preview);
        await tester.pumpAndSettle();
        expect(find.text('Preview'), findsOneWidget);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
