import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_tooltip.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/features/speech/data/speech_audio_input.dart';
import 'package:lilygobox/features/speech/data/speech_audio_output.dart';
import 'package:lilygobox/features/speech/data/speech_engine.dart';
import 'package:lilygobox/features/speech/data/speech_model_store.dart';
import 'package:lilygobox/features/speech/domain/speech_model.dart';
import 'package:lilygobox/features/speech/domain/speech_reply_text.dart';
import 'package:lilygobox/features/speech/presentation/speech_chat_controls.dart';
import 'package:lilygobox/features/speech/presentation/speech_model_dialog.dart';
import 'package:lilygobox/features/speech/state/speech_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../assistant/assistant_test_scope.dart';
import 'speech_package_fixture.dart';

class _Microphone implements SpeechAudioInput {
  Completer<void> opened = Completer<void>();
  bool available = true;

  @override
  Future<void> record({
    required Future<bool> stop,
    required void Function() started,
    required void Function(SpeechAudioChunk) onAudio,
    bool continuous = false,
    String? captureDeviceId,
    String? playbackDeviceId,
  }) async {
    if (!available) throw const SpeechFailure(.microphone);
    started();
    if (!opened.isCompleted) opened.complete();
    onAudio((pcm: Uint8List(32000), sampleRate: 16000, channels: 1));
    await stop;
  }
}

class _Engine implements SpeechEngine {
  Completer<void> partial = Completer<void>();
  Completer<void> recognized = Completer<void>();
  Completer<void> continuousStarted = Completer<void>();
  void Function(String)? emitUtterance;
  String? spoken;
  int? spokenVoice;
  SpeechModelFormat? spokenFormat;
  int synthesisCalls = 0;

  @override
  Future<int> check(
    SpeechModelFormat format,
    Directory directory, {
    Future<void>? cancellation,
  }) async => format.kind == .synthesis ? 5 : 0;

  @override
  Future<String> recognize(
    Directory directory,
    Stream<SpeechAudioChunk> audio, {
    void Function(String)? onPartial,
    required Future<void> cancellation,
  }) async {
    await for (final chunk in audio) {
      expect(chunk.sampleRate, 16000);
      expect(chunk.pcm.length, 32000);
      onPartial?.call('你好');
      if (!partial.isCompleted) partial.complete();
    }
    if (!recognized.isCompleted) recognized.complete();
    return '你好，世界。';
  }

  @override
  Future<void> recognizeContinuous(
    Directory directory,
    Stream<SpeechAudioChunk> audio, {
    double silenceSeconds = defaultSpeechSendSilenceSeconds,
    void Function(String)? onPartial,
    required void Function(String) onUtterance,
    required Future<void> cancellation,
  }) async {
    emitUtterance = onUtterance;
    if (!continuousStarted.isCompleted) continuousStarted.complete();
    await for (final _ in audio) {
      if (cancellation == Future<void>.value()) break;
    }
    emitUtterance = null;
  }

  @override
  Future<Uint8List> synthesize(
    SpeechModelFormat format,
    Directory directory,
    String text,
    int voice, {
    double gain = defaultSpeechSynthesisGain,
    double speed = defaultSpeechSynthesisSpeed,
    Future<void>? cancellation,
  }) async {
    synthesisCalls++;
    spoken = text;
    spokenVoice = voice;
    spokenFormat = format;
    return Uint8List(1);
  }

  @override
  Stream<Uint8List> synthesizeStream(
    SpeechModelFormat format,
    Directory directory,
    String text,
    int voice, {
    double gain = defaultSpeechSynthesisGain,
    double speed = defaultSpeechSynthesisSpeed,
    Future<void>? cancellation,
  }) async* {
    yield await synthesize(
      format,
      directory,
      text,
      voice,
      gain: gain,
      speed: speed,
      cancellation: cancellation,
    );
  }

  @override
  Future<void> warmUpSynthesis(
    SpeechModelFormat format,
    Directory directory,
  ) async {}

  @override
  void disposeSynthesisSession() {}
}

class _Speaker implements SpeechAudioOutput {
  Completer<void> started = Completer<void>();
  Completer<void> stopped = Completer<void>();

  @override
  Future<void> play(
    Uint8List wav,
    Future<void> cancellation, {
    String? deviceId,
  }) async {
    if (!started.isCompleted) started.complete();
    await cancellation;
    if (!stopped.isCompleted) stopped.complete();
  }

