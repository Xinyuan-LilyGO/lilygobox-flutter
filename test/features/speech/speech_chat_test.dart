import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/speech/data/speech_audio_input.dart';
import 'package:lilygobox/features/speech/data/speech_audio_output.dart';
import 'package:lilygobox/features/speech/data/speech_engine.dart';
import 'package:lilygobox/features/speech/data/speech_model_store.dart';
import 'package:lilygobox/features/speech/domain/speech_model.dart';
import 'package:lilygobox/features/speech/domain/speech_reply_text.dart';
import 'package:lilygobox/features/speech/state/speech_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../assistant/assistant_test_scope.dart';
import 'speech_package_fixture.dart';

class _Microphone implements SpeechAudioInput {
  Completer<void> opened = Completer<void>();
  bool available = true;

  @override
  Future<SpeechRecording?> record({
    required Future<bool> stop,
    required void Function() started,
  }) async {
    if (!available) throw const SpeechFailure(.microphone);
    started();
    opened.complete();
    if (!await stop) return null;
    return (pcm: Uint8List(32000), sampleRate: 16000, channels: 1);
  }
}

class _Engine implements SpeechEngine {
  final recognized = Completer<void>();
  String? spoken;

  @override
  Future<int> check(SpeechModelFormat format, Directory directory) async =>
      format.kind == .synthesis ? 5 : 0;

  @override
  Future<String> recognize(
    Directory directory,
    Uint8List pcm, {
    int sampleRate = speechSampleRate,
    int channels = 1,
    Future<void>? cancellation,
  }) async {
    expect(sampleRate, 16000);
    expect(pcm.length, 32000);
    recognized.complete();
    return '你好，世界。';
  }

  @override
  Future<Uint8List> synthesize(
    Directory directory,
    String text,
    int voice, {
    Future<void>? cancellation,
  }) async {
    spoken = text;
    return Uint8List(1);
  }
}

class _Speaker implements SpeechAudioOutput {
  final started = Completer<void>();
  final stopped = Completer<void>();

  @override
  Future<void> play(Uint8List wav, Future<void> cancellation) async {
    started.complete();
    await cancellation;
    stopped.complete();
  }
}

void main() {
  final themes = ValueVariant<ThemeType>(ThemeType.values.toSet());

  test(
    'speech text retains visible prose, without code, image or link targets',
    () {
      const source =
          '## Heading\n\nRead **this** [link](https://example.test).'
          '\n\n```dart\nsecretCode();\n```\n\n![image](image.png)';
      final result = speechReplyText(source);
      expect(result, startsWith('Heading\nRead this link.'));
      expect(result, isNot(contains('secretCode')));
      expect(result, isNot(contains('https://')));
      expect(speechReplyText('```text\nOnly code\n```'), isEmpty);
    },
  );

  testWidgets('voice fills the draft, sends only on click, plays and stops', (
    tester,
  ) async {
    final microphone = _Microphone();
    final engine = _Engine();
    final speaker = _Speaker();
    final theme = ThemeProvider()..setTheme(themes.currentValue!);
    final language = LanguageProvider();
    final split = SplitViewProvider();
    final shell = AppShellProvider();
    for (final notifier in [theme, language, split, shell]) {
      addTearDown(notifier.dispose);
    }
    var requestCount = 0;
    final scope = (await tester.runAsync(() async {
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        client: MockClient((request) async {
          requestCount++;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '**你好**，欢迎。\n\n```dart\nexample();\n```',
                    'reasoning_content': 'hidden reasoning',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(scope.dispose);
      await scope.provider.initialized;
      await scope.provider.saveService(
        name: 'Test',
        protocol: .openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      return scope;
    }))!;
    final speech = (await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('speech-chat-');
      addTearDown(() => root.delete(recursive: true));
      final provider = SpeechProvider(
        store: SpeechModelStore(
          directory: Directory(path.join(root.path, 'store')),
        ),
        engine: engine,
        input: microphone,
        output: speaker,
      );
      addTearDown(provider.dispose);
      await provider.load();
      for (final format in SpeechModelFormat.values) {
        final source = await speechArchiveFixture(root, format.name, format);
        expect(await provider.import(source), isNull);
      }
      return provider;
    }))!;

    Future<void> showChat({bool active = true}) => tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: scope.provider),
          ChangeNotifierProvider.value(value: speech),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 330,
                child: TickerMode(
                  enabled: active,
                  child: const AssistantPage(initialDraft: 'Draft'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await showChat();
    await tester.pumpAndSettle();
    final mic = find.byKey(const ValueKey('ai-voice-input'));
    final input = find.byKey(const ValueKey('ai-message-input'));
    Future<void> waitFor(bool Function() ready) async {
      for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(ready(), isTrue);
    }

    Future<void> tapAndWait(Finder target, Completer<void> signal) async {
      await tester.runAsync(() => tester.tap(target));
      await waitFor(() => signal.isCompleted);
    }

    final l10n = AppLocalizations.of(tester.element(input));
    final microphoneError = find.text(l10n.speechMicrophoneError);
    microphone.available = false;
    await tester.runAsync(() => tester.tap(mic));
    await waitFor(() => microphoneError.evaluate().isNotEmpty);
    expect(speech.hasCapture, isFalse);
    expect(tester.widget<TextField>(input).controller!.text, 'Draft');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    microphone.available = true;

    await tapAndWait(mic, microphone.opened);
    await tester.pumpAndSettle();
    expect(speech.hasCapture, isTrue);
    await tapAndWait(mic, engine.recognized);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, 'Draft\n你好，世界。');
    expect(requestCount, 0);
    expect(tester.takeException(), isNull);

    const editedDraft = 'Draft\n你好，世界！';
    await tester.enterText(input, editedDraft);
    expect(requestCount, 0);
    await tester.tap(find.byKey(const ValueKey('ai-send-button')));
    for (var attempt = 0; attempt < 80 && scope.provider.busy; attempt++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();
    expect(requestCount, 1);
    expect(
      scope.provider.messages
          .lastWhere((message) => message.role == 'user')
          .content,
      editedDraft,
    );
    final reply = scope.provider.messages.lastWhere(
      (message) => message.role == 'assistant',
    );
    final play = find.byKey(ValueKey('ai-voice-play-${reply.id}'));
    await tester.ensureVisible(play);
    await tapAndWait(play, speaker.started);
    await tester.pumpAndSettle();
    expect(engine.spoken, '你好，欢迎。');
    await tapAndWait(play, speaker.stopped);

    microphone.opened = Completer<void>();
    await tapAndWait(mic, microphone.opened);
    await showChat(active: false);
    await waitFor(() => !speech.hasCapture);
    await tester.pumpAndSettle();
    expect(speech.hasCapture, isFalse);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: themes);
}
