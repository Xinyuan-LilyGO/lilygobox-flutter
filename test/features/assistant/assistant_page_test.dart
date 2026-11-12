/*
 * @Description: 验证 AI 主页居中与底部输入状态、键盘发送、直达设置及缩放布局。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 11:16:04
 * @LastEditTime: 2026-11-12 11:40:05
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
    Widget? content,
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
        scrollbarTheme: const ScrollbarThemeData(
          crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
        ),
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
          child:
              content ??
              (settings ? const SettingsSplitView() : const AssistantPage()),
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

  for (final stop in [false, true]) {
    testWidgets(
      'stream follows bottom until upward wheel interrupts and hides actions until terminal: stop=$stop',
      (tester) async {
        scope.dispose();
        final output = StreamController<List<int>>();
        addTearDown(output.close);
        scope = await createAssistantTestScope(
          theme: theme,
          language: language,
          shell: shell,
          splitView: splitView,
          client: MockClient.streaming((request, body) async {
            await body.drain<void>();
            return http.StreamedResponse(output.stream, 200);
          }),
        );
        await tester.runAsync(() => scope.provider.initialized);
        await scope.provider.saveService(
          name: 'Test',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://example.test/v1',
          models: ['test'],
          apiKey: 'key',
        );
        await tester.pumpWidget(app(disableAnimations: stop));
        unawaited(scope.provider.sendMessage('Start'));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        final replyId = scope.provider.messages.last.id;
        final userId = scope.provider.messages.first.id;
        final copy = find.byKey(ValueKey('ai-copy-message-$replyId'));
        final time = find.byKey(ValueKey('ai-message-time-$replyId'));
        final latest = find.byKey(const ValueKey('ai-scroll-to-latest'));
        expect(copy, findsNothing);
        expect(time, findsNothing);
        expect(find.byKey(ValueKey('ai-copy-message-$userId')), findsOneWidget);
        expect(latest, findsNothing);
        final list = find.byKey(const ValueKey('ai-message-scroll'));
        final scroll = tester.widget<SingleChildScrollView>(list).controller!;
        output.add(
          utf8.encode(
            'data: ' +
                jsonEncode({
                  'choices': [
                    {
                      'delta': {
                        'content': List.generate(
                          80,
                          (i) => 'Line $i: Streaming response.',
                        ).join('\n\n'),
                      },
                    },
                  ],
                }) +
                '\n\n',
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(scope.provider.busy, isTrue);
        expect(scroll.position.extentAfter, lessThanOrEqualTo(1));
        expect(latest, findsNothing);
        expect(copy, findsNothing);
        expect(time, findsNothing);
        // 新一批输出触发跟随动画后，立即用真实滚轮向上打断。
        output.add(
          utf8.encode(
            'data: ' +
                jsonEncode({
                  'choices': [
                    {
                      'delta': {
                        'content': List.filled(
                          15,
                          '\n\nMore streaming text.',
                        ).join(),
                      },
                    },
                  ],
                }) +
                '\n\n',
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        final wheelStart = scroll.offset;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getTopLeft(list) + const Offset(100, 100),
            scrollDelta: const Offset(0, -300),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getTopLeft(list) + const Offset(100, 100),
            scrollDelta: const Offset(0, -300),
          ),
        );
        await tester.pumpAndSettle();
        final readingOffset = scroll.offset;
        // 连续向上滚轮必须累计目标，不能因解除跟随而反复重置动画。
        expect(readingOffset, closeTo(wheelStart - 600, 1));
        expect(scroll.position.extentAfter, greaterThan(120));
        expect(latest, findsOneWidget);
        // 后续输出继续增长也不能拉走用户的阅读位置。
        output.add(
          utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': '\n\nLater output. ' * 100},
                },
              ],
            })}\n\n',
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(readingOffset, 1));
        expect(copy, findsNothing);
        // 点击回到最新消息恢复跟随。
        await tester.tap(latest);
        await tester.pumpAndSettle();
        expect(scroll.position.extentAfter, lessThanOrEqualTo(1));
        output.add(
          utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': '\n\nFollowing again. ' * 40},
                },
              ],
            })}\n\n',
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(scroll.position.extentAfter, lessThanOrEqualTo(1));
        expect(latest, findsNothing);
        if (stop) {
          scope.provider.stopGeneration();
        } else {
          output.add(utf8.encode('data: [DONE]\n\n'));
          await tester.runAsync(output.close);
        }
        await pumpAssistantUntilIdle(tester);
        await tester.pumpAndSettle();
        expect(copy, findsOneWidget);
        expect(time, findsOneWidget);
        expect(
          scope.provider.messages.last.status,
          stop ? AiResponseStatus.stopped : AiResponseStatus.completed,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('queued message heading stays fixed while items scroll', (
    tester,
  ) async {
    await tester.runAsync(() => scope.provider.initialized);
    await scope.provider.saveService(
      name: 'Test',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['test'],
      apiKey: 'key',
    );
    responseGate = Completer<void>();
    unawaited(scope.provider.sendMessage('Start'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 9; i++) {
      await scope.provider.sendMessage('Queued item $i');
    }
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final heading = find.byKey(const ValueKey('ai-pending-guidance-heading'));
    final list = find.byKey(const ValueKey('ai-pending-guidance-scroll'));
    final controller = tester.widget<SingleChildScrollView>(list).controller!;
    expect(
      ScrollbarTheme.of(tester.element(list)).crossAxisMargin,
      AppScrollBehavior.scrollbarEdgeInset - 4,
    );
    final conversation = find.byKey(const ValueKey('ai-message-scroll'));
    expect(
      ScrollbarTheme.of(tester.element(conversation)).crossAxisMargin,
      AppScrollBehavior.scrollbarEdgeInset,
    );
    final headingRect = tester.getRect(heading);
    final firstItem = find.byKey(
      ValueKey(scope.provider.pendingGuidance.first.id),
    );
    final initialItemTop = tester.getTopLeft(firstItem).dy;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(headingRect.bottom, lessThanOrEqualTo(tester.getRect(list).top));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(tester.getTopLeft(firstItem).dy, lessThan(initialItemTop));
    expect(tester.getRect(heading), headingRect);
    expect(find.text('Queued messages (9)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-queue-attachments-divider')),
      findsNothing,
    );
    tester.widget<ChatComposer>(find.byType(ChatComposer)).onAttachmentsChanged([
      AiImageAttachment(
        name: 'draft.png',
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
        mimeType: 'image/png',
      ),
    ]);
    await tester.pumpAndSettle();
    final divider = find.byKey(const ValueKey('ai-queue-attachments-divider'));
    expect(divider, findsOneWidget);
    expect(tester.widget<Divider>(divider).color, theme.themeData.dividerColor);
    final attachmentsList = find.byKey(const ValueKey('ai-attachments-scroll'));
    expect(
      tester.getRect(divider).top - tester.getRect(list).bottom,
      closeTo(8, .1),
    );
    expect(
      tester.getRect(attachmentsList).top - tester.getRect(divider).bottom,
      closeTo(8, .1),
    );
    // 滚到底后按最后一张卡片的真实边缘核对，不只测滚动容器。
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final lastQueue = find.byKey(
      ValueKey(scope.provider.pendingGuidance.last.id),
    );
    expect(
      tester.getRect(divider).top - tester.getRect(lastQueue).bottom,
      closeTo(8, .1),
    );
    final firstImage = find
        .descendant(of: attachmentsList, matching: find.byType(Image))
        .first;
    expect(
      tester.getRect(firstImage).top - tester.getRect(divider).bottom,
      closeTo(8, .1),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('ai-pending-guidance'))).height,
      lessThanOrEqualTo(174),
    );
    expect(tester.takeException(), isNull);
    scope.provider.stopGeneration();
    responseGate!.complete();
    await pumpAssistantUntilIdle(tester);
  });

  testWidgets(
    'running turns queue messages and automatically send them as separate turns',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      responseGate = Completer<void>();
      await tester.pumpWidget(app());
      final field = find.byKey(const ValueKey('ai-message-input'));
      await tester.enterText(field, 'Start');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(scope.provider.busy, isTrue);
      await tester.enterText(field, 'Please use Chinese');
      await tester.pump();
      final send = find.byKey(const ValueKey('ai-send-button'));
      expect(send, findsOneWidget);
      await tester.tap(send);
      await tester.pumpAndSettle();
      final pending = find.byKey(const ValueKey('ai-pending-guidance'));
      expect(pending, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ai-composer-context-layer')),
          matching: pending,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ai-composer-input-layer')),
          matching: pending,
        ),
        findsNothing,
      );
      expect(find.text('Queued messages (1)'), findsOneWidget);
      expect(scope.provider.messages, hasLength(2));
      expect(requests, 1);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
      expect(find.byKey(const ValueKey('ai-stop-button')), findsOneWidget);
      await tester.enterText(field, 'Discard this one');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final discarded = scope.provider.pendingGuidance.last;
      await tester.tap(
        find.byKey(ValueKey('ai-remove-guidance-${discarded.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        scope.provider.pendingGuidance.single.content,
        'Please use Chinese',
      );
      final queued = scope.provider.pendingGuidance.single;
      await tester.tap(find.byKey(ValueKey('ai-edit-guidance-${queued.id}')));
      await tester.pumpAndSettle();
      expect(scope.provider.pendingGuidance, isEmpty);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Please use Chinese',
      );
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(
        find.byKey(ValueKey('ai-edit-queue-input-${queued.id}')),
        findsNothing,
      );
      await tester.enterText(field, 'Use Chinese briefly');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        scope.provider.pendingGuidance.single.content,
        'Use Chinese briefly',
      );
      await capture(tester, 'pending-guidance');
      responseGate!.complete();
      await pumpAssistantUntilIdle(tester);
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(pending, findsNothing);
      expect(find.text('Use Chinese briefly'), findsOneWidget);
      expect(scope.provider.messages, hasLength(4));
      expect(scope.provider.messages[2].role, 'user');
      expect(scope.provider.messages[2].content, 'Use Chinese briefly');
      final reply = scope.provider.messages.last;
      await tester.tap(find.byKey(ValueKey('ai-response-details-${reply.id}')));
      await tester.pumpAndSettle();
      expect(find.text('User guidance'), findsNothing);
      expect(
        (jsonDecode(requestBodies.last)['messages'] as List).last['content'],
        'Use Chinese briefly',
      );
    },
  );

  testWidgets('Ctrl+V reaches the image paste action inside the text field', (
    tester,
  ) async {
    final input = TextEditingController();
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(input.dispose);
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    var reads = 0;
    List<AiImageAttachment> attachments = [];
    await tester.pumpWidget(
      app(
        content: Align(
          alignment: Alignment.bottomCenter,
          child: ChatComposer(
            input: input,
            focusNode: focus,
            scrollController: scroll,
            theme: theme.themeData,
            assistant: scope.provider,
            ready: true,
            onSend: (_) {},
            attachments: const [],
            onAttachmentsChanged: (value) => attachments = value,
            readClipboardImage: () async {
              reads++;
              return bytes;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ai-message-input')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(attachments.single.bytes, bytes);
    expect(input.text, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('text-only capability blocks image sends and history replay', (
    tester,
  ) async {
    await tester.runAsync(() => scope.provider.initialized);
    final id = await scope.provider.saveService(
      name: 'Gateway',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['chat'],
      apiKey: 'key',
      imageInputs: {'chat': AiImageInput.unsupported},
    );
    final image = AiImageAttachment(
      name: 'image.png',
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      ),
      mimeType: 'image/png',
    );
    await scope.provider.sendMessage('Describe', attachments: [image]);
    expect(requests, 0);
    expect(scope.provider.messages, isEmpty);
    await scope.provider.saveService(
      id: id,
      name: 'Gateway',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['chat'],
      imageInputs: {},
    );
    await tester.runAsync(
      () => scope.provider.sendMessage('Describe', attachments: [image]),
    );
    expect(requests, 1);
    final messageCount = scope.provider.messages.length;
    await scope.provider.saveService(
      id: id,
      name: 'Gateway',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['chat'],
      imageInputs: {'chat': AiImageInput.unsupported},
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ai-message-input'));
    await tester.enterText(field, 'Keep this draft');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send-button')));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, 'Keep this draft');
    expect(scope.provider.messages.length, messageCount);
    expect(requests, 1);
    await scope.provider.sendMessage('Blocked history');
    expect(scope.provider.messages.length, messageCount);
    expect(requests, 1);
  });

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
      final messageList = find.byKey(const ValueKey('ai-message-scroll'));
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
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('ai-message-scroll')),
          )
          .controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('ai-scroll-to-latest'));
      expect(button, findsNothing);
      final original = controller.offset;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(
            find.byKey(const ValueKey('ai-message-scroll')),
          ),
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
      expect(tester.getSize(button).width, 28);
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

  testWidgets(
    'one latest click reaches the end of mixed image messages',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      final image = AiImageAttachment(
        name: 'image.png',
        mimeType: 'image/png',
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      );
      for (var i = 0; i < 16; i++) {
        await tester.runAsync(
          () => scope.provider.sendMessage(
            i < 4
                ? 'Short message'
                : List.filled(8, 'An image description line').join('\n'),
            attachments: [image],
          ),
        );
      }
      await tester.pumpWidget(
        app(disableAnimations: latestMotionVariant.currentValue!),
      );
      await tester.pumpAndSettle();
      final sentImages = find.descendant(
        of: find.byKey(const ValueKey('ai-message-scroll')),
        matching: find.byType(Image),
      );
      expect(tester.getSize(sentImages.first), const Size(100, 100));
      tester
          .widget<ChatComposer>(find.byType(ChatComposer))
          .onAttachmentsChanged([image]);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('ai-message-scroll')),
          )
          .controller!;
      final extent = controller.position.maxScrollExtent;
      // Mixed-height messages must not change the scrollbar mapping as we scroll.
      for (final fraction in [.2, .5, .8, .35, 1.0, 0.0]) {
        controller.jumpTo(extent * fraction);
        await tester.pumpAndSettle();
        expect(controller.position.maxScrollExtent, closeTo(extent, .1));
        expect(controller.offset, closeTo(extent * fraction, .1));
      }
      controller.jumpTo(1);
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('ai-scroll-to-latest'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.position.extentAfter, closeTo(0, 1));
      expect(button, findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: latestMotionVariant,
  );

  testWidgets('many draft images wrap and scroll without covering the editor', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    final images = List.generate(
      40,
      (index) => AiImageAttachment(
        name: 'image-$index.png',
        bytes: bytes,
        mimeType: 'image/png',
      ),
    );
    tester
        .widget<ChatComposer>(find.byType(ChatComposer))
        .onAttachmentsChanged(images);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ai-composer-attachment-layer')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-queue-attachments-divider')),
      findsNothing,
    );
    final list = find.byKey(const ValueKey('ai-attachments-scroll'));
    final bar = find.byKey(const ValueKey('ai-attachments-scrollbar'));
    final controller = tester.widget<SingleChildScrollView>(list).controller!;
    expect(tester.getSize(list).height, lessThanOrEqualTo(166));
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(tester.widget<Scrollbar>(bar).thumbVisibility, isNull);
    final thumbnails = find.descendant(of: list, matching: find.byType(Image));
    final firstRect = tester.getRect(thumbnails.first);
    expect(firstRect.width, lessThan(100));
    final row = thumbnails
        .evaluate()
        .map((element) => tester.getRect(find.byWidget(element.widget)))
        .where((rect) => (rect.top - firstRect.top).abs() < .1)
        .toList();
    expect(row, hasLength(10));
    expect(row.last.right, closeTo(tester.getRect(list).right - 12, .1));
    expect(
      firstRect.left - tester.getRect(list).left,
      closeTo(tester.getRect(list).right - row.last.right, .1),
    );
    final original = controller.offset;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, 100),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(controller.offset, greaterThan(original));
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final last = find.descendant(of: list, matching: find.byType(Image)).last;
    expect(
      tester.getRect(last).bottom,
      lessThanOrEqualTo(tester.getRect(list).bottom + .1),
    );
    expect(
      tester.getRect(last).right,
      lessThanOrEqualTo(tester.getRect(bar).right - 11.9),
    );
    expect(
      tester.getRect(list).bottom,
      lessThanOrEqualTo(
        tester
                .getRect(find.byKey(const ValueKey('ai-composer-input-layer')))
                .top +
            .1,
      ),
    );
    // 滚到最后一张后仍可删除，回调保留其他附件。
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(last));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-remove-image-button')).last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChatComposer>(find.byType(ChatComposer)).attachments.length,
      39,
    );
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing key opens model services without losing the draft', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ai-message-input'));
    await tester.enterText(field, 'Keep this draft');
    await tester.pump();
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

    final stopButton = find.byKey(const ValueKey('ai-stop-button'));
    expect(stopButton, findsOneWidget);
    expect(
      tester.widget<TitleBarIconButton>(stopButton).icon,
      Symbols.stop_rounded,
    );
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
    'square stop button ends the turn and preserves the unsent draft',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      responseGate = Completer<void>();
      await tester.pumpWidget(app());
      final field = find.byKey(const ValueKey('ai-message-input'));
      await tester.enterText(field, 'Start');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      final button = find.byKey(const ValueKey('ai-stop-button'));
      expect(
        tester.widget<TitleBarIconButton>(button).icon,
        Symbols.stop_rounded,
      );
      await tester.tap(button);
      await tester.pump();
      await tester.enterText(field, 'Unsent draft');
      responseGate!.complete();
      await pumpAssistantUntilIdle(tester);
      expect(scope.provider.error, isNull);
      expect(
        scope.provider.messages
            .where((item) => item.role == 'assistant')
            .every((item) => item.content.isEmpty),
        isTrue,
      );
      expect(tester.widget<TextField>(field).controller!.text, 'Unsent draft');
      expect(button, findsNothing);
      expect(find.byKey(const ValueKey('ai-send-button')), findsOneWidget);
      expect(find.text('Resume response'), findsNothing);
      await tester.enterText(field, '');
      await tester.pump();
      final continueButton = find.byKey(const ValueKey('ai-continue-button'));
      expect(
        tester.widget<TitleBarIconButton>(continueButton).icon,
        Symbols.play_arrow_rounded,
      );
      await tester.tap(continueButton);
      await pumpAssistantUntilIdle(tester);
      expect(requests, 2);
      expect(continueButton, findsNothing);
      expect(
        scope.provider.messages.last.content,
        'Ready to help with LilygoBox.',
      );
    },
  );

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

  testWidgets(
    'tool preamble and answer have separate ordered elapsed sections',
    (tester) async {
      showProcess = true;
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      await tester.pumpWidget(app());
      await tester.enterText(
        find.byKey(const ValueKey('ai-message-input')),
        'Switch theme',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await pumpAssistantUntilIdle(tester);
      await tester.pumpAndSettle();
      final replies = scope.provider.messages
          .where((message) => message.role == 'assistant')
          .toList();
      expect(replies, hasLength(2));
      final firstHeader = find.byKey(
        ValueKey('ai-response-details-${replies.first.id}'),
      );
      final nextHeader = find.byKey(
        ValueKey('ai-response-details-${replies.last.id}'),
      );
      final preamble = find.text('Updating the theme.', findRichText: true);
      final answer = find.text(
        'Ready to help with LilygoBox.',
        findRichText: true,
      );
      expect(firstHeader, findsOneWidget);
      expect(nextHeader, findsOneWidget);
      expect(preamble, findsOneWidget);
      expect(answer, findsOneWidget);
      expect(
        tester.getTopLeft(firstHeader).dy,
        lessThan(tester.getTopLeft(preamble).dy),
      );
      expect(
        tester.getTopLeft(preamble).dy,
        lessThan(tester.getTopLeft(nextHeader).dy),
      );
      expect(
        tester.getTopLeft(nextHeader).dy,
        lessThan(tester.getTopLeft(answer).dy),
      );
      expect(replies.first.processingSteps, isEmpty);
      expect(replies.last.processingSteps.single.name, 'set_theme');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'select all always includes elapsed heading and only visible details',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      await tester.pumpWidget(app());
      unawaited(scope.provider.sendMessage('USER_SELECTION_TEST'));
      await pumpAssistantUntilIdle(tester);
      await tester.pumpAndSettle();
      final reply = scope.provider.messages.last;
      final header = find.byKey(ValueKey('ai-response-details-${reply.id}'));
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      bool selected(Finder root) => find
          .descendant(of: root, matching: find.byType(RichText))
          .evaluate()
          .any(
            (element) => (element.renderObject! as RenderParagraph).selections
                .any((selection) => !selection.isCollapsed),
          );
      region.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(selected(find.text('USER_SELECTION_TEST')), isTrue);
      expect(selected(header), isTrue);
      await tester.ensureVisible(header);
      region.hideToolbar();
      await tester.pumpAndSettle();
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(selected(header), isFalse);
      expect(selected(find.text('USER_SELECTION_TEST')), isFalse);
      region.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(selected(header), isTrue);
      expect(
        selected(find.byKey(const ValueKey('ai-response-details-expanded'))),
        isTrue,
      );
      expect(find.byType(SelectableText), findsNothing);
      region.hideToolbar();
      await tester.pumpAndSettle();
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(selected(header), isFalse);
      expect(selected(find.text('USER_SELECTION_TEST')), isFalse);
      region.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(selected(header), isTrue);
      expect(
        find.byKey(const ValueKey('ai-response-details-expanded')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('clicking editor padding and toolbar whitespace focuses text', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ai-message-input'));
    final focus = tester.widget<TextField>(field).focusNode!;
    final rect = tester.getRect(
      find.byKey(const ValueKey('ai-composer-input-layer')),
    );
    for (final point in [
      rect.topCenter + const Offset(0, 4),
      rect.centerLeft + const Offset(4, 0),
      rect.bottomCenter - const Offset(0, 15),
    ]) {
      focus.unfocus();
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      final gesture = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(focus.hasFocus, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(focus.hasFocus, isTrue);
      await gesture.up();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      // 已聚焦时再次按下，不能先失焦再等松开恢复。
      final held = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(focus.hasFocus, isTrue);
      await held.up();
      await tester.pump();
    }
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
            find.byKey(const ValueKey('ai-stop-button')),
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

  for (final reasoning in [false, true]) {
    testWidgets(
      'model list reveals selection and pins the visible service: reasoning=$reasoning',
      (tester) async {
        await tester.runAsync(() => scope.provider.initialized);
        await scope.provider.saveService(
          name: 'First service',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://first.test/v1',
          models: List.generate(20, (i) => 'first-$i'),
          apiKey: 'key',
        );
        final selectedModel = reasoning ? 'o3' : 'chosen-model';
        final service = await scope.provider.saveService(
          name: 'Second service',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://second.test/v1',
          models: [
            ...List.generate(15, (i) => 'second-$i'),
            selectedModel,
            ...List.generate(15, (i) => 'last-$i'),
          ],
          apiKey: 'key',
        );
        await scope.provider.selectModel(service, selectedModel);
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        final trigger = find.byKey(const ValueKey('ai-model-selector'));
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        if (reasoning) {
          await tester.tap(find.byKey(const ValueKey('ai-reasoning-models')));
          await tester.pumpAndSettle();
        }
        final list = find.byKey(const ValueKey('ai-model-list-scroll'));
        final controller = tester
            .widget<SingleChildScrollView>(list)
            .controller!;
        final selected = find.byKey(
          ValueKey('ai-model-$service-$selectedModel'),
        );
        final viewport = tester.getRect(list);
        final row = tester.getRect(selected);
        final pinned = find.byKey(const ValueKey('ai-model-pinned-service'));
        expect(row.top, closeTo(tester.getRect(pinned).bottom, 1));
        expect(row.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(controller.offset, greaterThan(0));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('ai-model-pinned-service')),
            matching: find.text('Second service'),
          ),
          findsOneWidget,
        );
        final search = find.byKey(const ValueKey('ai-model-search'));
        expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);
        controller.jumpTo(100);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('ai-model-pinned-service')),
            matching: find.text('First service'),
          ),
          findsOneWidget,
        );
        await tester.enterText(search, 'no match');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('ai-model-pinned-service')),
          findsNothing,
        );
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        if (reasoning) {
          await tester.tap(find.byKey(const ValueKey('ai-reasoning-models')));
          await tester.pumpAndSettle();
        }
        expect(
          tester.getRect(selected).top,
          closeTo(tester.getRect(pinned).bottom, 1),
        );
        expect(
          tester.getRect(selected).bottom,
          lessThanOrEqualTo(tester.getRect(list).bottom),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

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
        closeTo(16, .1),
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