  @override
  Future<void> playStream(
    Stream<Uint8List> wavChunks,
    Future<void> cancellation, {
    String? deviceId,
  }) async {
    await for (final chunk in wavChunks) {
      await play(chunk, cancellation, deviceId: deviceId);
    }
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

      final parsed = parseSpeechReply(
        'Detailed explanation\n\n```dart\ncode();\n```\n\n<speech>简短口语回复。</speech>',
      );
      expect(parsed.body, 'Detailed explanation\n\n```dart\ncode();\n```');
      expect(parsed.speech, '简短口语回复。');
      expect(parsed.pendingSpeech, isFalse);

      final streaming = parseSpeechReply(
        'Main text\n\n<speech>正在生成口语',
      );
      expect(streaming.body, 'Main text');
      expect(streaming.speech, '正在生成口语');
      expect(streaming.pendingSpeech, isTrue);

      expect(normalizeWakeWords([' 小爱 ', '小爱', '', 'Lily']), [
        '小爱',
        'Lily',
      ]);
      expect(matchSpeechWakeWord('今天天气', const []), (
        matched: true,
        command: '今天天气',
      ));
      expect(matchSpeechWakeWord('随便说点什么', const ['小爱', 'Lily']), (
        matched: false,
        command: '',
      ));
      expect(matchSpeechWakeWord('小爱，帮我查一下', const ['小爱']), (
        matched: true,
        command: '帮我查一下',
      ));
      expect(matchSpeechWakeWord('lily', const ['Lily']), (
        matched: true,
        command: '',
      ));

      final samples = Int16List.fromList([1000, -1000, 20000]);
      final raw = samples.buffer.asUint8List();
      final boosted = Int16List.view(applySpeechPcmGain(raw, 2.0).buffer);
      expect(boosted, [2000, -2000, 32767]);
      final reduced = Int16List.view(applySpeechPcmGain(raw, 0.5).buffer);
      expect(reduced, [500, -500, 10000]);
      expect(identical(applySpeechPcmGain(raw, 1.0), raw), isTrue);
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
    String? systemPrompt;
    final scope = (await tester.runAsync(() async {
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        client: MockClient((request) async {
          requestCount++;
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final messages = (body['messages'] as List).cast<Map<String, Object?>>();
          systemPrompt = messages
              .where((item) => item['role'] == 'system')
              .map((item) => item['content'])
              .whereType<String>()
              .join('\n');
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        '**你好**，欢迎。\n\n```dart\nexample();\n```\n\n<speech>你好，欢迎。</speech>',
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
      for (final format in [
        SpeechModelFormat.bilingualZipformer,
        SpeechModelFormat.kokoroMultiLanguage,
      ]) {
        final source = await speechArchiveFixture(root, format.name, format);
        expect(await provider.import(source), isNull);
      }
      return provider;
    }))!;

    final assistant = scope.provider.forkForWorkspace();
    final otherAssistant = scope.provider.forkForWorkspace();
    addTearDown(assistant.dispose);
    addTearDown(otherAssistant.dispose);

    Future<void> showChat({bool active = true}) => tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: assistant),
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
                  child: Column(
                    children: [
                      Selector<AiAssistantProvider, SpeechBindings>(
                        selector: (_, ai) => ai.speechBindings,
                        builder: (_, bindings, _) => SpeechChatControls(
                          theme: theme.themeData,
                          speech: speech,
                          bindings: bindings,
                          onChanged: assistant.setSpeechBindings,
                          compact: true,
                        ),
                      ),
                      const Expanded(
                        child: AssistantPage(initialDraft: 'Draft'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await showChat();
    await tester.pumpAndSettle();
    final synthesisMenu = find.byKey(
      const ValueKey('speech-chat-menu-synthesis'),
    );
    final recognitionMenu = find.byKey(
      const ValueKey('speech-chat-menu-recognition'),
    );
    final panel = find.byKey(const ValueKey('speech-chat-panel'));
    final back = find.byKey(const ValueKey('speech-chat-back'));
    final mic = find.byKey(const ValueKey('ai-voice-input'));
    final voiceSelect = find.byKey(const ValueKey('speech-agent-voice'));
    final saveVoice = find.byKey(const ValueKey('speech-agent-save'));
    final asr = speech.library.models.singleWhere(
      (model) => model.kind == .recognition,
    );
    final tts = speech.library.models.singleWhere(
      (model) => model.kind == .synthesis,
    );
    Finder option(SpeechModel model) =>
        find.byKey(ValueKey('speech-chat-model-${model.id}'));
    Finder none(SpeechModelKind kind) =>
        find.byKey(ValueKey('speech-chat-none-${kind.name}'));
    Finder toggle(SpeechModelKind kind) =>
        find.byKey(ValueKey('speech-chat-toggle-${kind.name}'));
    void expectSelectedIcon(SpeechModel model) {
      final icon = find.descendant(
        of: option(model),
        matching: find.byType(SpeechModelIcon),
      );
      expect(
        tester.widget<SpeechModelIcon>(icon).backgroundColor,
        theme.themeData.primary,
      );
    }

    bool selected(Finder finder) =>
        tester.widget<MenuItemSurface>(finder).isSelected;
    Finder voiceTooltip(Finder menu, String message) =>
        find.ancestor(of: menu, matching: find.byTooltip(message));
    const synthesisSubtitle =
        'Speech synthesis · Chinese–English Kokoro · 5 voices';
    const recognitionSubtitle =
        'Speech recognition · Chinese–English Zipformer';
    void expectModelOption(SpeechModel model, String subtitle, double height) {
      final row = option(model);
      expect(
        find.descendant(of: row, matching: find.text(subtitle)),
        findsOneWidget,
      );
      expect(voiceTooltip(row, subtitle), findsOneWidget);
      expect(tester.getSize(row).height, height);
    }

    expect(mic, findsNothing);
    expect(speech.library.synthesisModel(assistant.speechVoice), isNull);
    expect(voiceTooltip(synthesisMenu, 'Speech synthesis'), findsOneWidget);
    expect(voiceTooltip(recognitionMenu, 'Speech recognition'), findsOneWidget);
    final synthesisIcon = tester.widget<Icon>(
      find.descendant(
        of: synthesisMenu,
        matching: find.byIcon(Symbols.volume_up_rounded),
      ),
    );
    final recognitionIcon = tester.widget<Icon>(
      find.descendant(
        of: recognitionMenu,
        matching: find.byIcon(Symbols.mic_rounded),
      ),
    );
    expect(synthesisIcon.fill, 1);
    expect(recognitionIcon.fill, 1);
    Color background(Finder menu) => tester
        .widgetList<DecoratedBox>(
          find.descendant(of: menu, matching: find.byType(DecoratedBox)),
        )
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.color != null)
        .color!;
    final hover = theme.themeData.secondaryTextHoverColor;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    expect(background(synthesisMenu), hover.withValues(alpha: 0));
    for (final menu in [synthesisMenu, recognitionMenu]) {
      await mouse.moveTo(tester.getCenter(menu));
      await tester.pump();
      await tester.pump(MenuItemSurface.animationDuration ~/ 2);
      final color = background(menu);
      expect(color.a, inExclusiveRange(0.0, 1.0));
      expect(color.withValues(alpha: 1), hover);
      await tester.pumpAndSettle();
    }
    await mouse.removePointer();

    await tester.tap(synthesisMenu);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(voiceSelect, findsNothing);
    expect(selected(none(.synthesis)), isTrue);
    expect(none(.recognition), findsNothing);
    expect(option(asr), findsNothing);
    expect(tester.getSize(panel).width, 336);
    final optionHeight = tester.getSize(none(.synthesis)).height;
    expectModelOption(tts, synthesisSubtitle, optionHeight);
    final search = find.byKey(const ValueKey('speech-chat-search'));
    await tester.tap(recognitionMenu);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(none(.synthesis), findsNothing);
    expect(selected(none(.recognition)), isTrue);
    expect(tester.getSize(none(.recognition)).height, optionHeight);
    expectModelOption(asr, recognitionSubtitle, optionHeight);
    await tester.enterText(search, 'not-present');
    await tester.pumpAndSettle();
    expect(option(asr), findsNothing);
    expect(find.text('No matching voice models'), findsOneWidget);
    await tester.enterText(search, asr.name.toUpperCase());
    await tester.pumpAndSettle();
    await tester.tap(option(asr));
    await tester.pumpAndSettle();
    expect(back, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text(recognitionSubtitle)),
      findsOneWidget,
    );
    expect(assistant.speechBindings.recognitionId, asr.id);
    expect(assistant.speechVoice, isNull);
    expect(
      voiceTooltip(recognitionMenu, 'Speech recognition · ${asr.name}'),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(toggle(.recognition)).value, isTrue);
    Future<void> waitFor(bool Function() ready) async {
      for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(ready(), isTrue);
    }

    await tester.tap(toggle(.recognition));
    await tester.pumpAndSettle();
    expect(assistant.speechBindings.recognitionId, asr.id);
    expect(assistant.speechRecognitionId, isNull);
    expect(
      find.descendant(
        of: recognitionMenu,
        matching: find.byIcon(Symbols.mic_rounded),
      ),
      findsOneWidget,
    );
    expect(mic, findsNothing);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(selected(option(asr)), isTrue);
    expectSelectedIcon(asr);
    await tester.tap(option(asr));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle(.recognition)).value, isFalse);
    await tester.tap(toggle(.recognition));
    await tester.pumpAndSettle();
    expect(assistant.speechRecognitionId, asr.id);
    expect(assistant.speechContinuousRecognition, isTrue);
    assistant.setSpeechBindings(
      assistant.speechBindings
          .withRecognitionHardwareId('mic-1')
          .withSynthesisHardwareId('spk-1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('speech-chat-recognition-settings')),
    );
    await tester.pumpAndSettle();
    final continuousToggle = find.byKey(const ValueKey('speech-chat-continuous'));
    expect(tester.widget<Switch>(continuousToggle).value, isTrue);
    await tester.tap(continuousToggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-recognition-save')));
    await tester.pumpAndSettle();
    await waitFor(() => !speech.hasCapture);
    microphone.opened = Completer<void>();
    expect(assistant.speechContinuousRecognition, isFalse);
    expect(mic, findsOneWidget);
    await tester.tap(recognitionMenu);
    await tester.pumpAndSettle();
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.enterText(search, '');
    await tester.tap(synthesisMenu);
    await tester.pumpAndSettle();
    expect(option(asr), findsNothing);
    expect(assistant.speechBindings.recognitionId, asr.id);
    await tester.tap(option(tts));
    await tester.pumpAndSettle();
    expect(assistant.speechVoice, (modelId: tts.id, voice: 0));
    expect(
      find.descendant(of: panel, matching: find.text(synthesisSubtitle)),
      findsOneWidget,
    );
    expect(find.textContaining('Model format:'), findsNothing);
    expect(tester.widget<Switch>(toggle(.synthesis)).value, isTrue);
    expect(find.text('Voice 1'), findsNothing);
    final synthesisSettings = find.text('Speech synthesis settings');
    expect(synthesisSettings, findsOneWidget);
    await tester.tap(synthesisSettings);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    final dialog = find.byType(AlertDialog);
    final autoRead = find.byKey(const ValueKey('speech-chat-auto-read'));
    expect(tester.widget<Switch>(autoRead).value, isTrue);
    await tester.tap(autoRead);
    await tester.pumpAndSettle();
    final voiceLabel = find.descendant(
      of: dialog,
      matching: find.text('Voice'),
    );
    final voiceDescription = find.text(
      'The voice this agent uses to read replies aloud.',
    );
    final modelInfo = find.byKey(
      const ValueKey('speech-agent-voice-model-info'),
    );
    expect(
      find.descendant(of: dialog, matching: synthesisSettings),
      findsOneWidget,
    );
    expect(
      find.descendant(of: modelInfo, matching: find.text(tts.name)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: modelInfo, matching: find.text(synthesisSubtitle)),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(modelInfo).dy,
      lessThan(tester.getTopLeft(voiceLabel).dy),
    );
    expect(tester.getTopLeft(modelInfo).dx, tester.getTopLeft(voiceLabel).dx);
    expect(
      tester.getTopLeft(voiceDescription).dx,
      tester.getTopLeft(voiceLabel).dx,
    );
    expect(
      tester.getTopLeft(voiceDescription).dy,
      greaterThan(tester.getBottomLeft(voiceLabel).dy),
    );
    expect(tester.getTopLeft(voiceSelect).dy, tester.getTopLeft(voiceLabel).dy);
    expect(tester.getSize(voiceSelect).width, 220);
    expect(
      tester.getTopLeft(voiceSelect).dx,
      greaterThan(tester.getTopRight(voiceDescription).dx),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(360, 600));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(voiceSelect).dy,
      greaterThan(tester.getBottomLeft(voiceDescription).dy),
    );
    expect(tester.getSize(voiceSelect).width, greaterThan(100));
    expect(
      find.byKey(const ValueKey('speech-agent-voice-preview')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(voiceSelect);
    await tester.tap(voiceSelect);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice 4').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(saveVoice);
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
    await tester.pumpAndSettle();
    expect(assistant.speechVoice, (modelId: tts.id, voice: 3));
    expect(otherAssistant.speechBindings, emptySpeechBindings);
    final synthesisTooltip = 'Speech synthesis · ${tts.name}';
    expect(voiceTooltip(synthesisMenu, synthesisTooltip), findsOneWidget);
    expect(
      voiceTooltip(recognitionMenu, 'Speech recognition · ${asr.name}'),
      findsOneWidget,
    );
    await mouse.addPointer(location: tester.getCenter(synthesisMenu));
    await tester.pump();
    await tester.pump(AppTooltip.waitDuration);
    await tester.pumpAndSettle();
    expect(find.text(synthesisTooltip), findsOneWidget);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    final restoredAssistant = scope.provider.forkForWorkspace();
    addTearDown(restoredAssistant.dispose);
    await tester.tap(synthesisMenu);
    await tester.pumpAndSettle();
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expectSelectedIcon(tts);
    await tester.tap(option(tts));
    await tester.pumpAndSettle();
    expect(assistant.speechAutoPlay, isFalse);
    await tester.tap(toggle(.synthesis));
    await tester.pumpAndSettle();
    expect(assistant.speechVoice, isNull);
    expect(assistant.speechAutoPlay, isFalse);
    expect(assistant.speechBindings.autoPlay, isFalse);
    expect(assistant.speechBindings.voice, (modelId: tts.id, voice: 3));
    expect(assistant.speechRecognitionId, asr.id);
    expect(
      find.descendant(
        of: synthesisMenu,
        matching: find.byIcon(Symbols.volume_up_rounded),
      ),
      findsOneWidget,
    );
    restoredAssistant.restoreWorkspaceConversation(
      assistant.snapshotWorkspaceConversation(),
    );
    expect(restoredAssistant.speechBindings, assistant.speechBindings);
    expect(restoredAssistant.speechVoice, isNull);
    await tester.tap(toggle(.synthesis));
    await tester.pumpAndSettle();
    expect(assistant.speechVoice, (modelId: tts.id, voice: 3));
    expect(assistant.speechAutoPlay, isFalse);
    await tester.tap(synthesisSettings);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-chat-auto-read')));
    await tester.pumpAndSettle();
    await tester.tap(saveVoice);
    await tester.pumpAndSettle();
    expect(assistant.speechAutoPlay, isTrue);
    assistant.setSpeechBindings(
      assistant.speechBindings.withSynthesisHardwareId('spk-1'),
    );
    await tester.pumpAndSettle();

    final input = find.byKey(const ValueKey('ai-message-input'));

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
    engine.recognized = Completer<void>();

    await tapAndWait(mic, microphone.opened);
    await waitFor(() => engine.partial.isCompleted);
    await tester.pumpAndSettle();
    expect(speech.hasCapture, isTrue);
    expect(tester.widget<TextField>(input).readOnly, isTrue);
    expect(tester.widget<TextField>(input).controller!.text, 'Draft\n你好');
    await tapAndWait(mic, engine.recognized);
    await waitFor(
      () =>
          !speech.hasCapture &&
          tester.widget<TextField>(input).controller!.text == 'Draft\n你好，世界。',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).readOnly, isFalse);
    expect(tester.widget<TextField>(input).controller!.text, 'Draft\n你好，世界。');
    expect(requestCount, 0);
    expect(tester.takeException(), isNull);

    const editedDraft = 'Draft\n你好，世界！';
    await tester.enterText(input, editedDraft);
    expect(requestCount, 0);
    await tester.tap(find.byKey(const ValueKey('ai-send-button')));
    for (var attempt = 0; attempt < 80 && assistant.busy; attempt++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();
    expect(requestCount, 1);
    expect(systemPrompt, contains('<speech>'));
    expect(
      assistant.messages.lastWhere((message) => message.role == 'user').content,
      editedDraft,
    );
    final reply = assistant.messages.lastWhere(
      (message) => message.role == 'assistant',
    );
    final voiceCard = find.byKey(ValueKey('ai-voice-card-${reply.id}'));
    expect(voiceCard, findsOneWidget);
    expect(find.textContaining('<speech>'), findsNothing);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final copyVoice = find.byKey(ValueKey('ai-voice-copy-${reply.id}'));
    await tester.ensureVisible(copyVoice);
    await tester.tap(copyVoice);
    await tester.pump();
    expect(copiedText, '你好，欢迎。');
    await tester.pump(const Duration(seconds: 2));
    final play = find.byKey(ValueKey('ai-voice-play-${reply.id}'));
    await tester.ensureVisible(play);
    await waitFor(() => speaker.started.isCompleted);
    await tester.pumpAndSettle();
    expect(engine.spoken, '你好，欢迎。');
    expect(engine.spokenVoice, 3);
    expect(engine.spokenFormat, SpeechModelFormat.kokoroMultiLanguage);
    expect(engine.synthesisCalls, 1);
    await tapAndWait(play, speaker.stopped);
    await tester.pumpAndSettle();

    speaker.started = Completer<void>();
    speaker.stopped = Completer<void>();
    await tapAndWait(play, speaker.started);
    await tester.pumpAndSettle();
    expect(engine.synthesisCalls, 1);
    await tapAndWait(play, speaker.stopped);

    microphone.opened = Completer<void>();
    engine.partial = Completer<void>();
    await tapAndWait(mic, microphone.opened);
    await waitFor(() => engine.partial.isCompleted);
    await showChat(active: false);
    await waitFor(() => !speech.hasCapture);
    await tester.pumpAndSettle();
    expect(speech.hasCapture, isFalse);
    expect(tester.widget<TextField>(input).controller!.text, '你好');
    await showChat();
    await tester.pumpAndSettle();
    await tester.tap(synthesisMenu);
    await tester.pumpAndSettle();
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.tap(none(.synthesis));
    await tester.pumpAndSettle();
    expect(assistant.speechVoice, isNull);
    expect(assistant.speechBindings.recognitionId, asr.id);
    expect(play, findsNothing);
    await tester.tap(recognitionMenu);
    await tester.pumpAndSettle();
    expect(back, findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('speech-chat-recognition-settings')),
    );
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    engine.continuousStarted = Completer<void>();
    final enableContinuous = find.byKey(const ValueKey('speech-chat-continuous'));
    await tester.ensureVisible(enableContinuous);
    await tester.tap(enableContinuous);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('speech-wake-word-input')),
      '小爱',
    );
    final addWakeWord = find.byKey(const ValueKey('speech-wake-word-add'));
    await tester.ensureVisible(addWakeWord);
    await tester.tap(addWakeWord);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-recognition-save')));
    await tester.pumpAndSettle();
    expect(assistant.speechWakeWords, ['小爱']);
    expect(assistant.speechContinuousRecognition, isTrue);
    await waitFor(() => engine.continuousStarted.isCompleted);
    expect(speech.hasCapture, isTrue);
    engine.emitUtterance?.call('无关的背景对话');
    await tester.pump();
    expect(requestCount, 1);
    engine.emitUtterance?.call('小爱，你好呀');
    for (var attempt = 0; attempt < 80 && requestCount < 2; attempt++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    for (var attempt = 0; attempt < 80 && assistant.busy; attempt++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(requestCount, 2);
    expect(
      assistant.messages.lastWhere((message) => message.role == 'user').content,
      '小爱，你好呀',
    );

    await tester.tap(recognitionMenu);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('speech-chat-recognition-settings')),
    );
    await tester.pumpAndSettle();
    final removeWakeWord = find.byKey(
      const ValueKey('speech-wake-word-remove-小爱'),
    );
    await tester.ensureVisible(removeWakeWord);
    await tester.tap(removeWakeWord);
    await tester.pumpAndSettle();
    final continuousSwitch = find.byKey(
      const ValueKey('speech-chat-continuous'),
    );
    await tester.ensureVisible(continuousSwitch);
    await tester.tap(continuousSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-recognition-save')));
    await tester.pumpAndSettle();
    expect(assistant.speechWakeWords, isEmpty);
    expect(assistant.speechContinuousRecognition, isFalse);
    await tester.tap(recognitionMenu);
    await tester.pumpAndSettle();
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.tap(none(.recognition));
    await tester.pumpAndSettle();
    expect(mic, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.takeException(), isNull);

    var fieldBindings = emptySpeechBindings;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: speech),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, update) => Column(
                children: [
                  SpeechChatControls(
                    theme: theme.themeData,
                    speech: speech,
                    bindings: fieldBindings,
                    onChanged: (value) => update(() => fieldBindings = value),
                    compact: false,
                    kinds: const [.synthesis],
                    fieldStyle: true,
                  ),
                  SpeechChatControls(
                    theme: theme.themeData,
                    speech: speech,
                    bindings: fieldBindings,
                    onChanged: (value) => update(() => fieldBindings = value),
                    compact: false,
                    kinds: const [.recognition],
                    fieldStyle: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No synthesis'), findsOneWidget);
    expect(find.text('No recognition'), findsOneWidget);
    await tester.tap(synthesisMenu);
    await tester.pumpAndSettle();
    await tester.tap(option(tts));
    await tester.pumpAndSettle();
    expect(fieldBindings.voice, (modelId: tts.id, voice: 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(recognitionMenu);
    await tester.pumpAndSettle();
    await tester.tap(option(asr));
    await tester.pumpAndSettle();
    expect(fieldBindings.recognitionId, asr.id);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }, variant: themes);

  testWidgets('streaming speech plays before body completes and card sits above body', (
    tester,
  ) async {
    final microphone = _Microphone();
    final engine = _Engine();
    final speaker = _Speaker();
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final split = SplitViewProvider();
    final shell = AppShellProvider();
    for (final notifier in [theme, language, split, shell]) {
      addTearDown(notifier.dispose);
    }

    final firstChunk = Completer<void>();
    final finishStream = Completer<void>();
    final scope = (await tester.runAsync(() async {
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/chat/completions')) {
            final controller = StreamController<List<int>>();
            controller.add(
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"<speech>先说这句。</speech>\\n"}}]}\n\n',
              ),
            );
            unawaited(
              firstChunk.future.then((_) async {
                controller.add(
                  utf8.encode(
                    'data: {"choices":[{"delta":{"content":"这里是后续很长的正文内容。"}}]}\n\n',
                  ),
                );
                await finishStream.future;
                controller.add(utf8.encode('data: [DONE]\n\n'));
                await controller.close();
              }),
            );
            return http.StreamedResponse(
              controller.stream,
              200,
              headers: {'content-type': 'text/event-stream; charset=utf-8'},
            );
          }
          return http.StreamedResponse(const Stream.empty(), 404);
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
      final root = await Directory.systemTemp.createTemp('speech-stream-');
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
      final source = await speechArchiveFixture(
        root,
        SpeechModelFormat.kokoroMultiLanguage.name,
        SpeechModelFormat.kokoroMultiLanguage,
      );
      expect(await provider.import(source), isNull);
      return provider;
    }))!;

