/*
 * @Description: 验证 AI 主页居中与底部输入状态、键盘发送、直达设置及缩放布局。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 11:16:04
 * @LastEditTime: 2026-11-10 13:53:32
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/context_menu/text_selection_menu.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/app_capsule_slider.dart';
import 'package:lilygobox/core/widgets/title_bar_icon_button.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_composer.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/features/settings/presentation/widgets/split_view.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

void main() {
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider splitView;
  late AppNavigationProvider navigation;
  late AssistantTestScope scope;
  var requests = 0;
  Completer<void>? responseGate;
  var failRequests = false;
  var transientFailures = 0;
  var showProcess = false;
  final requestBodies = <String>[];
  final boundaryKey = GlobalKey();
  final latestMotionVariant = ValueVariant<bool>({false, true});

  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    splitView = SplitViewProvider();
    navigation = AppNavigationProvider();
    requests = 0;
    responseGate = null;
    failRequests = false;
    transientFailures = 0;
    showProcess = false;
    requestBodies.clear();
    if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
      final inter = FontLoader('LilygoBoxInter')
        ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf'));
      final defaultFont = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/Roboto/Roboto-Variable.ttf'));
      final symbols =
          FontLoader(
            'packages/material_symbols_icons/MaterialSymbolsRounded',
          )..addFont(
            rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
            ),
          );
      await Future.wait([inter.load(), defaultFont.load(), symbols.load()]);
    }
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: splitView,
      client: MockClient((request) async {
        requests++;
        requestBodies.add(request.body);
        if (responseGate case final gate?) await gate.future;
        if (failRequests) {
          return http.Response('{"error":{"message":"Invalid token"}}', 401);
        }
        if (transientFailures > 0) {
          transientFailures--;
          return http.Response('Unavailable', 503);
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': showProcess && requests == 1
                    ? {
                        'content': 'Updating the theme.',
                        'reasoning_content': 'Inspect the current theme.',
                        'tool_calls': [
                          {
                            'id': 'theme-call',
                            'type': 'function',
                            'function': {
                              'name': 'set_theme',
                              'arguments': '{"theme":"dark"}',
                            },
                          },
                        ],
                      }
                    : {
                        'content': 'Ready to help with LilygoBox.',
                        if (showProcess)
                          'reasoning_content': List.filled(
                            30,
                            'Confirm the setting result. ',
                          ).join(),
                      },
              },
            ],
          }),
          200,
        );
      }),
    );
  });
  tearDown(() {
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    splitView.dispose();
    navigation.dispose();
  });

  Widget app({
    bool settings = false,
    bool tickerEnabled = true,
    bool disableAnimations = false,
    double scale = 1,
    String locale = 'en',
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider.value(value: language),
      ChangeNotifierProvider.value(value: scope.provider),
      ChangeNotifierProvider.value(value: navigation),
    ],
    child: MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: theme.themeData.materialColors,
        fontFamily: 'LilygoBoxInter',
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: disableAnimations,
        ),
        child: RepaintBoundary(key: boundaryKey, child: child!),
      ),
      home: Scaffold(
        body: TickerMode(
          enabled: tickerEnabled,
          child: settings ? const SettingsSplitView() : const AssistantPage(),
        ),
      ),
    ),
  );

  Future<void> pumpAssistantUntilIdle(WidgetTester tester) async {
    for (var i = 0; i < 1000 && scope.provider.busy; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(scope.provider.busy, isFalse);
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('tmp/assistant-ui/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('composer theme background updates while its ticker is paused', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final background = find.byKey(
      const ValueKey('ai-composer-input-background'),
    );
    expect(
      tester.widget<ColoredBox>(background).color,
      theme.themeData.primary,
    );

    await tester.pumpWidget(app(tickerEnabled: false));
    theme.setTheme(ThemeType.light);
    await tester.pump();
    expect(
      tester.widget<ColoredBox>(background).color,
      theme.themeData.primary,
    );

    await tester.pumpWidget(app(tickerEnabled: true));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ColoredBox>(background).color,
      theme.themeData.primary,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'composer stays at bottom with centered greeting and no assistant title',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final composer = find.byType(ChatComposer);
      expect(tester.getBottomRight(composer).dy, closeTo(736, 1));
      expect(
        tester.getRect(find.text('What can I help you with today?')).center.dx,
        closeTo(550, 1),
      );
      expect(find.text('LilygoBox Assistant'), findsNothing);
      expect(
        find.byKey(const ValueKey('ai-composer-context-layer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ai-composer-input-layer')),
        findsOneWidget,
      );
      final outerRect = tester.getRect(
        find.byKey(const ValueKey('ai-composer-context-layer')),
      );
      final innerRect = tester.getRect(
        find.byKey(const ValueKey('ai-composer-input-layer')),
      );
      expect(innerRect.top - outerRect.top, 5);
      expect(outerRect.bottom - innerRect.bottom, 5);
      expect(innerRect.left - outerRect.left, 5);
      expect(outerRect.right - innerRect.right, 5);
      await capture(tester, 'home-empty-dark');
      expect(find.text('Adjust sidebar layout'), findsNothing);
      expect(find.text('Configure AI service'), findsNothing);
      final outer = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('ai-composer-context-layer')),
      );
      final inner = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('ai-composer-input-layer')),
      );
      final inputBackground = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('ai-composer-input-background')),
      );
      expect((outer.decoration as BoxDecoration).border, isNull);
      expect(
        (inner.decoration as BoxDecoration).border!.top.color,
        Colors.transparent,
      );
      expect(inputBackground.color, theme.themeData.primary);
      expect(find.text('LilygoBox workspace'), findsNothing);
      final field = find.byKey(const ValueKey('ai-message-input'));
      await tester.enterText(field, 'Adjust sidebar layout');
      tester.widget<TextField>(field).focusNode!.unfocus();
      await tester.pumpAndSettle();
      tester.widget<TextField>(field).focusNode!.requestFocus();
      await tester.pump(Duration.zero);
      final focusedOuter = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('ai-composer-context-layer')),
      );
      final focusedInner = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('ai-composer-input-layer')),
      );
      Color renderedBorderColor() =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: find.byKey(
                                const ValueKey('ai-composer-input-layer'),
                              ),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .border!
              .top
              .color;
      expect((focusedOuter.decoration as BoxDecoration).border, isNull);
      expect(renderedBorderColor(), Colors.transparent);
      await tester.pump(const Duration(milliseconds: 90));
      final transitioningColor = renderedBorderColor();
      expect(transitioningColor, isNot(Colors.transparent));
      expect(transitioningColor, isNot(theme.themeData.basePrimary));
      await tester.pump(const Duration(milliseconds: 90));
      expect(renderedBorderColor(), theme.themeData.basePrimary);
      expect(focusedInner.duration, const Duration(milliseconds: 180));
      expect(requests, 0);
      await scope.provider.saveService(
        name: 'DeepSeek',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://api.deepseek.com',
        models: ['deepseek-chat'],
        apiKey: 'test-key',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await pumpAssistantUntilIdle(tester);
      expect(requests, 1);
      expect(find.text('Ready to help with LilygoBox.'), findsOneWidget);
      expect(find.text('Adjust sidebar layout'), findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      final assistantSelection = tester.widget<SelectionArea>(
        find.ancestor(
          of: find.text('Ready to help with LilygoBox.'),
          matching: find.byType(SelectionArea),
        ),
      );
      expect(
        assistantSelection.contextMenuBuilder,
        AppTextSelectionMenu.buildRegion,
      );
      final reply = scope.provider.messages.last;
      final responseDetails = find.byKey(
        ValueKey('ai-response-details-${reply.id}'),
      );
      expect(responseDetails, findsOneWidget);
      await tester.tap(responseDetails);
      await tester.pumpAndSettle();
      expect(find.text('Model: deepseek-chat'), findsOneWidget);
      expect(find.text('API protocol: OpenAI Chat Completions'), findsNothing);
      expect(find.text('No application settings were changed.'), findsNothing);
      final messageList = find.byType(ListView);
      expect(
        tester.getSize(messageList).width,
        tester.getSize(find.byType(AssistantPage)).width,
      );
      expect(tester.getBottomRight(composer).dy, closeTo(736, 1));
      expect(find.text('What can I help you with today?'), findsNothing);
      await capture(tester, 'home-conversation-dark');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'composer keeps selection tight and reserves a scrollbar gutter',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ChatComposer),
          matching: find.byType(Scrollbar),
        ),
        findsOneWidget,
      );
      final field = find.byKey(const ValueKey('ai-message-input'));
      final text =
          'A long first line for selection.\nShort\n${List.filled(20, 'More log content to scroll.').join('\n')}';
      await tester.enterText(field, text);
      final input = tester.widget<TextField>(field);
      input.controller!.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
      await tester.pumpAndSettle();
      final editable = tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      final shortStart = text.indexOf('Short');
      final boxes = editable.renderEditable.getBoxesForSelection(
        TextSelection(baseOffset: shortStart, extentOffset: shortStart + 5),
      );
      expect(boxes.single.right - boxes.single.left, lessThan(100));
      final scrollbar = find.byKey(const ValueKey('ai-input-scrollbar'));
      expect(
        tester.getRect(scrollbar).right - tester.getRect(field).right,
        closeTo(14, .1),
      );
      expect(input.scrollController!.position.maxScrollExtent, greaterThan(0));
      final original = input.controller!.text;
      input.scrollController!.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(field),
          scrollDelta: const Offset(0, 60),
          kind: PointerDeviceKind.mouse,
        ),
      );
      expect(input.scrollController!.offset, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(input.scrollController!.offset, inExclusiveRange(0, 60));
      await tester.pumpAndSettle();
      expect(input.scrollController!.offset, closeTo(60, .1));
      expect(input.controller!.text, original);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'animates wheel scrolling and latest button with theme contrast',
    (tester) async {
      final reducedMotion = latestMotionVariant.currentValue!;
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      await tester.runAsync(
        () => scope.provider.sendMessage(
          List.filled(60, 'Long conversation line').join('\n'),
        ),
      );
      await tester.pumpWidget(app(disableAnimations: reducedMotion));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('ai-scroll-to-latest'));
      expect(button, findsNothing);
      final original = controller.offset;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(ListView)),
          scrollDelta: const Offset(0, -240),
          kind: PointerDeviceKind.mouse,
        ),
      );
      if (reducedMotion) {
        expect(controller.offset, closeTo(original - 240, .1));
      } else {
        expect(controller.offset, original);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(controller.offset, inExclusiveRange(original - 240, original));
      }
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      expect(
        tester.getBottomRight(button).dy,
        lessThan(tester.getTopLeft(find.byType(ChatComposer)).dy),
      );

      // Both themes keep a distinct neutral fill and hover state.
      for (final type in ThemeType.values) {
        theme.setTheme(type);
        await tester.pumpAndSettle();
        final control = tester.widget<TitleBarIconButton>(button);
        expect(
          (control.backgroundColor!.computeLuminance() -
                  theme.themeData.secondary.computeLuminance())
              .abs(),
          greaterThan(.04),
        );
        expect(control.hoverColor, isNot(control.backgroundColor));
      }

      // The outgoing button fades without accepting mouse or keyboard input.
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      if (!reducedMotion) {
        await tester.pump(const Duration(milliseconds: 75));
        final fade = tester.widget<FadeTransition>(
          find
              .ancestor(of: button, matching: find.byType(FadeTransition))
              .first,
        );
        expect(fade.opacity.value, inExclusiveRange(0, 1));
        expect(button.hitTestable(), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(button, findsNothing);

      controller.jumpTo(controller.position.maxScrollExtent - 240);
      await tester.pump();
      if (!reducedMotion) {
        await tester.pump(const Duration(milliseconds: 75));
        final fade = tester.widget<FadeTransition>(
          find
              .ancestor(of: button, matching: find.byType(FadeTransition))
              .first,
        );
        expect(fade.opacity.value, inExclusiveRange(0, 1));
      }
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.position.extentAfter, closeTo(0, 1));
      expect(button, findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: latestMotionVariant,
  );

  testWidgets('missing key opens model services without losing the draft', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ai-message-input'));
    await tester.enterText(field, 'Keep this draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(navigation.currentPage, AppPage.settings);
    expect(navigation.settingsSection, AppSettingsSection.aiServices);
    expect(tester.widget<TextField>(field).controller!.text, 'Keep this draft');
    expect(requests, 0);
  });

  testWidgets('keeps input focused and editable while a reply is generating', (
    tester,
  ) async {
    responseGate = Completer<void>();
    await tester.runAsync(() => scope.provider.initialized);
    await scope.provider.saveService(
      name: 'DeepSeek',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://api.deepseek.com',
      models: ['deepseek-chat'],
      apiKey: 'test-key',
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ai-message-input'));
    await tester.enterText(field, 'First message');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    final activeField = tester.widget<TextField>(field);
    expect(scope.provider.busy, isTrue);
    expect(activeField.focusNode!.hasFocus, isTrue);
    expect(activeField.readOnly, isFalse);
    expect(find.text('Connecting · 00:00:000'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Connecting'), findsOneWidget);

    final pauseResumeButton = find.byKey(
      const ValueKey('ai-pause-resume-button'),
    );
    expect(pauseResumeButton, findsOneWidget);
    expect(find.byKey(const ValueKey('ai-stop-button')), findsNothing);
    expect(
      tester.widget<TitleBarIconButton>(pauseResumeButton).icon,
      Symbols.stop_rounded,
    );
    await tester.tap(pauseResumeButton);
    await tester.pump();
    expect(scope.provider.paused, isTrue);
    expect(
      tester.widget<TitleBarIconButton>(pauseResumeButton).icon,
      Symbols.play_arrow_rounded,
    );
    await tester.tap(pauseResumeButton);
    await tester.pump();
    expect(scope.provider.paused, isFalse);
    await tester.enterText(field, 'Next message');
    expect(tester.widget<TextField>(field).controller!.text, 'Next message');

    responseGate!.complete();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 30));
    expect(scope.provider.busy, isFalse);
    expect(find.textContaining('Thinking…'), findsNothing);
    expect(find.textContaining('Responding'), findsNothing);
    expect(
      scope.provider.messages.last.content,
      'Ready to help with LilygoBox.',
    );
    await pumpAssistantUntilIdle(tester);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(tester.widget<TextField>(field).controller!.text, 'Next message');
  });

  testWidgets(
    'request failures stay in their chat turns after later messages',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Test API',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test-model'],
        apiKey: 'test-key',
      );
      await tester.pumpWidget(app());
      failRequests = true;
      unawaited(scope.provider.sendMessage('First attempt'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await pumpAssistantUntilIdle(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Processing failed'), findsOneWidget);
      expect(find.text('This turn failed  Invalid token'), findsOneWidget);
      unawaited(scope.provider.sendMessage('Second attempt'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await pumpAssistantUntilIdle(tester);
      await tester.pumpAndSettle();
      expect(find.text('This turn failed  Invalid token'), findsNWidgets(2));
      expect(requests, 2);
      final failedTurns = scope.provider.messages
          .where((message) => message.requestError != null)
          .toList();
      expect(failedTurns, hasLength(2));
      expect(
        failedTurns.every(
          (message) => message.status == AiResponseStatus.failed,
        ),
        isTrue,
      );
      failRequests = false;
      unawaited(scope.provider.sendMessage('Try again'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await pumpAssistantUntilIdle(tester);
      await tester.pumpAndSettle();
      expect(find.text('This turn failed  Invalid token'), findsNWidgets(2));
      expect(scope.provider.messages.last.status, AiResponseStatus.completed);
      expect(scope.provider.messages.last.requestError, isNull);
      expect(requestBodies.last, isNot(contains('Invalid token')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retry state and its cause are shown in the matching chat turn', (
    tester,
  ) async {
    await tester.runAsync(() => scope.provider.initialized);
    await scope.provider.saveService(
      name: 'Test API',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['test-model'],
      apiKey: 'test-key',
    );
    await tester.pumpWidget(app());
    transientFailures = 1;
    unawaited(scope.provider.sendMessage('Hello'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (
      var i = 0;
      i < 20 && scope.provider.messages.last.retries.isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump();
    expect(scope.provider.messages.last.status, AiResponseStatus.retrying);
    expect(find.textContaining('Retrying model request (1/2)'), findsOneWidget);
    await pumpAssistantUntilIdle(tester);
    await tester.pumpAndSettle();
    final reply = scope.provider.messages.last;
    expect(reply.status, AiResponseStatus.completed);
    expect(reply.retries.single.attempt, 1);
    expect(reply.requestError, isNull);
    expect(requests, 2);
    await tester.tap(find.byKey(ValueKey('ai-response-details-${reply.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Model request retry 1: HTTP 503'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('process is collapsed by default and scrolls when expanded', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(420, 760));
    await tester.runAsync(() => scope.provider.initialized);
    await scope.provider.saveService(
      name: 'Test',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['test'],
      apiKey: 'key',
    );
    showProcess = true;
    await tester.pumpWidget(app(scale: 1.5));
    unawaited(scope.provider.sendMessage('Switch the theme.'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await pumpAssistantUntilIdle(tester);
    await tester.pumpAndSettle();
    final reply = scope.provider.messages.last;
    expect(reply.content, 'Ready to help with LilygoBox.');
    expect(find.text('Model reasoning'), findsNothing);
    expect(find.text('Updating the theme.'), findsNothing);
    final header = find.byKey(ValueKey('ai-response-details-${reply.id}'));
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text('Model reasoning'), findsNWidgets(2));
    expect(find.text('Inspect the current theme.'), findsOneWidget);
    expect(find.text('Updating the theme.'), findsOneWidget);
    expect(find.text('Applied: Change theme to Dark'), findsOneWidget);
    expect(
      find.text('Waiting for the model after setting operations'),
      findsOneWidget,
    );
    final scroll = find
        .ancestor(
          of: find.text('Inspect the current theme.'),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    final controller = tester.widget<SingleChildScrollView>(scroll).controller!;
    expect(tester.getSize(scroll).height, lessThanOrEqualTo(300));
    expect(controller.position.maxScrollExtent, greaterThan(0));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await capture(tester, 'process-details');
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text('Model reasoning'), findsNothing);
  });

  testWidgets('shift enter and IME confirmation do not submit messages', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ai-message-input'));
    await tester.enterText(field, 'First line');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(requests, 0);
    expect(navigation.currentPage, AppPage.home);
    final controller = tester.widget<TextField>(field).controller!;
    controller.value = const TextEditingValue(
      text: '拼音',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(navigation.currentPage, AppPage.home);
    expect(requests, 0);
  });

  testWidgets('clicking send does not focus the input again', (tester) async {
    responseGate = Completer<void>();
    await tester.runAsync(() => scope.provider.initialized);
    await scope.provider.saveService(
      name: 'DeepSeek',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://api.deepseek.com',
      models: ['deepseek-chat'],
      apiKey: 'test-key',
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('ai-message-input'));
    await tester.enterText(input, 'Send with the button');
    await tester.pump();
    expect(
      tester
          .widget<TitleBarIconButton>(
            find.byKey(const ValueKey('ai-send-button')),
          )
          .size,
      30,
    );
    await tester.tap(find.byKey(const ValueKey('ai-send-button')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(scope.provider.busy, isTrue, reason: 'request count: $requests');
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isFalse);
    expect(
      tester
          .widget<TitleBarIconButton>(
            find.byKey(const ValueKey('ai-pause-resume-button')),
          )
          .size,
      30,
    );

    responseGate!.complete();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await pumpAssistantUntilIdle(tester);
  });

  testWidgets('home and AI settings adapt to narrow windows and large text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final type in ThemeType.values) {
      theme.setTheme(type);
      for (final locale in ['en', 'zh']) {
        await tester.binding.setSurfaceSize(const Size(390, 720));
        await tester.pumpWidget(app(scale: 1.6, locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final inputScrollbars = find.descendant(
          of: find.byType(ChatComposer),
          matching: find.byType(Scrollbar),
        );
        expect(inputScrollbars, findsOneWidget);
        final field = find.byKey(const ValueKey('ai-message-input'));
        await tester.enterText(field, 'Line 1\nLine 2\nLine 3\nLine 4');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        navigation.openAiSettings();
        await tester.pumpWidget(
          app(settings: true, scale: 1.6, locale: locale),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ai-add-service')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        navigation.closeSettings();
      }
    }
  });

  testWidgets(
    'model selector searches services and switches without navigation or lost drafts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      expect(scope.provider.credentialLoaded, isTrue);
      final first = await scope.provider.saveService(
        name: 'DeepSeek',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://api.deepseek.com',
        models: ['deepseek-chat', 'deepseek-reasoner'],
        apiKey: 'first-key',
      );
      final second = await scope.provider.saveService(
        name: 'Gateway',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['custom-model'],
        apiKey: 'second-key',
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ai-message-input'));
      await tester.enterText(input, 'Keep this draft');
      await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedRotation>(
              find.byKey(const ValueKey('ai-model-selector-arrow')),
            )
            .turns,
        0.5,
      );
      expect(navigation.currentPage, AppPage.home);
      expect(find.text('For next messages'), findsNothing);
      expect(find.text('Add model service'), findsNothing);
      await capture(tester, 'model-selector-dark');
      final search = find.byKey(const ValueKey('ai-model-search'));
      expect(find.text('Filter by model name or service name.'), findsNothing);
      final searchInput = search;
      expect(
        tester.widget<TextField>(searchInput).decoration!.labelText,
        isNull,
      );
      expect(tester.widget<TextField>(searchInput).autofocus, isFalse);
      expect(
        tester.widget<TextField>(searchInput).focusNode!.hasFocus,
        isFalse,
      );
      final searchDecoration = tester
          .widget<TextField>(searchInput)
          .decoration!;
      expect(searchDecoration.hintText, 'Search models or providers');
      expect(searchDecoration.isDense, isTrue);
      expect(
        (searchDecoration.border as OutlineInputBorder).borderRadius,
        BorderRadius.circular(999),
      );
      await tester.enterText(search, 'no-such-model');
      await tester.pumpAndSettle();
      expect(find.text('No matching models'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(
        find.byKey(ValueKey('ai-model-$first-deepseek-reasoner')),
        findsOneWidget,
      );
      await tester.enterText(search, 'gateway');
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('ai-model-$first-deepseek-reasoner')),
        findsNothing,
      );
      await tester.tap(find.byKey(ValueKey('ai-model-$second-custom-model')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedRotation>(
              find.byKey(const ValueKey('ai-model-selector-arrow')),
            )
            .turns,
        0,
      );
      expect(scope.provider.selectedService?.id, second);
      expect(scope.provider.selectedModel, 'custom-model');
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Keep this draft',
      );
      expect(navigation.currentPage, AppPage.home);
      expect(requests, 0);
      expect(find.byKey(const ValueKey('ai-model-search')), findsNothing);
      expect(find.byKey(const ValueKey('ai-tools-button')), findsNothing);
      expect(find.text('Approval required for changes'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'model menu stays compact without focusing search in narrow large text layouts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final locale in ['en', 'zh']) {
        await tester.pumpWidget(app(scale: 1.6, locale: locale));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
        await tester.pumpAndSettle();
        final search = tester.widget<TextField>(
          find.byKey(const ValueKey('ai-model-search')),
        );
        expect(search.focusNode!.hasFocus, isFalse);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'reasoning opens first, fades to models and preserves concrete effort choices',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      final service = await scope.provider.saveService(
        name: 'Reasoning service',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['o3', 'plain'],
        apiKey: 'key',
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final trigger = find.byKey(const ValueKey('ai-model-selector'));
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-model-list-panel')), findsNothing);
      expect(find.byKey(const ValueKey('ai-reasoning-panel')), findsOneWidget);
      final slider = find.byType(Slider);
      expect(
        tester
            .widget<AppCapsuleSlider>(
              find.byKey(const ValueKey('ai-reasoning-slider')),
            )
            .divisions,
        2,
      );
      expect(find.text('Default'), findsNothing);
      expect(find.byKey(const ValueKey('ai-reasoning-reset')), findsNothing);
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
      await tester.pumpAndSettle();
      expect(scope.provider.reasoningEffort, AiReasoningEffort.high);
      expect(find.text('o3 · High'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai-reasoning-models')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final listFade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('ai-model-list-panel')),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(listFade.opacity.value, greaterThan(0));
      expect(listFade.opacity.value, lessThan(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('ai-model-$service-plain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-reasoning-panel')), findsNothing);
      expect(scope.provider.reasoningEffort, isNull);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('ai-model-$service-o3')));
      await tester.pumpAndSettle();
      expect(scope.provider.reasoningEffort, AiReasoningEffort.high);
      expect(find.byKey(const ValueKey('ai-reasoning-reset')), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-reasoning-panel')), findsOneWidget);
      expect(tester.widget<Slider>(slider).value, 1);
      expect(scope.provider.selectedModel, 'o3');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'turn details retain the model and effort used for that request',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Reasoning service',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['o3', 'plain'],
        apiKey: 'key',
      );
      await scope.provider.setReasoningEffort(AiReasoningEffort.high);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.runAsync(() => scope.provider.sendMessage('Hello'));
      await pumpAssistantUntilIdle(tester);
      final reply = scope.provider.messages.last;
      await scope.provider.setReasoningEffort(AiReasoningEffort.low);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('ai-response-effort-${reply.id}')),
        findsNothing,
      );
      await tester.tap(find.byKey(ValueKey('ai-response-details-${reply.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Model: o3'), findsOneWidget);
      expect(find.text('Reasoning effort: High'), findsOneWidget);
      expect(find.text('Reasoning effort: Low'), findsNothing);
      final modelRect = tester.getRect(find.text('Model: o3'));
      final effortRect = tester.getRect(find.text('Reasoning effort: High'));
      expect(effortRect.left, modelRect.left);
      expect(effortRect.top, greaterThan(modelRect.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reasoning popup fits narrow windows in both languages', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => scope.provider.initialized);
    await scope.provider.saveService(
      name: 'DeepSeek',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['deepseek-flash'],
      apiKey: 'key',
    );
    for (final type in ThemeType.values) {
      theme.setTheme(type);
      for (final locale in ['en', 'zh']) {
        await tester.pumpWidget(app(scale: 1.6, locale: locale));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('ai-reasoning-panel')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<AppCapsuleSlider>(
                find.byKey(const ValueKey('ai-reasoning-slider')),
              )
              .divisions,
          3,
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'reasoning-${type.name}-$locale');
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets(
    'empty model menu shows its empty state without a duplicate service shortcut',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
      await tester.pump();
      double menuOpacity() => tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('ai-model-menu-fade')),
          )
          .opacity
          .value;
      expect(menuOpacity(), 0);
      await tester.pump(const Duration(milliseconds: 75));
      expect(menuOpacity(), closeTo(.5, .01));
      await tester.pump(const Duration(milliseconds: 75));
      expect(menuOpacity(), 1);
      await tester.pumpAndSettle();
      final menuRect = tester.getRect(
        find.byKey(const ValueKey('ai-model-menu-surface')),
      );
      expect(menuRect.width, lessThanOrEqualTo(280));
      final scrollbar = find.byKey(const ValueKey('ai-model-list-scrollbar'));
      final list = find.byKey(const ValueKey('ai-model-list-scroll'));
      expect(tester.widget<Scrollbar>(scrollbar).thumbVisibility, isNull);
      expect(
        tester.getRect(scrollbar).right - tester.getRect(list).right,
        closeTo(20, .1),
      );
      expect(menuRect.right - tester.getRect(scrollbar).right, closeTo(4, .1));
      final selectorRect = tester.getRect(
        find.byKey(const ValueKey('ai-model-selector')),
      );
      final titleRect = tester.getRect(
        find.byKey(const ValueKey('ai-model-menu-title')),
      );
      expect(menuRect.right, closeTo(selectorRect.right - 16, 1));
      expect(menuRect.right, lessThanOrEqualTo(784));
      expect(titleRect.top - menuRect.top, 10);
      expect(
        tester.getRect(find.byKey(const ValueKey('ai-model-search'))).top -
            titleRect.bottom,
        8,
      );
      expect(menuRect.height, lessThan(280));
      expect(
        find.text('No model services yet. Add a service to get started.'),
        findsOneWidget,
      );
      expect(navigation.currentPage, AppPage.home);
      expect(find.text('Add model service'), findsNothing);
      await capture(tester, 'model-selector-empty-compact');
      expect(tester.takeException(), isNull);
    },
  );
}
