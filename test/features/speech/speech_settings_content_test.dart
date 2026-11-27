import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/core/widgets/dialog_style.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/settings/presentation/widgets/content_layout.dart';
import 'package:lilygobox/features/speech/data/speech_audio_output.dart';
import 'package:lilygobox/features/speech/data/speech_audio_input.dart';
import 'package:lilygobox/features/speech/data/speech_engine.dart';
import 'package:lilygobox/features/speech/data/speech_model_store.dart';
import 'package:lilygobox/features/speech/domain/speech_model.dart';
import 'package:lilygobox/features/speech/presentation/speech_model_dialog.dart';
import 'package:lilygobox/features/speech/presentation/speech_settings_content.dart';
import 'package:lilygobox/features/speech/state/speech_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../assistant/assistant_test_scope.dart';
import 'speech_package_fixture.dart';

class _Engine implements SpeechEngine {
  int? previewVoice;

  @override
  Future<int> check(
    SpeechModelFormat format,
    Directory directory, {
    Future<void>? cancellation,
  }) async => format.kind == .synthesis ? 5 : 0;

  @override
  Future<String> recognize(
    SpeechModelFormat format,
    Directory directory,
    Stream<SpeechAudioChunk> audio, {
    void Function(String)? onPartial,
    required Future<void> cancellation,
  }) async {
    await for (final _ in audio) {
      onPartial?.call('recognized test');
    }
    return 'recognized test phrase';
  }

  @override
  Future<Uint8List> synthesize(
    SpeechModelFormat format,
    Directory directory,
    String text,
    int voice, {
    double speed = 1.0,
    double gain = 1.0,
    Future<void>? cancellation,
  }) async {
    previewVoice = voice;
    return Uint8List(1);
  }

