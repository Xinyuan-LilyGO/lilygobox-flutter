import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/user_input.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_composer.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/user_input_panel.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

import 'assistant_test_scope.dart';

const _questions = [
  {
    'id': 'scope',
    'header': '修改范围',
    'question': '需要处理哪些文件？',
    'options': [
      {'label': '当前文件夹', 'description': '仅处理当前目录中的内容。'},
      {'label': '整个项目', 'description': '处理项目中的相关文件。'},
    ],
  },
  {
    'id': 'style',
    'header': '输出方式',
    'question': '希望如何展示结果？',
    'options': [
      {'label': '简短说明', 'description': '只展示关键结果。'},
      {'label': '详细说明', 'description': '展示处理过程和验证信息。'},
    ],
  },
];

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'single three-option question shows its note without scrolling ($dark)',
      (tester) async {
        final theme = ThemeProvider()
          ..setTheme(dark ? ThemeType.dark : ThemeType.light);
        final focus = FocusNode();
        addTearDown(theme.dispose);
        addTearDown(focus.dispose);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 700);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var largeText = false;
        final request = AiUserInputRequest.fromArguments('single', {
          'questions': [
            {
              'id': 'activity',
              'header': '新闻题测试',
              'question': '如果现在给你十分钟空闲时间，你最想做什么？',
              'options': [
                {'label': '听听音乐', 'description': '放一首喜欢的歌，休息一下。'},
                {'label': '出去走走', 'description': '活动一下，换换心情。'},
                {'label': '玩会游戏', 'description': '来一局轻松的小游戏。'},
              ],
            },
          ],
        });
        Widget app() => MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(largeText ? 1.5 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 820,
                child: AssistantUserInputPanel(
                  request: request,
                  theme: theme.themeData,
                  inputFocus: focus,
                  onSubmit: (_) {},
                  onCancel: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        final scroll = find.byKey(const ValueKey('ai-user-input-scroll'));
        final controller = tester
            .widget<SingleChildScrollView>(scroll)
            .controller!;
        final note = find.byKey(const ValueKey('ai-question-note-activity'));
        final submit = find.byKey(const ValueKey('ai-user-input-submit'));
        expect(controller.position.maxScrollExtent, 0);
        expect(note.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(note).bottom,
          lessThan(tester.getRect(submit).top),
        );
        expect(tester.takeException(), isNull);

        // 小窗口及放大字体保留内部滚动，不把底部操作挤出可视区域。
        largeText = true;
        tester.view.physicalSize = const Size(360, 480);
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(controller.position.maxScrollExtent, greaterThan(0));
        expect(submit.hitTestable(), findsOneWidget);
        expect(tester.getRect(submit).bottom, lessThanOrEqualTo(480));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(note);
        await tester.pumpAndSettle();
        expect(note.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final dark in [false, true]) {
    for (final narrow in [false, true]) {
      testWidgets(
        'all questions need an answer and fixed actions remain visible ($dark/$narrow)',
        (tester) async {
          final theme = ThemeProvider()
            ..setTheme(dark ? ThemeType.dark : ThemeType.light);
          final focus = FocusNode();
          addTearDown(theme.dispose);
          addTearDown(focus.dispose);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = narrow
              ? const Size(360, 760)
              : const Size(800, 600);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundaryKey = GlobalKey();
          if (const bool.fromEnvironment('CAPTURE_USER_INPUT')) {
            await (FontLoader('LilygoBoxInter')..addFont(
                  rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf'),
                ))
                .load();
            await tester.runAsync(() async {
              final font = File(
                '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/msyh.ttc',
              );
              if (await font.exists()) {
                await (FontLoader('UserInputCaptureCjk')..addFont(
                      Future.value(
                        ByteData.sublistView(await font.readAsBytes()),
                      ),
                    ))
                    .load();
              }
            });
            await (FontLoader(
                  'packages/material_symbols_icons/MaterialSymbolsRounded',
                )..addFont(
                  rootBundle.load(
                    'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
                  ),
                ))
                .load();
          }
          Map<String, List<String>>? submitted;
          var cancelled = false;
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(narrow ? 'en' : 'zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(
                colorScheme: theme.themeData.materialColors,
                fontFamily: 'LilygoBoxInter',
                fontFamilyFallback: const ['UserInputCaptureCjk'],
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(narrow ? 1.5 : 1)),
                child: child!,
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: 480,
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: AssistantUserInputPanel(
                        request: AiUserInputRequest.fromArguments('ask', {
                          'questions': _questions,
                        }),
                        theme: theme.themeData,
                        inputFocus: focus,
                        onSubmit: (answers) => submitted = answers,
                        onCancel: () => cancelled = true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final submit = find.byKey(const ValueKey('ai-user-input-submit'));
          expect(tester.widget<AppActionButton>(submit).onPressed, isNull);
          final scroll = find.byKey(const ValueKey('ai-user-input-scroll'));
          final scrollController = tester
              .widget<SingleChildScrollView>(scroll)
              .controller!;
          expect(scrollController.position.maxScrollExtent, greaterThan(0));
          final scrollbarContext = tester.element(
            find.byKey(const ValueKey('ai-user-input-scrollbar')),
          );
          expect(ScrollbarTheme.of(scrollbarContext).crossAxisMargin, 6);
          await tester.tap(
            find.byKey(const ValueKey('ai-question-option-scope-0')),
          );
          await tester.pumpAndSettle();
          expect(tester.widget<AppActionButton>(submit).onPressed, isNull);
          final secondNote = find.descendant(
            of: find.byKey(const ValueKey('ai-question-note-style')),
            matching: find.byType(TextField),
          );
          await tester.ensureVisible(secondNote);
          await tester.enterText(secondNote, '自定义结果格式');
          await tester.pumpAndSettle();
          expect(tester.widget<AppActionButton>(submit).onPressed, isNotNull);
          expect(
            tester.getRect(submit).bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height),
          );
          if (const bool.fromEnvironment('CAPTURE_USER_INPUT') && !narrow) {
            scrollController.jumpTo(0);
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final image = await tester
                  .renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey))
                  .toImage(pixelRatio: 1.5);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('tmp').create(recursive: true);
              await File(
                'tmp/user-input-panel-$dark.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(submit);
          await tester.pump();
          expect(submitted, {
            'scope': ['当前文件夹'],
            'style': ['自定义结果格式'],
          });
          expect(tester.widget<AppActionButton>(submit).onPressed, isNull);
          expect(cancelled, isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('oversized notes cannot submit invalid answers or split emoji', (
    tester,
  ) async {
    final theme = ThemeProvider();
    final focus = FocusNode();
    addTearDown(theme.dispose);
    addTearDown(focus.dispose);
    final request = AiUserInputRequest.fromArguments('long-note', {
      'questions': [_questions.first],
    });
    Map<String, List<String>>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 480,
              child: AssistantUserInputPanel(
                request: request,
                theme: theme.themeData,
                inputFocus: focus,
                onSubmit: (answers) =>
                    submitted = request.validateAnswers(answers),
                onCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final note = find.descendant(
      of: find.byKey(const ValueKey('ai-question-note-scope')),
      matching: find.byType(TextField),
    );
    final submit = find.byKey(const ValueKey('ai-user-input-submit'));
    await tester.ensureVisible(note);
    // UTF-16 协议上限也适用于粘贴，不能仅按用户可见字符计数。
    await tester.enterText(note, 'x' * 16001);
    await tester.pump();
    expect(tester.widget<TextField>(note).controller!.text, isEmpty);
    expect(tester.widget<AppActionButton>(submit).onPressed, isNull);
    await tester.enterText(note, '😀' * 8001);
    await tester.pump();
    expect(tester.widget<TextField>(note).controller!.text, isEmpty);
    expect(tester.widget<AppActionButton>(submit).onPressed, isNull);
    final accepted = '${'😀' * 7999}ab';
    expect(accepted.length, 16000);
    await tester.enterText(note, accepted);
    await tester.pump();
    expect(tester.widget<TextField>(note).controller!.text, accepted);
    await tester.enterText(note, '${accepted}c');
    await tester.pump();
    expect(tester.widget<TextField>(note).controller!.text, accepted);
    await tester.tap(submit);
    await tester.pump();
    expect(submitted, {
      'scope': [accepted],
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'question replaces composer and restores draft, attachment and queue after cancellation',
    (tester) async {
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final split = SplitViewProvider();
      var calls = 0;
      final response = Completer<http.Response>();
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        client: MockClient((_) async {
          if (++calls > 1) return response.future;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '',
                    'tool_calls': [
                      {
                        'id': 'question-call',
                        'type': 'function',
                        'function': {
                          'name': 'request_user_input',
                          'arguments': jsonEncode({
                            'questions': [_questions.first],
                          }),
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await scope.provider.initialized;
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      final input = TextEditingController(text: 'unsent draft');
      final focus = FocusNode();
      final scroll = ScrollController();
      final bytes = (await tester.runAsync(
        () =>
            File('assets/images/branding/lilygobox_app_icon.png').readAsBytes(),
      ))!;
      final attachment = AiImageAttachment(
        name: 'draft.png',
        mimeType: 'image/png',
        bytes: bytes,
      );
      addTearDown(() {
        scope.dispose();
        theme.dispose();
        language.dispose();
        shell.dispose();
        split.dispose();
        input.dispose();
        focus.dispose();
        scroll.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 480,
                child: ListenableBuilder(
                  listenable: scope.provider,
                  builder: (context, _) => ChatComposer(
                    input: input,
                    focusNode: focus,
                    scrollController: scroll,
                    theme: theme.themeData,
                    assistant: scope.provider,
                    ready: true,
                    onSend: (_) {},
                    attachments: [attachment],
                    onAttachmentsChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pump();
      final sending = scope.provider.sendMessage('Ask a question');
      for (var i = 0; scope.provider.pendingUserInput == null && i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(
        scope.provider.pendingUserInput,
        isNotNull,
        reason: 'calls=$calls error=${scope.provider.error}',
      );
      await scope.provider.sendMessage('queued message');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('ai-composer-input-layer')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('ai-user-input-panel')), findsOneWidget);
      expect(focus.hasFocus, isFalse);
      await tester.tap(find.byKey(const ValueKey('ai-user-input-cancel')));
      for (var i = 0; calls < 2 && i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('ai-user-input-panel')), findsNothing);
      expect(
        find.byKey(const ValueKey('ai-composer-input-layer')),
        findsOneWidget,
      );
      expect(input.text, 'unsent draft');
      expect(focus.hasFocus, isFalse);
      expect(
        tester
            .widget<ChatComposer>(find.byType(ChatComposer))
            .attachments
            .single,
        same(attachment),
      );
      expect(scope.provider.pendingGuidance.single.content, 'queued message');
      scope.provider.stopGeneration();
      response.complete(
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'done'},
              },
            ],
          }),
          200,
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      unawaited(sending);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