    final assistant = scope.provider.forkForWorkspace();
    addTearDown(assistant.dispose);
    final tts = speech.library.models.single;
    assistant.setSpeechBindings(
      emptySpeechBindings
          .withVoice((modelId: tts.id, voice: 0))
          .withSynthesisHardwareId('spk-1')
          .withAutoPlay(true),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: language),
          ChangeNotifierProvider.value(value: split),
          ChangeNotifierProvider.value(value: shell),
          ChangeNotifierProvider.value(value: assistant),
          ChangeNotifierProvider.value(value: speech),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AssistantPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sending = assistant.sendMessage('你好');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 100 && engine.synthesisCalls == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    expect(assistant.busy, isTrue);
    expect(assistant.speechVoice, isNotNull);
    expect(assistant.speechAutoPlay, isTrue);
    expect(speech.library.synthesisModel(assistant.speechVoice), isNotNull);
    expect(assistant.messages.last.content, contains('<speech>先说这句。</speech>'));
    expect(find.text('先说这句。'), findsOneWidget);
    expect(
      find.byKey(ValueKey('ai-voice-card-${assistant.messages.last.id}')),
      findsOneWidget,
    );
    expect(speech.hasPlayback || engine.synthesisCalls == 1, isTrue);
    expect(engine.synthesisCalls, 1);
    expect(engine.spoken, '先说这句。');