  @override
  Stream<Uint8List> synthesizeStream(
    SpeechModelFormat format,
    Directory directory,
    String text,
    int voice, {
    double speed = 1.0,
    double gain = 1.0,
    Future<void>? cancellation,
  }) async* {
    yield await synthesize(
      format,
      directory,
      text,
      voice,
      speed: speed,
      gain: gain,
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

  @override
  Future<void> recognizeContinuous(
    SpeechModelFormat format,
    Directory directory,
    Stream<SpeechAudioChunk> audio, {
    double silenceSeconds = defaultSpeechSendSilenceSeconds,
    void Function(String)? onPartial,
    required void Function(String) onUtterance,
    required Future<void> cancellation,
  }) async {}
}

class _Input implements SpeechAudioInput {
  bool? lastStop;

  @override
  Future<void> record({
    required Future<bool> stop,
    required void Function() started,
    required void Function(SpeechAudioChunk) onAudio,
    bool continuous = false,
    String? captureDeviceId,
    String? playbackDeviceId,
  }) async {
    lastStop = null;
    started();
    onAudio((
      pcm: Uint8List.fromList([1, 2]),
      sampleRate: speechSampleRate,
      channels: 1,
    ));
    lastStop = await stop;
  }
}

class _Output implements SpeechAudioOutput {
  bool playing = false;

  @override
  Future<void> play(
    Uint8List wav,
    Future<void> cancellation, {
    String? deviceId,
  }) async {
    playing = true;
    await cancellation;
    playing = false;
  }

  @override
  Future<void> playStream(
    Stream<Uint8List> wavChunks,
    Future<void> cancellation, {
    String? deviceId,
  }) async {
    await for (final chunk in wavChunks) {
      await play(chunk, cancellation, deviceId: deviceId);
      break;
    }
  }
}

class _FileSelector extends FileSelectorPlatform {
  _FileSelector(this.destination);

  final String destination;
  int saveCalls = 0;
  String? suggestedName;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    saveCalls++;
    suggestedName = options.suggestedName;
    return FileSaveLocation(destination);
  }
}

void main() {
  testWidgets(
    'single-column library adapts, exports selected models, and previews separately',
    (tester) async {
      final engine = _Engine();
      final output = _Output();
      final input = _Input();
      final (speech, source) = (await tester.runAsync(() async {
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
          engine: engine,
          output: output,
          input: input,
        );
        addTearDown(provider.dispose);
        await provider.load();
        return (provider, source);
      }))!;

      final themes = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final split = SplitViewProvider();
      for (final notifier in [themes, language, shell, split]) {
        addTearDown(notifier.dispose);
      }
      final (workspaces, agent, otherAgent) = (await tester.runAsync(() async {
        final scope = await createAssistantTestScope(
          theme: themes,
          language: language,
          shell: shell,
          splitView: split,
        );
        addTearDown(scope.dispose);
        await scope.provider.saveService(
          name: 'Test',
          protocol: .openAiChatCompletions,
          baseUrl: 'https://example.test/v1',
          models: ['test'],
          apiKey: 'key',
        );
        final workspaces = AiWorkspaceProvider(scope.provider);
        addTearDown(workspaces.dispose);
        await workspaces.initialized;
        final agent = await workspaces.createPrimary(
          title: 'Voice agent',
          task: 'Voice settings test',
        );
        final otherAgent = await workspaces.createPrimary(
          title: 'Other agent',
          task: 'Voice settings test',
        );
        return (workspaces, agent, otherAgent);
      }))!;
      Future<void> showPage(
        AppTheme theme,
        double width, {
        Locale locale = const Locale('en'),
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: appLocalizationDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(width == 320 ? 1.5 : 1),
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: MultiProvider(
                      providers: [
                        ChangeNotifierProvider.value(value: speech),
                        ChangeNotifierProvider.value(value: workspaces),
                      ],
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
      }

      await showPage(themes.allThemes.first, 760);
      final importButton = find.byKey(const ValueKey('speech-import'));
      expect(
        find.ancestor(of: importButton, matching: find.byType(SettingsSection)),
        findsOneWidget,
      );
      final empty = find.text('No models imported');
      expect(empty, findsOneWidget);
      expect(
        find.ancestor(of: empty, matching: find.byType(SettingsPanel)),
        findsNothing,
      );

      final exportButton = find.byKey(const ValueKey('speech-export'));
      expect(tester.widget<AppActionButton>(exportButton).onPressed, isNull);
      final root = File(source).parent;
      await tester.runAsync(() async {
        expect(await speech.import(source), isNull);
        final recognition = await speechArchiveFixture(
          root,
          'Recognition',
          .bilingualZipformer,
        );
        expect(await speech.import(recognition), isNull);
      });
      final [model, recognition] = speech.library.models;
      final card = find.byKey(ValueKey('speech-model-${model.id}'));
      final details = find.byKey(ValueKey('speech-details-${model.id}'));
      final preview = find.byKey(ValueKey('speech-preview-${model.id}'));
      final name = find.descendant(
        of: card,
        matching: find.text('Chinese voice model'),
      );
      final recognitionCard = find.byKey(
        ValueKey('speech-model-${recognition.id}'),
      );

      for (final theme in themes.allThemes) {
        for (final width in [760.0, 320.0]) {
          await showPage(theme, width);
          expect(empty, findsNothing);
          expect(find.text('Imported voice models'), findsOneWidget);
          expect(
            find.text(
              'Models available for offline recognition and synthesis.',
            ),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(card).dx,
            tester.getTopLeft(recognitionCard).dx,
          );
          expect(
            tester.getSize(card).width,
            tester.getSize(recognitionCard).width,
          );
          expect(
            tester.getTopLeft(recognitionCard).dy,
            greaterThan(tester.getBottomLeft(card).dy),
          );
          expect(find.text('Chinese voice model'), findsOneWidget);
          expect(
            find.descendant(
              of: card,
              matching: find.text('Speech synthesis · Chinese VITS · 5 voices'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: recognitionCard,
              matching: find.text(
                'Speech recognition · Chinese–English Zipformer',
              ),
            ),
            findsOneWidget,
          );
          expect(find.text('Default model'), findsNothing);
          expect(
            find.descendant(of: card, matching: find.text('Bound to 0 agents')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: card, matching: find.byType(Text)),
            findsNWidgets(5),
          );
          final detailsBounds = tester.getRect(details);
          final nameBounds = tester.getRect(name);
          if (width == 320) {
            expect(detailsBounds.top, greaterThan(nameBounds.bottom));
          } else {
            expect(detailsBounds.left, greaterThanOrEqualTo(nameBounds.right));
          }
          expect(preview, findsNothing);
          expect(tester.widget<AppActionButton>(details).label, 'View details');
          await tester.ensureVisible(details);
          await tester.tap(details);
          await tester.pumpAndSettle();
          final dialogIcon = find.descendant(
            of: find.byType(SpeechModelDialog),
            matching: find.byType(SpeechModelIcon),
          );
          final iconBackground =
              tester
                      .widget<DecoratedBox>(
                        find.descendant(
                          of: dialogIcon,
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .decoration
                  as BoxDecoration;
          expect(iconBackground.color, theme.secondary);
          expect(iconBackground.shape, BoxShape.circle);
          expect(
            iconBackground.color,
            isNot(AppDialogStyle.backgroundColor(theme)),
          );
          expect(
            find.text('Model format: Chinese VITS (vits-zh-ll)'),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('speech-preview-voice')),
            findsOneWidget,
          );
          final previewTitle = find.text('Voice to preview');
          final previewDescription = find.text(
            'Choose a voice to hear a sample. This does not change any agent’s settings.',
          );
          expect(
            tester.widget<Text>(previewTitle).style,
            AppDialogStyle.fieldTitleStyle(theme),
          );
          expect(
            tester.widget<Text>(previewDescription).style,
            AppDialogStyle.descriptionStyle(theme),
          );
          expect(
            find.byKey(ValueKey('speech-export-${model.id}')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Set as default'), findsNothing);
          await tester.tap(find.byKey(const ValueKey('speech-model-close')));
          await tester.pumpAndSettle();
        }
      }

      await showPage(themes.allThemes.first, 760, locale: const Locale('zh'));
      expect(find.text('查看详情'), findsNWidgets(2));
      expect(find.text('试听'), findsNothing);
      expect(
        find.descendant(
          of: card,
          matching: find.text('语音合成 · 中文 VITS · 5 种音色'),
        ),
        findsOneWidget,
      );
      await showPage(themes.allThemes.first, 760);
      final recognitionDetails = find.byKey(
        ValueKey('speech-details-${recognition.id}'),
      );
      await tester.ensureVisible(recognitionDetails);
      await tester.tap(recognitionDetails);
      await tester.pumpAndSettle();
      expect(find.text('Test recognition'), findsOneWidget);
      final recognitionTest = find.byKey(
        ValueKey('speech-recognition-test-${recognition.id}'),
      );
      final transcript = find.descendant(
        of: find.byKey(const ValueKey('speech-recognition-test-result')),
        matching: find.byType(TextField),
      );
      TextField field() => tester.widget<TextField>(transcript);
      Future<void> waitForPartial(String draft) async {
        await tester.tap(recognitionTest);
        for (
          var attempt = 0;
          attempt < 100 && field().controller!.text == draft;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
        expect(find.text('Stop recording'), findsOneWidget);
        expect(field().readOnly, isTrue);
        expect(field().controller!.text, '$draft\nrecognized test');
      }

      await tester.enterText(transcript, 'Existing draft');
      await tester.runAsync(() async {
        await waitForPartial('Existing draft');
        await tester.tap(recognitionTest);
      });
      await tester.pumpAndSettle();
      expect(
        field().controller!.text,
        'Existing draft\nrecognized test phrase',
      );
      expect(field().readOnly, isFalse);
      expect(input.lastStop, isTrue);
      await tester.enterText(transcript, 'Edited transcript');
      await tester.runAsync(() => waitForPartial('Edited transcript'));
      await tester.tap(find.byKey(const ValueKey('speech-model-close')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(input.lastStop, isFalse);
      expect(speech.hasCapture, isFalse);
      final destination = path.join(root.path, 'selected.tar.zst');
      final previousPicker = FileSelectorPlatform.instance;
      final picker = _FileSelector(destination);
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = previousPicker);
      final exportPosition = tester.getTopLeft(exportButton);
      final importPosition = tester.getTopLeft(importButton);
      expect(
        exportPosition.dy < importPosition.dy ||
            (exportPosition.dy == importPosition.dy &&
                exportPosition.dx < importPosition.dx),
        isTrue,
      );
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      expect(find.text('Export selected (2)'), findsOneWidget);
      final confirm = find.byKey(const ValueKey('speech-package-confirm'));
      Finder exportCard(SpeechModel model) =>
          find.byKey(ValueKey('speech-package-card-${model.id}'));
      expect(
        find.descendant(
          of: exportCard(model),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).shape == BoxShape.circle &&
                (widget.decoration as BoxDecoration).color ==
                    themes.allThemes.first.primary,
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(exportCard(model));
      await tester.tap(exportCard(recognition));
      await tester.pumpAndSettle();
      expect(tester.widget<AppActionButton>(confirm).onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(picker.saveCalls, 0);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      await tester.tap(exportCard(recognition));
      await tester.pumpAndSettle();
      expect(find.text('Export selected (1)'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(confirm);
        for (
          var attempt = 0;
          attempt < 100 &&
              tester.widget<AppActionButton>(exportButton).onPressed == null;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          tester.widget<AppActionButton>(exportButton).onPressed,
          isNotNull,
        );
        final receiver = SpeechModelStore(
          directory: Directory(path.join(root.path, 'receiver')),
        );
        final restored = await receiver.import(
          SpeechLibrary(),
          destination,
          check: engine.check,
        );
        expect(restored.models.single.id, model.id);
      });
      await tester.pumpAndSettle();
      expect(picker.saveCalls, 1);
      expect(
        picker.suggestedName,
        matches(r'^lilygobox-voice-model-package-\d{12}\.tar\.zst$'),
      );
      final selection = (modelId: model.id, voice: 4);
      final bindings = emptySpeechBindings.withVoice(selection);
      agent.assistant.setSpeechBindings(bindings);
      otherAgent.assistant.setSpeechBindings(bindings);
      await tester.pumpAndSettle();
      expect(find.text('Bound to 2 agents'), findsOneWidget);
      workspaces.remove(otherAgent.id);
      agent.assistant.setSpeechBindings(emptySpeechBindings);
      await tester.pumpAndSettle();
      expect(find.text('Bound to 1 agent'), findsOneWidget);
      await tester.tap(details);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('speech-preview-voice')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voice 3'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(preview));
      await tester.pumpAndSettle();
      expect(find.text('Stop playback'), findsOneWidget);
      for (var attempt = 0; attempt < 100 && !output.playing; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(output.playing, isTrue);
      expect(engine.previewVoice, 2);
      expect(agent.assistant.speechVoice, isNull);
      expect(workspaces.speechLibraryUsage[model.id], 1);
      await tester.tap(find.byKey(const ValueKey('speech-model-close')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(output.playing, isFalse);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('Voice 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('speech-model-close')));
      await tester.pumpAndSettle();

      agent.assistant.setSpeechBindings(
        bindings.withRecognition(recognition.id).withEnabled(.synthesis, false),
      );
      await tester.pumpAndSettle();
      final delete = find.byKey(ValueKey('speech-delete-${model.id}'));
      final confirmDelete = find.byKey(const ValueKey('confirm-speech-delete'));
      await tester.tap(delete);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(confirmDelete));
      expect(
        find.text(l10n.aiRoleplayLibraryDeleteBoundTitle(model.name, 2)),
        findsOneWidget,
      );
      expect(
        find.text(l10n.aiRoleplayLibraryAgentsToUnbind(2)),
        findsOneWidget,
      );
      expect(find.text(agent.title), findsOneWidget);
      expect(
        find.text(l10n.aiRoleplayLibraryRecycledAgent(otherAgent.title)),
        findsOneWidget,
      );
      for (final affected in [agent, otherAgent]) {
        expect(find.text(l10n.aiAgentIdValue(affected.id)), findsOneWidget);
      }
      expect(find.text(l10n.aiRoleplayLibraryDeleteAndUnbind), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancel-speech-delete')));
      await tester.pumpAndSettle();
      expect(speech.library.models, contains(model));
      expect(agent.assistant.speechBindings.voice, selection);

      final deleteSelected = find.byKey(
        const ValueKey('speech-delete-selected'),
      );
      expect(deleteSelected, findsNothing);
      await tester.tap(name);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppActionButton>(deleteSelected).label,
        l10n.settingsDeleteSelected(1),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text(recognition.name));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppActionButton>(deleteSelected).label,
        l10n.settingsDeleteSelected(2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(deleteSelected, findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.tap(deleteSelected);
      await tester.pumpAndSettle();
      expect(find.text(l10n.speechDeleteModelsHeading(2)), findsOneWidget);
      expect(
        find.text(l10n.aiRoleplayLibraryAgentsToUnbind(2)),
        findsOneWidget,
      );
      expect(find.text(l10n.aiAgentIdValue(agent.id)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancel-speech-delete')));
      await tester.pumpAndSettle();
      expect(deleteSelected, findsOneWidget);
      expect(speech.library.models, hasLength(2));

      await tester.tap(deleteSelected);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(confirmDelete);
        for (
          var attempt = 0;
          attempt < 100 && speech.library.models.isNotEmpty;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
        expect(speech.library.models, isEmpty);
        expect(agent.assistant.speechBindings, emptySpeechBindings);
        expect(await File(source).exists(), isTrue);
        final recycled = workspaces.recycledAgents.single;
        expect(recycled.id, otherAgent.id);
        expect(recycled.record['conversation'], isNot(contains('speechVoice')));
      });
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(recognitionCard, findsNothing);
      expect(deleteSelected, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