    firstChunk.complete();
    for (var i = 0;
        i < 50 &&
            !assistant.messages.last.content.contains('这里是后续很长的正文内容');
        i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
    final cardTop = tester
        .getTopLeft(
          find.byKey(ValueKey('ai-voice-card-${assistant.messages.last.id}')),
        )
        .dy;
    final bodyTop = tester
        .getTopLeft(
          find
              .byWidgetPredicate(
                (widget) => widget.runtimeType.toString() == 'ChatMessageBody',
              )
              .last,
        )
        .dy;
    expect(cardTop, lessThan(bodyTop));

    finishStream.complete();
    for (var i = 0; i < 50 && assistant.busy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(assistant.busy, isFalse);
  });

  testWidgets(
    'hardware selector inside recognition and synthesis cards binds independently',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('speech_hardware_test_'),
      );
      addTearDown(() => root!.delete(recursive: true));
      final store = SpeechModelStore(directory: root!);
      const tts = SpeechModel(
        id: 'tts-1',
        format: .chineseVits,
        name: 'TTS 1',
        voiceCount: 1,
      );
      const asr = SpeechModel(
        id: 'asr-1',
        format: .bilingualZipformer,
        name: 'ASR 1',
        voiceCount: 1,
      );
      final speech = SpeechProvider(
        store: store,
        engine: _Engine(),
        output: _Speaker(),
        input: _Microphone(),
      );
      await tester.runAsync(speech.load);
      addTearDown(speech.dispose);

      var bindings = emptySpeechBindings
          .withVoice((modelId: tts.id, voice: 0))
          .withRecognition(asr.id);
      final theme = ThemeProvider();
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SpeechChatControls(
                theme: theme.themeData,
                speech: speech,
                bindings: bindings,
                onChanged: (next) => setState(() => bindings = next),
                compact: false,
                hardwareOwnersFor: (_) => const {
                  'mic-1': (id: 'agent-a', title: 'Agent A', busy: false),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top bar no longer has a standalone hardware chip.
      expect(
        find.byKey(const ValueKey('speech-chat-menu-hardware')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('speech-chat-menu-recognition')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('speech-chat-menu-synthesis')),
        findsOneWidget,
      );
    },
  );

  test(
    'multiple conversations with different hardware capture and play concurrently',
    () async {
      final root = await Directory.systemTemp.createTemp('speech_multi_test_');
      addTearDown(() => root.delete(recursive: true));
      final store = SpeechModelStore(directory: root);
      final ttsArchive = await speechArchiveFixture(
        root,
        SpeechModelFormat.kokoroMultiLanguage.name,
        SpeechModelFormat.kokoroMultiLanguage,
      );
      final asrArchive = await speechArchiveFixture(
        root,
        SpeechModelFormat.bilingualZipformer.name,
        SpeechModelFormat.bilingualZipformer,
      );
      final speech = SpeechProvider(
        store: store,
        engine: _Engine(),
        output: _Speaker(),
        input: _Microphone(),
      );
      await speech.load();
      expect(await speech.import(ttsArchive), isNull);
      expect(await speech.import(asrArchive), isNull);
      addTearDown(speech.dispose);

      final tts = speech.library.models.firstWhere(
        (m) => m.kind == .synthesis,
      );
      final asr = speech.library.models.firstWhere(
        (m) => m.kind == .recognition,
      );
      final first = SpeechConversation(
        agent: Object(),
        recognitionHardwareId: 'mic-1',
        synthesisHardwareId: 'spk-1',
      );
      final second = SpeechConversation(
        agent: Object(),
        recognitionHardwareId: 'mic-2',
        synthesisHardwareId: 'spk-2',
      );

      final listen1 = speech.startContinuousListening(
        first,
        modelId: asr.id,
        onUtterance: (_) {},
      );
      final listen2 = speech.startContinuousListening(
        second,
        modelId: asr.id,
        onUtterance: (_) {},
      );
      final play1 = speech.play(
        first,
        '第一路播报',
        selection: (modelId: tts.id, voice: 0),
        allowContinuousCapture: true,
      );
      final play2 = speech.play(
        second,
        '第二路播报',
        selection: (modelId: tts.id, voice: 0),
        allowContinuousCapture: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(speech.hasCaptureFor(first), isTrue);
      expect(speech.hasCaptureFor(second), isTrue);
      expect(speech.isPlaying(first), isTrue);
      expect(speech.isPlaying(second), isTrue);

      speech.stopConversation(first);
      speech.stopConversation(second);
      speech.stopPlayback(first);
      speech.stopPlayback(second);
      await Future.wait([listen1, listen2, play1, play2]);
    },
  );
}
