/*
 * @Description: 验证 AI 主页居中与底部输入状态、键盘发送、直达设置及缩放布局。
 */

import 'package:lilygobox/core/l10n/delegates.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/app_capsule_slider.dart';
import 'package:lilygobox/core/widgets/title_bar_icon_button.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/data/agent_package.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_composer.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_content_window.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_scrollbar.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/code_block.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/message_content.dart';
import 'package:lilygobox/features/settings/presentation/widgets/split_view.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/model_selector.dart';
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
  var failWebTool = false;
  var showTimeTool = false;
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
    failWebTool = false;
    showTimeTool = false;
    requestBodies.clear();
    if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
      final inter = FontLoader('LilygoBoxInter')
        ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf'));
      final defaultFont = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/Roboto/Roboto-Variable.ttf'));
      final symbols =
          FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
            ..addFont(
              rootBundle.load(
                'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
              ),
            );
      final outlined =
          FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
            ..addFont(
              rootBundle.load(
                'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
              ),
            );
      final chinese = File('${Platform.environment['WINDIR']}/Fonts/msyh.ttc');
      if (await chinese.exists()) {
        await (FontLoader('AssistantCaptureCjk')..addFont(
              Future.value(ByteData.sublistView(await chinese.readAsBytes())),
            ))
            .load();
      }
      await Future.wait([
        inter.load(),
        defaultFont.load(),
        symbols.load(),
        outlined.load(),
      ]);
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
                'message': failWebTool && requests == 1
                    ? {
                        'content': null,
                        'tool_calls': [
                          {
                            'id': 'web-call',
                            'type': 'function',
                            'function': {
                              'name': 'read_webpage',
                              'arguments': '{"url":"http://example.com"}',
                            },
                          },
                        ],
                      }
                    : showProcess && requests == 1
                    ? {
                        'content': 'Updating the theme.',
                        'reasoning_content': 'Inspect the current theme.',
                        'tool_calls': [
                          {
                            'id': 'theme-call',
                            'type': 'function',
                            'function': {
                              'name': showTimeTool
                                  ? 'get_current_time'
                                  : 'set_theme',
                              'arguments': showTimeTool
                                  ? '{}'
                                  : '{"theme":"dark"}',
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
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        scrollbarTheme: const ScrollbarThemeData(
          crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
        ),
        colorScheme: theme.themeData.materialColors,
        fontFamily: 'LilygoBoxInter',
        fontFamilyFallback: const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')
            ? const ['AssistantCaptureCjk']
            : null,
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

  testWidgets(
    'one wheel notch over MSG-04106 preserves message interaction and travel',
    (tester) async {
      final package = (await tester.runAsync(
        () => AgentPackage.read(
          'artifacts/lilygobox-long-chat-10000.7z',
        ),
      ))!;
      final record = (package['workflow']['sessions'] as List).single;
      scope.provider.restoreWorkspaceConversation(
        Map<String, dynamic>.from(record['conversation'] as Map),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in [const Size(2048, 1220), const Size(1000, 680)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(app(locale: 'zh'));
        await tester.pumpAndSettle();
        tester
            .widget<ChatHistoryScrollbar>(find.byType(ChatHistoryScrollbar))
            .seek(.41055, true);
        await tester.pumpAndSettle();
        final button = find.byKey(
          const ValueKey('ai-copy-message-fixture-4106'),
        );
        expect(button.hitTestable(), findsOneWidget);
        for (final delta in [-100.0, 100.0]) {
          final start = tester.getCenter(button);
          await tester.sendEventToBinding(
            PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position: start,
              scrollDelta: Offset(0, delta),
            ),
          );
          await tester.pump();
          for (var frame = 1; frame <= 25; frame++) {
            await tester.pump(const Duration(milliseconds: 8));
            final remaining = 1 - frame / 25;
            expect(
              tester.getCenter(button).dy,
              closeTo(
                start.dy - delta * (1 - remaining * remaining * remaining),
                .1,
              ),
              reason: '$size frame $frame',
            );
            expect(
              button.hitTestable(),
              findsOneWidget,
              reason: '$size frame $frame',
            );
          }
          await tester.pumpAndSettle();
          expect(tester.getCenter(button).dy, closeTo(start.dy - delta, .1));
        }
      }
    },
  );

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

  for (final locale in ['en', 'zh']) {
    for (final kind in ['primary', 'permanent']) {
      testWidgets('agent source shows $kind role and icon in $locale', (
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
        await tester.runAsync(
          () => scope.provider.receiveAgentMessage(
            sourceId: '123-1',
            sourceTitle: 'Writer',
            sourceKind: kind,
            content: 'Progress report.',
          ),
        );
        await tester.pumpWidget(app(locale: locale));
        await tester.pumpAndSettle();
        final message = scope.provider.messages.firstWhere(
          (message) => message.toolName == 'agent_message',
        );
        final heading = find.byKey(
          ValueKey('agent-message-source-${message.id}'),
        );
        final expectedLabel = locale == 'zh'
            ? (kind == 'primary' ? '来自主智能体：Writer' : '来自子智能体：Writer')
            : (kind == 'primary'
                  ? 'From main agent: Writer'
                  : 'From child agent: Writer');
        expect(tester.widget<Text>(heading).data, expectedLabel);
        final sourceRow = find
            .ancestor(of: heading, matching: find.byType(Row))
            .first;
        final icon = tester.widget<Icon>(
          find.descendant(of: sourceRow, matching: find.byType(Icon)),
        );
        expect(
          icon.icon,
          kind == 'primary'
              ? Symbols.hub_rounded
              : Symbols.account_tree_rounded,
        );
        expect(icon.fill, 1);
        expect(
          find.byKey(ValueKey('agent-message-source-id-${message.id}')),
          findsOneWidget,
        );
        expect(message.toolArguments?['source_agent_kind'], kind);
        final snapshot = scope.provider.snapshotWorkspaceConversation();
        scope.provider.clearConversation();
        scope.provider.restoreWorkspaceConversation(snapshot);
        expect(
          scope.provider.messages
              .firstWhere((item) => item.id == message.id)
              .toolArguments?['source_agent_kind'],
          kind,
        );
      });
    }
    testWidgets('timer notification is not labeled as an agent in $locale', (
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
      await tester.runAsync(
        () => scope.provider.receiveAgentMessage(
          sourceId: 'timer:123-1',
          sourceTitle: 'Timer',
          content: 'Timer expired.',
        ),
      );
      await tester.pumpWidget(app(locale: locale));
      await tester.pumpAndSettle();
      final message = scope.provider.messages.firstWhere(
        (message) => message.toolName == 'agent_message',
      );
      final heading = find.byKey(
        ValueKey('agent-message-source-${message.id}'),
      );
      expect(
        tester.widget<Text>(heading).data,
        locale == 'zh' ? '计时器' : 'Timer',
      );
      expect(
        find.byKey(ValueKey('agent-message-source-id-${message.id}')),
        findsNothing,
      );
      expect(
        tester
            .widget<InkWell>(
              find.ancestor(of: heading, matching: find.byType(InkWell)).first,
            )
            .onTap,
        isNull,
      );
      expect(message.toolArguments?['source_agent_id'], 'timer:123-1');
    });
  }

  testWidgets(
    'async restored conversation opens at the latest message and preserves a valid reading position',
    (tester) async {
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
          List.generate(80, (i) => 'History paragraph $i.').join('\n\n'),
        ),
      );
      final snapshot = scope.provider.snapshotWorkspaceConversation();
      scope.provider.clearConversation();
      final bucket = PageStorageBucket();
      Widget conversation() =>
          PageStorage(bucket: bucket, child: const AssistantPage());
      await tester.pumpWidget(app(content: conversation()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-scroll')), findsNothing);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        scope.provider.restoreWorkspaceConversation(snapshot);
      });
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('ai-message-scroll')),
          )
          .controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(scroll.position.extentAfter, lessThanOrEqualTo(1));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(content: const SizedBox.shrink()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(content: conversation()));
      await tester.pumpAndSettle();
      final restored = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('ai-message-scroll')),
          )
          .controller!;
      expect(restored.offset, 0);
      expect(restored.position.extentAfter, greaterThan(120));
      expect(tester.takeException(), isNull);
    },
  );

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
        for (final metricKey in [
          const ValueKey('ai-cache-usage-metric'),
          const ValueKey('ai-context-usage-metric'),
        ]) {
          final metric = find.byKey(metricKey);
          expect(metric, findsOneWidget);
          await tester.tap(metric);
          await tester.pumpAndSettle();
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        }
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
        final visibleText = find
            .descendant(of: list, matching: find.byType(RichText))
            .evaluate()
            .map((element) => element.widget as RichText)
            .firstWhere((widget) => widget.text.toPlainText().trim().isNotEmpty)
            .text
            .toPlainText();
        final visibleAnchor = find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == visibleText,
        );
        final visibleAnchorTop = tester.getTopLeft(visibleAnchor).dy;
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
        // 正文窗口会校正滚动原点；阅读内容仍应随滚轮向下移动。
        expect(readingOffset, isNot(wheelStart));
        expect(tester.getTopLeft(visibleAnchor).dy, lessThan(visibleAnchorTop));
        expect(scroll.position.extentAfter, greaterThan(120));
        expect(latest, findsOneWidget);
        // 后续输出继续增长也不能拉走用户的阅读位置。
        final readingTop = tester.getTopLeft(visibleAnchor).dy;
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
        expect(tester.getTopLeft(visibleAnchor).dy, closeTo(readingTop, 1));
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

  testWidgets('queued agent messages show their role, icon and complete ID', (
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
    final gate = responseGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    unawaited(scope.provider.sendMessage('Start'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    const senders = [
      ('primary', '1794989955026711-0', 'main', Symbols.hub_rounded),
      (
        'permanent',
        '1794989955026711-1',
        'child',
        Symbols.account_tree_rounded,
      ),
    ];
    for (final (kind, id, role, _) in senders) {
      await scope.provider.receiveAgentMessage(
        sourceId: id,
        sourceTitle: 'Writer',
        sourceKind: kind,
        content: 'Queued $role report',
      );
    }
    await scope.provider.sendMessage('Human follow-up');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final messages = scope.provider.pendingGuidance;
    expect(messages, hasLength(3));
    final queue = find.byKey(const ValueKey('ai-pending-guidance'));
    for (final (index, (_, id, role, icon)) in senders.indexed) {
      final message = messages[index];
      final item = find.descendant(
        of: queue,
        matching: find.byKey(ValueKey(message.id)),
      );
      expect(
        find.descendant(of: item, matching: find.byIcon(icon)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: item,
          matching: find.text('From $role agent: Writer'),
        ),
        findsOneWidget,
      );
      final sourceId = find.descendant(
        of: item,
        matching: find.text('Agent ID: $id'),
      );
      expect(sourceId, findsOneWidget);
      expect(
        tester.getRect(sourceId).bottom,
        lessThanOrEqualTo(tester.getRect(find.text(message.content)).top),
      );
    }
    expect(find.text('Human follow-up'), findsOneWidget);
    expect(
      find.byKey(ValueKey('agent-message-source-${messages.last.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('agent-message-source-id-${messages.last.id}')),
      findsNothing,
    );
    gate.complete();
    await pumpAssistantUntilIdle(tester);
    expect(tester.takeException(), isNull);
  });

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
    tester.widget<ChatComposer>(find.byType(ChatComposer)).onAttachmentsChanged(
      [
        AiImageAttachment(
          name: 'draft.png',
          bytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
          ),
          mimeType: 'image/png',
        ),
      ],
    );
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

  testWidgets('running turns show pending manual guidance until it applies', (
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
    expect(scope.provider.pendingGuidance.single.content, 'Please use Chinese');
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
    final edited = scope.provider.pendingGuidance.single;
    await tester.tap(find.byKey(ValueKey('ai-steer-guidance-${edited.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Waiting to apply guidance…'), findsOneWidget);
    expect(requests, 1);
    responseGate!.complete();
    await pumpAssistantUntilIdle(tester);
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(pending, findsNothing);
    expect(find.text('Waiting to apply guidance…'), findsNothing);
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
  });

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
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
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
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
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

  testWidgets('hidden conversation defers provider rebuilds until shown', (
    tester,
  ) async {
    await tester.runAsync(() => scope.provider.initialized);
    await tester.pumpWidget(app(tickerEnabled: false));
    await tester.pumpAndSettle();
    final before = tester.widget<ChatComposer>(find.byType(ChatComposer));
    scope.provider.contextBudgetTokens = 64000;
    await tester.pump();
    expect(
      tester.widget<ChatComposer>(find.byType(ChatComposer)),
      same(before),
    );
    await tester.pumpWidget(app(tickerEnabled: true));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChatComposer>(find.byType(ChatComposer)),
      isNot(same(before)),
    );
    expect(scope.provider.contextBudgetTokens, 64000);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unchanged messages retain their content across provider updates',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      await tester.runAsync(
        () => scope.provider.sendMessage('Keep this history'),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final bodies = tester
          .widgetList<ChatMessageBody>(find.byType(ChatMessageBody))
          .toList();
      scope.provider.contextBudgetTokens = 64000;
      await tester.pump();
      final updated = tester
          .widgetList<ChatMessageBody>(find.byType(ChatMessageBody))
          .toList();
      expect(updated, hasLength(bodies.length));
      for (var index = 0; index < bodies.length; index++) {
        expect(updated[index], same(bodies[index]));
      }
      expect(tester.takeException(), isNull);
    },
  );

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
      expect(innerRect.left - outerRect.left, 4);
      expect(outerRect.right - innerRect.right, 4);
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
      final assistantSelection = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      assistantSelection.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      await tester.tapAt(
        tester.getCenter(find.text('Ready to help with LilygoBox.')),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final copyItem = find.ancestor(
        of: find.text('Copy'),
        matching: find.byType(MenuItemSurface),
      );
      expect(copyItem, findsOneWidget);
      expect(
        find.descendant(
          of: copyItem,
          matching: find.byIcon(Symbols.content_copy),
        ),
        findsOneWidget,
      );
      assistantSelection.hideToolbar();
      assistantSelection.clearSelection();
      await tester.pumpAndSettle();
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

  testWidgets('composer keeps selection tight and reserves a scrollbar gutter', (
    tester,
  ) async {
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
      find.descendant(of: scrollbar, matching: find.byType(Scrollbar)),
      findsNothing,
    );
    expect(
      tester.getRect(scrollbar).right - tester.getRect(field).right,
      closeTo(14, .1),
    );
    final controller = tester.widget<Scrollbar>(scrollbar).controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    final original = input.controller!.text;
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(scrollbar),
        scrollDelta: const Offset(0, 60),
        kind: PointerDeviceKind.mouse,
      ),
    );
    expect(controller.offset, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(controller.offset, inExclusiveRange(0, 60));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(60, .1));
    expect(input.controller!.text, original);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

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
    'live compaction shows the request stage and running elapsed time',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      final serviceId = await scope.provider.saveService(
        name: 'Summary service',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test-model'],
        apiKey: 'test-key',
      );
      await scope.provider.selectModel(serviceId, 'test-model');
      scope.provider.restoreWorkspaceConversation({
        'messages': [],
        'history': [
          for (var index = 0; index < 16; index++)
            {
              'role': index.isEven ? 'user' : 'assistant',
              'content': 'History $index',
            },
        ],
      });
      final gate = responseGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await tester.pumpWidget(app(locale: 'zh'));
      final pending = scope.provider.compactContext();
      await tester.pump();
      final header = find.textContaining('手动压缩上下文 · 正在连接 · 用时 ');
      final initial = tester.widget<Text>(header).data;
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(header).data, isNot(initial));
      expect(find.byIcon(Symbols.cloud_sync_rounded), findsOneWidget);
      gate.complete();
      for (
        var attempt = 0;
        attempt < 100 && scope.provider.compacting.value;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(scope.provider.compacting.value, isFalse);
      await pending;
      await tester.pumpAndSettle();
      expect(find.textContaining('手动压缩上下文 · 已完成 · 用时 '), findsOneWidget);
    },
  );

  testWidgets(
    'guided reply timing stays hidden while preflight compaction stops and resumes',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      final serviceId = await scope.provider.saveService(
        name: 'Summary service',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test-model'],
        apiKey: 'test-key',
      );
      await scope.provider.selectModel(serviceId, 'test-model');
      scope.provider.restoreWorkspaceConversation({
        'messages': [],
        'history': [
          for (var index = 0; index < 6; index++)
            {
              'role': index.isEven ? 'user' : 'assistant',
              'content': 'Previous history $index ${'context ' * 37}',
            },
        ],
      });
      scope.provider.contextBudgetTokens = 1000;
      final originalGate = Completer<void>();
      final compactionGate = Completer<void>();
      final resumedCompactionGate = Completer<void>();
      final guidedReplyGate = Completer<void>();
      for (final gate in [
        originalGate,
        compactionGate,
        resumedCompactionGate,
        guidedReplyGate,
      ]) {
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
      }
      Future<void> pumpUntilRequest(int count) async {
        for (var attempt = 0; attempt < 100 && requests < count; attempt++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        }
        expect(requests, count);
        await tester.pump();
      }

      await tester.pumpWidget(app(locale: 'zh'));
      responseGate = originalGate;
      final turn = scope.provider.sendMessage('Start');
      await pumpUntilRequest(1);
      responseGate = compactionGate;
      await scope.provider.sendMessage(
        'Change direction ${'follow-up ' * 170}',
        steer: true,
      );
      originalGate.complete();
      await pumpUntilRequest(2);

      expect(scope.provider.compacting.value, isTrue);
      final compaction = scope.provider.messages.singleWhere(
        (message) => message.role == 'compaction',
      );
      final guidedReply = scope.provider.messages.last;
      expect(compaction.toolArguments?['replyId'], guidedReply.id);
      final compactionTiming = find.byKey(
        ValueKey('ai-response-details-${compaction.id}'),
      );
      final replyTiming = find.byKey(
        ValueKey('ai-response-details-${guidedReply.id}'),
      );
      expect(compactionTiming, findsOneWidget);
      expect(replyTiming, findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(replyTiming, findsNothing);
      expect(requests, 2);

      await tester.tap(find.byKey(const ValueKey('ai-stop-button')));
      compactionGate.complete();
      await pumpAssistantUntilIdle(tester);
      await turn;
      expect(requests, 2);
      expect(find.textContaining('自动压缩上下文 · 已取消'), findsOneWidget);
      expect(replyTiming, findsNothing);

      responseGate = resumedCompactionGate;
      await tester.tap(find.byKey(const ValueKey('ai-continue-button')));
      await pumpUntilRequest(3);
      expect(scope.provider.compacting.value, isTrue);
      expect(compactionTiming, findsOneWidget);
      expect(replyTiming, findsNothing);
      expect(
        scope.provider.messages.where((item) => item.role == 'compaction'),
        hasLength(1),
      );

      responseGate = guidedReplyGate;
      resumedCompactionGate.complete();
      await pumpUntilRequest(4);
      expect(scope.provider.compacting.value, isFalse);
      expect(compactionTiming, findsOneWidget);
      expect(replyTiming, findsOneWidget);
      expect(
        tester.getTopLeft(compactionTiming).dy,
        lessThan(tester.getTopLeft(replyTiming).dy),
      );

      guidedReplyGate.complete();
      await pumpAssistantUntilIdle(tester);
    },
  );

  for (final automatic in [false, true]) {
    testWidgets(
      '${automatic ? "automatic" : "manual"} compaction history expands independently of replies',
      (tester) async {
        await tester.runAsync(() => scope.provider.initialized);
        final start = DateTime(2026, 11, 20, 10);
        final step = AiProcessingStep(
          name: 'compact_context',
          succeeded: true,
          arguments: {
            'trigger': automatic ? 'auto' : 'manual',
            'outcome': 'compacted',
            'beforeTokens': 1200,
            'afterTokens': 300,
          },
        );
        const duration = Duration(milliseconds: 3200);
        final record = AiMessage(
          id: 'manual-history',
          role: 'compaction',
          model: 'deepseek-flash',
          reasoningEffort: AiReasoningEffort.none,
          content: '',
          toolName: 'compact_context',
          toolArguments: automatic
              ? {'trigger': 'auto', 'replyId': 'reply-1'}
              : null,
          createdAt: start,
          finishedAt: start.add(duration),
          elapsed: duration,
          status: AiResponseStatus.completed,
          processingSteps: [step],
          processEvents: [
            const AiProcessEvent(
              type: AiProcessEventType.status,
              status: AiResponseStatus.connecting,
              elapsed: Duration.zero,
            ),
            const AiProcessEvent(
              type: AiProcessEventType.status,
              status: AiResponseStatus.thinking,
              operationId: 'manual-history',
              elapsed: Duration(milliseconds: 400),
            ),
            const AiProcessEvent(
              type: AiProcessEventType.status,
              status: AiResponseStatus.streaming,
              operationId: 'manual-history',
              elapsed: Duration(seconds: 2),
            ),
            AiProcessEvent(
              type: AiProcessEventType.action,
              operationId: 'manual-history',
              elapsed: duration,
              action: step,
            ),
            const AiProcessEvent(
              type: AiProcessEventType.status,
              status: AiResponseStatus.completed,
              elapsed: duration,
            ),
          ],
        );
        final emptyReply = AiMessage(
          id: 'empty-reply',
          role: 'assistant',
          content: '',
          elapsed: Duration.zero,
          finishedAt: start,
          status: AiResponseStatus.stopped,
        );
        scope.provider.restoreWorkspaceConversation({
          'messages': [
            ConversationCodec.message(emptyReply),
            ConversationCodec.message(record),
          ],
          'history': <Map<String, Object?>>[],
        });
        await tester.pumpWidget(app(locale: 'zh'));
        await tester.pumpAndSettle();
        final title = find.text(
          '${automatic ? "自动" : "手动"}压缩上下文 · 已完成 · 用时 00:03:200',
        );
        final detail = find.text('估算 token 数：1200 → 300');
        expect(find.text('2026.11.20 10:00:03'), findsOneWidget);
        expect(detail, findsNothing);
        double headerToCopy(String id) {
          final button = find.byKey(ValueKey('ai-copy-message-$id'));
          expect(tester.widget<TitleBarIconButton>(button).onPressed, isNull);
          final header = find.byKey(ValueKey('ai-response-details-$id'));
          return tester.getTopLeft(button).dy - tester.getBottomLeft(header).dy;
        }

        expect(
          headerToCopy(record.id),
          closeTo(headerToCopy(emptyReply.id), 1),
        );
        await tester.tap(title);
        await tester.pumpAndSettle();
        expect(detail, findsNothing);
        expect(find.text('正在连接'), findsOneWidget);
        expect(find.byIcon(Symbols.cloud_sync_rounded), findsOneWidget);
        expect(find.text('00:00:000'), findsOneWidget);
        final operation = find.byKey(
          const ValueKey('operation-manual-history'),
        );
        await tester.tap(
          find.descendant(of: operation, matching: find.byType(InkWell)).first,
        );
        await tester.pumpAndSettle();
        expect(detail, findsOneWidget);
        expect(find.textContaining('开始时间'), findsNothing);
        final model = find.textContaining('deepseek-flash');
        expect(find.text('思考强度：关闭'), findsOneWidget);
        final left = tester
            .getTopLeft(
              find.byKey(const ValueKey('ai-response-details-manual-history')),
            )
            .dx;
        expect(tester.getTopLeft(model.first).dx, closeTo(left, 1));
        final stageIcon = find.byIcon(Symbols.edit_note_rounded);
        final stage = find.text('正在输出');
        final stageTime = find.text('00:02:000');
        final firstTime = find.text('00:00:000');
        expect(tester.getTopLeft(stageIcon).dx, greaterThan(left));
        expect(
          tester.getTopLeft(stage).dx,
          greaterThan(tester.getTopLeft(stageIcon).dx),
        );
        expect(
          tester.getTopLeft(stageTime).dy,
          closeTo(tester.getTopLeft(stage).dy, 1),
        );
        expect(
          tester.getTopRight(stageTime).dx,
          closeTo(tester.getTopRight(firstTime).dx, 1),
        );
        expect(
          tester.getTopLeft(detail).dx,
          closeTo(tester.getTopLeft(stageIcon).dx, 1),
        );
        if (automatic) await capture(tester, 'compaction-shared-timing');
        await tester.tap(title);
        await tester.pumpAndSettle();
        expect(detail, findsNothing);
      },
    );
  }

  for (final (outcome, title, status) in [
    ('failed', '上下文压缩失败', AiResponseStatus.failed),
    ('unchanged', '上下文未改变', AiResponseStatus.completed),
  ]) {
    testWidgets('automatic compaction timing shows $outcome, not completion', (
      tester,
    ) async {
      await tester.runAsync(() => scope.provider.initialized);
      const id = 'compaction-result';
      const duration = Duration(milliseconds: 3200);
      final failed = outcome == 'failed';
      final start = DateTime(2026, 11, 20, 10);
      final step = AiProcessingStep(
        name: 'compact_context',
        succeeded: false,
        arguments: {
          'trigger': 'auto',
          'outcome': outcome,
          if (failed) ...{
            'compactionIssue': 'outputLimit',
            'finishReason': 'length',
            'outputTokens': 2048,
            'outputLimit': 2048,
          } else
            'noTokenSavings': true,
        },
      );
      final record = AiMessage(
        id: id,
        role: 'compaction',
        model: 'deepseek-flash',
        content: '',
        toolName: 'compact_context',
        toolArguments: const {'trigger': 'auto'},
        createdAt: start,
        finishedAt: start.add(duration),
        elapsed: duration,
        status: status,
        processingSteps: [step],
        processEvents: [
          const AiProcessEvent(
            type: AiProcessEventType.status,
            status: AiResponseStatus.thinking,
            operationId: id,
            elapsed: Duration(milliseconds: 400),
          ),
          AiProcessEvent(
            type: AiProcessEventType.action,
            operationId: id,
            elapsed: duration,
            action: step,
          ),
          AiProcessEvent(
            type: AiProcessEventType.status,
            status: status,
            elapsed: duration,
          ),
        ],
      );
      scope.provider.restoreWorkspaceConversation({
        'messages': [ConversationCodec.message(record)],
        'history': <Map<String, Object?>>[],
      });
      await tester.pumpWidget(app(locale: 'zh'));
      await tester.pumpAndSettle();
      final bodyError = find.textContaining('上下文压缩失败  模型达到输出 token 上限');
      expect(bodyError, failed ? findsOneWidget : findsNothing);
      if (failed) {
        final color = Theme.of(tester.element(bodyError)).colorScheme.error;
        expect(tester.widget<Text>(bodyError).style?.color, color);
      }
      final copy = find.byKey(const ValueKey('ai-copy-message-$id'));
      expect(
        tester.widget<TitleBarIconButton>(copy).onPressed,
        failed ? isNotNull : isNull,
      );
      if (failed) {
        final messenger = tester.binding.defaultBinaryMessenger;
        String? copied;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await tester.tap(copy);
        await tester.pump();
        expect(copied, tester.widget<Text>(bodyError).data);
      }
      await tester.tap(find.text('自动压缩上下文 · $title · 用时 00:03:200'));
      await tester.pumpAndSettle();
      expect(find.text('已完成'), findsNothing);
      expect(find.text('处理失败'), failed ? findsOneWidget : findsNothing);
      final operation = find.byKey(const ValueKey('operation-$id'));
      await tester.tap(
        find.descendant(of: operation, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('正在思考…'), findsOneWidget);
      if (failed) {
        expect(find.text('错误详情'), findsOneWidget);
        final block = tester.widget<ChatCodeBlock>(find.byType(ChatCodeBlock));
        expect(block.text, contains('模型达到输出 token 上限'));
        expect(block.text, contains('模型结束原因：length'));
        expect(block.text, contains('2048 token'));
      } else {
        expect(find.text('摘要未减少估算 token 数，已保留原上下文。'), findsOneWidget);
        expect(find.text('错误详情'), findsNothing);
      }
    });
  }

  testWidgets('composer metrics sit close to the bottom of the chat page', (
    tester,
  ) async {
    await tester.runAsync(() => scope.provider.initialized);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(450, 650), const Size(1920, 1080)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(app(scale: size.width == 450 ? 1.5 : 1));
      await tester.pumpAndSettle();
      final metric = find.byKey(const ValueKey('ai-context-usage-metric'));
      final pageBottom = tester.getBottomLeft(find.byType(AssistantPage)).dy;
      expect(pageBottom - tester.getBottomLeft(metric).dy, closeTo(6, 1));
    }
  });

  testWidgets(
    'history thumb drag cancels latest following and retains the chosen location',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      scope.provider.restoreWorkspaceConversation({
        'messages': List.generate(
          1000,
          (index) => ConversationCodec.message(
            AiMessage(
              id: 'thumb-history-$index',
              role: 'user',
              content: 'HISTORY-$index ${'Example text. ' * 12}',
            ),
          ),
        ),
        'history': <Map<String, Object?>>[],
      });
      await tester.pumpWidget(
        app(
          disableAnimations: true,
          content: const ScrollbarTheme(
            data: ScrollbarThemeData(
              thumbVisibility: WidgetStatePropertyAll(true),
              crossAxisMargin: 6,
            ),
            child: AssistantPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewportFinder = find.byKey(const ValueKey('ai-message-scroll'));
      final viewport = tester.getRect(viewportFinder);
      final bar = find
          .descendant(of: viewportFinder, matching: find.byType(Scrollbar))
          .first;
      final logical = tester.widget<Scrollbar>(bar).controller!;
      final gesture = await tester.startGesture(
        Offset(viewport.right - 10, viewport.bottom - 18),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(Offset(0, -viewport.height * .5));
      await tester.pumpAndSettle();
      final fraction = logical.offset / logical.position.maxScrollExtent;
      expect(fraction, inExclusiveRange(.1, .9));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        logical.offset / logical.position.maxScrollExtent,
        closeTo(fraction, .01),
      );
      final latest = find.byKey(const ValueKey('ai-scroll-to-latest'));
      expect(latest, findsOneWidget);
      await tester.tap(latest);
      await tester.pumpAndSettle();
      expect(logical.offset / logical.position.maxScrollExtent, 1);
      expect(
        find.textContaining('HISTORY-999', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long Markdown retains semantics for mounted text and links', (
    tester,
  ) async {
    await tester.runAsync(() => scope.provider.initialized);
    scope.provider.restoreWorkspaceConversation({
      'messages': [
        ConversationCodec.message(
          AiMessage(
            id: 'long-markdown',
            role: 'assistant',
            content:
                '${List.filled(48, 'Earlier paragraph ${'word ' * 35}').join('\n\n')}'
                '\n\nReadable checkpoint.\n\n[Reference link](https://example.test)',
          ),
        ),
      ],
      'history': [],
    });
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Readable checkpoint.'), findsOneWidget);
      expect(
        find.semantics.byPredicate((node) {
          final data = node.getSemanticsData();
          return data.label == 'Reference link' &&
              data.hasAction(ui.SemanticsAction.tap);
        }),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('character-streamed Markdown keeps the live viewport anchored', (
    tester,
  ) async {
    scope.dispose();
    final output = StreamController<List<int>>();
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: splitView,
      client: MockClient.streaming((_, body) async {
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
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app());
    unawaited(scope.provider.sendMessage('Stream Markdown'));

    void delta(String text) => output.add(
      utf8.encode(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': text},
            },
          ],
        })}\n\n',
      ),
    );

    final seed = List.generate(
      85,
      (index) =>
          '## Section $index\n\n${'A long paragraph with formatted **text**. ' * 3}\n\n',
    ).join();
    delta(seed);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final viewport = find.byKey(const ValueKey('ai-message-scroll'));
    final position = tester
        .widget<SingleChildScrollView>(viewport)
        .controller!
        .position;
    final initialExtent = position.maxScrollExtent;
    expect(initialExtent, greaterThan(0));

    const suffix =
        '### Growing heading\n\n'
        '- First item\n- Second item with **formatting**\n\n'
        '| Value | Note |\n| --- | --- |\n| 42 | Table body |\n\n'
        '```text\nA line of code\nAnother line\n```\n\n'
        'Final **paragraph** with a [link](https://example.test).\n\n';
    for (final (index, character) in suffix.split('').indexed) {
      delta(character);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        position.extentAfter,
        closeTo(0, 1),
        reason: 'Streaming frame $index',
      );
    }
    expect(position.maxScrollExtent, isNot(initialExtent));
    expect(scope.provider.messages.last.content, contains('Growing heading'));

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(viewport),
        scrollDelta: const Offset(0, -600),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(position.extentAfter, greaterThan(120));
    delta('### More text while reading history\n\n${'Words. ' * 150}');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(position.extentAfter, greaterThan(120));
    output.add(utf8.encode('data: [DONE]\n\n'));
    unawaited(output.close());
    await pumpAssistantUntilIdle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one latest click reaches the end of mixed image messages', (
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
    final image = AiImageAttachment(
      name: 'image.png',
      mimeType: 'image/png',
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
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
    tester.widget<ChatComposer>(find.byType(ChatComposer)).onAttachmentsChanged(
      [image],
    );
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
  }, variant: latestMotionVariant);

  testWidgets('long Markdown uses a partial body window and remains selectable', (
    tester,
  ) async {
    await tester.runAsync(() => scope.provider.initialized);
    final content = List.generate(
      35,
      (i) =>
          '### Section $i\n\n- First long list item with enough text to wrap across the conversation width.\n- Second item\n\n| Name | Value |\n| --- | --- |\n| Row $i | Table content |\n',
    ).join('\n');
    scope.provider.restoreWorkspaceConversation({
      'messages': [
        ConversationCodec.message(
          AiMessage(id: 'paint-test', role: 'assistant', content: content),
        ),
      ],
      'history': <Map<String, Object?>>[],
    });
    await tester.pumpWidget(app(disableAnimations: true));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('ai-message-scroll')),
        )
        .controller!;
    final boundaryFinder = find.byKey(
      const ValueKey('ai-message-paint-paint-test'),
    );
    final bodyWindow = tester.state<ChatContentWindowState>(
      find.descendant(
        of: boundaryFinder,
        matching: find.byType(ChatContentWindow),
      ),
    );
    final initialFirst = bodyWindow.firstChildIndex;
    final extent = scroll.position.maxScrollExtent;
    expect(bodyWindow.widget.childCount, greaterThan(8));
    expect(bodyWindow.loadedChildCount, lessThan(bodyWindow.widget.childCount));
    expect(extent, greaterThan(0));
    final initialLoaded = bodyWindow.loadedChildCount;
    scroll.jumpTo(math.min(160, extent));
    await tester.pumpAndSettle();
    expect(bodyWindow.firstChildIndex, lessThan(initialFirst));
    expect(bodyWindow.loadedChildCount, greaterThan(initialLoaded));
    expect(bodyWindow.loadedChildCount, lessThan(bodyWindow.widget.childCount));
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.toolbar);
    await tester.pump();
    final paragraphs = find.descendant(
      of: boundaryFinder,
      matching: find.byType(RichText),
    );
    expect(
      paragraphs.evaluate().any(
        (e) => (e.renderObject! as RenderParagraph).selections.any(
          (s) => !s.isCollapsed,
        ),
      ),
      isTrue,
    );
    region.clearSelection();
    region.hideToolbar();
    await tester.pump();
    theme.setTheme(ThemeType.dark);
    await tester.pumpAndSettle();
    final paragraph = find
        .descendant(of: boundaryFinder, matching: find.byType(RichText))
        .evaluate()
        .map((element) => element.renderObject! as RenderParagraph)
        .firstWhere(
          (paragraph) => paragraph.text.toPlainText().contains('Section 34'),
        );
    bool hasColor(InlineSpan span, Color color) =>
        span.style?.color == color ||
        (span is TextSpan &&
            (span.children?.any((child) => hasColor(child, color)) ?? false));
    expect(hasColor(paragraph.text, theme.themeData.textColorPrimary), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'message repaint boundary updates when a running reply receives content',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      await tester.pumpWidget(app(disableAnimations: true));
      await tester.pumpAndSettle();
      responseGate = Completer<void>();
      unawaited(scope.provider.sendMessage('Paint boundary update'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final reply = scope.provider.messages.last;
      final finder = find.byKey(ValueKey('ai-message-paint-${reply.id}'));
      final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
      boundary.debugResetMetrics();
      responseGate!.complete();
      await pumpAssistantUntilIdle(tester);
      await tester.pumpAndSettle();
      expect(
        tester.renderObject<RenderRepaintBoundary>(finder),
        same(boundary),
      );
      expect(
        find.descendant(
          of: finder,
          matching: find.text(
            'Ready to help with LilygoBox.',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      expect(
        boundary.debugSymmetricPaintCount + boundary.debugAsymmetricPaintCount,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('many draft images wrap and scroll without covering the editor', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
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
    expect(find.text('Connecting · Worked for 00:00:000'), findsOneWidget);
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
    expect(find.textContaining('Model request retry 1'), findsOneWidget);
    await pumpAssistantUntilIdle(tester);
    await tester.pumpAndSettle();
    final reply = scope.provider.messages.last;
    expect(reply.status, AiResponseStatus.completed);
    expect(reply.retries.single.attempt, 1);
    expect(reply.requestError, isNull);
    expect(requests, 2);
    await tester.tap(find.byKey(ValueKey('ai-response-details-${reply.id}')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Model request retry 1: HTTP 503'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['en', 'zh']) {
    testWidgets('web failure reason appears in elapsed details: ' + locale, (
      tester,
    ) async {
      failWebTool = true;
      await tester.runAsync(() => scope.provider.initialized);
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test',
        models: ['test'],
        apiKey: 'key',
      );
      await tester.pumpWidget(app(locale: locale));
      unawaited(scope.provider.sendMessage('Read webpage'));
      await pumpAssistantUntilIdle(tester);
      await tester.pumpAndSettle();
      final reply = scope.provider.messages.last;
      await tester.tap(find.byKey(ValueKey('ai-response-details-${reply.id}')));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AssistantPage));
      final l10n = AppLocalizations.of(context);
      expect(find.text(l10n.aiWebUnsupportedScheme), findsNothing);
      await tester.tap(find.textContaining(l10n.aiWebFailed('example.com')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.aiWebUnsupportedScheme), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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

  testWidgets('time tool uses a clock for execution and result', (
    tester,
  ) async {
    await tester.runAsync(() => scope.provider.initialized);
    await scope.provider.saveService(
      name: 'Test',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test',
      models: ['test'],
      apiKey: 'key',
    );
    showProcess = true;
    showTimeTool = true;
    await tester.pumpWidget(app());
    unawaited(scope.provider.sendMessage('Check the time'));
    await pumpAssistantUntilIdle(tester);
    await tester.pumpAndSettle();
    final reply = scope.provider.messages.last;
    final header = find.byKey(ValueKey('ai-response-details-${reply.id}'));
    await tester.ensureVisible(header);
    final trigger = tester.getRect(header);
    final messageRect = tester.getRect(
      find.ancestor(of: header, matching: find.byType(Column)).first,
    );
    expect(trigger.right, lessThan(messageRect.right));
    // 点击用时右侧空白不应打开详情。
    await tester.tapAt(Offset(messageRect.right - 4, trigger.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('Read current time'), findsNothing);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.textContaining('Read current time'), findsOneWidget);
    expect(find.byIcon(Symbols.schedule_rounded), findsOneWidget);
    expect(find.text('Executing tools'), findsNothing);
    expect(find.text('Waiting for the model response'), findsOneWidget);
    expect(find.byIcon(Symbols.handyman_rounded), findsNothing);
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
    expect(find.textContaining('Model reasoning'), findsNothing);
    expect(
      find.text('Updating the theme.', findRichText: true),
      findsOneWidget,
    );
    final header = find.byKey(ValueKey('ai-response-details-${reply.id}'));
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.textContaining('Model reasoning'), findsOneWidget);
    expect(find.text('Inspect the current theme.'), findsNothing);
    expect(
      find.textContaining('Executed: Change theme to Dark'),
      findsOneWidget,
    );
    expect(find.text('Waiting for the model response'), findsOneWidget);
    final thought = List.filled(30, 'Confirm the setting result. ').join();
    expect(find.text(thought), findsNothing);
    await tester.ensureVisible(find.textContaining('Model reasoning'));
    await tester.tap(find.textContaining('Model reasoning'));
    await tester.pumpAndSettle();
    expect(find.text(thought), findsOneWidget);
    final scroll = find
        .ancestor(
          of: find.text(thought),
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
    expect(find.textContaining('Model reasoning'), findsNothing);
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
        models: ['custom-model', 'group/gpt-6.2-sol'],
        apiKey: 'second-key',
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final modelButton = find.byKey(const ValueKey('ai-model-selector'));
      final deepSeekIcon = find.byKey(const ValueKey('ai-model-brand-deepseek'));
      final openAiIcon = find.byKey(const ValueKey('ai-model-brand-openai'));
      final defaultIcon = find.byIcon(Symbols.blur_on);
      expect(
        find.descendant(of: modelButton, matching: deepSeekIcon),
        findsOneWidget,
      );
      final permissionButton = find.byKey(
        const ValueKey('ai-permissions-button'),
      );
      expect(
        tester.getSize(modelButton).height,
        closeTo(tester.getSize(permissionButton).height, .01),
      );
      expect(
        tester.widget<MenuItemSurface>(modelButton).borderRadius,
        tester.widget<MenuItemSurface>(permissionButton).borderRadius,
      );
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
      for (final (service, model, brandIcon, iconSize) in [
        (first, 'deepseek-chat', deepSeekIcon, 16.0),
        (first, 'deepseek-reasoner', deepSeekIcon, 16.0),
        (second, 'custom-model', defaultIcon, 16.0),
        (second, 'group/gpt-6.2-sol', openAiIcon, 14.0),
      ]) {
        final row = find.byKey(ValueKey('ai-model-$service-$model'));
        final icon = find.descendant(of: row, matching: brandIcon);
        expect(icon, findsOneWidget);
        expect(tester.getSize(row).height, 28);
        expect(tester.getSize(icon), Size.square(iconSize));
        expect(
          tester.getCenter(icon).dy,
          closeTo(tester.getCenter(row).dy, .01),
        );
        final label = find.descendant(of: row, matching: find.text(model));
        expect(tester.getRect(icon).right, lessThan(tester.getRect(label).left));
      }
      await capture(tester, 'model-selector-dark');
      final search = find.byKey(const ValueKey('ai-model-search'));
      final selectedRow = find.byKey(ValueKey('ai-model-$first-deepseek-chat'));
      final selectedIcon = find.descendant(
        of: selectedRow,
        matching: deepSeekIcon,
      );
      expect(tester.widget<SvgPicture>(selectedIcon).colorFilter, isNull);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(search));
      await mouse.moveTo(tester.getCenter(selectedRow));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SvgPicture>(selectedIcon).colorFilter,
        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
      await mouse.moveTo(tester.getCenter(search));
      await tester.pumpAndSettle();
      expect(tester.widget<SvgPicture>(selectedIcon).colorFilter, isNull);
      await mouse.removePointer();
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
        find.descendant(of: modelButton, matching: defaultIcon),
        findsOneWidget,
      );
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
      const models = ['deepseek-chat', 'group/gpt-6.2-sol', '自定义模型'];
      final service = await scope.provider.saveService(
        name: 'Gateway',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: models,
        apiKey: 'key',
      );
      for (final locale in ['en', 'zh']) {
        await tester.pumpWidget(app(scale: 1.6, locale: locale));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
        await tester.pumpAndSettle();
        final search = tester.widget<TextField>(
          find.byKey(const ValueKey('ai-model-search')),
        );
        expect(search.focusNode!.hasFocus, isFalse);
        final heights = {
          for (final model in models)
            tester
                .getSize(find.byKey(ValueKey('ai-model-$service-$model')))
                .height,
        };
        expect(heights, hasLength(1));
        expect(heights.single, greaterThan(28));
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
    'deleted model returns the live workspace selector to Choose model',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      final service = await scope.provider.saveService(
        name: 'Models',
        protocol: AiApiProtocol.openAiResponses,
        baseUrl: 'https://example.test/v1',
        models: ['gpt-6.1-sol', 'gpt-6-astra'],
        apiKey: 'key',
      );
      final agent = scope.provider.forkForWorkspace();
      addTearDown(agent.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelSelector(theme: theme.themeData, assistant: agent),
          ),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('gpt-6.1-sol'), findsOneWidget);
      await scope.provider.saveService(
        id: service,
        name: 'Models',
        protocol: AiApiProtocol.openAiResponses,
        baseUrl: 'https://example.test/v1',
        models: ['gpt-6-astra'],
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('gpt-6.1-sol'), findsNothing);
      expect(find.text('Select model'), findsOneWidget);
    },
  );

  testWidgets(
    'processing speed selection is available only for supported models',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      final service = await scope.provider.saveService(
        name: 'Speed service',
        protocol: AiApiProtocol.openAiResponses,
        baseUrl: 'https://example.test/v1',
        models: ['gpt-6.1-sol', 'deepseek-flash'],
        serviceTiers: {
          'gpt-6.1-sol': ['priority'],
        },
        apiKey: 'key',
      );
      await scope.provider.selectModel(service, 'gpt-6.1-sol');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('ai-processing-speed-toggle'));
      expect(toggle, findsOneWidget);
      expect(find.text('Processing speed'), findsNothing);
      expect(scope.provider.processingSpeeds, [
        AiProcessingSpeed.standard,
        AiProcessingSpeed.fast,
      ]);
      final icon = find.descendant(of: toggle, matching: find.byType(Icon));
      expect(
        tester.widget<Icon>(icon).color,
        theme.themeData.textColorTertiary,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        scope.provider.configuration.processingSpeed,
        AiProcessingSpeed.fast,
      );
      expect(tester.widget<Icon>(icon).color, theme.themeData.basePrimary);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(scope.provider.processingSpeed, AiProcessingSpeed.standard);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final child = scope.provider.forkForWorkspace();
      addTearDown(child.dispose);
      expect(child.configuration.processingSpeed, AiProcessingSpeed.fast);
      await child.setProcessingSpeed(AiProcessingSpeed.standard);
      expect(scope.provider.processingSpeed, AiProcessingSpeed.fast);
      await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
      await tester.pumpAndSettle();
      await scope.provider.selectModel(service, 'deepseek-flash');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ai-processing-speed-toggle')),
        findsNothing,
      );
      expect(scope.provider.processingSpeed, AiProcessingSpeed.standard);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reasoning opens first, fades to models and preserves concrete effort choices',
    (tester) async {
      await tester.runAsync(() => scope.provider.initialized);
      const model = 'auto/gpt-6.2-sol';
      final service = await scope.provider.saveService(
        name: 'Reasoning service',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: [model, 'plain'],
        apiKey: 'key',
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final trigger = find.byKey(const ValueKey('ai-model-selector'));
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-model-list-panel')), findsNothing);
      expect(find.byKey(const ValueKey('ai-reasoning-panel')), findsOneWidget);
      final header = find.byKey(const ValueKey('ai-reasoning-models'));
      final icon = find.descendant(
        of: header,
        matching: find.byKey(const ValueKey('ai-model-brand-openai')),
      );
      final label = find.descendant(of: header, matching: find.text(model));
      expect(tester.getRect(icon).right, lessThan(tester.getRect(label).left));
      final slider = find.byType(Slider);
      expect(
        tester
            .widget<AppCapsuleSlider>(
              find.byKey(const ValueKey('ai-reasoning-slider')),
            )
            .divisions,
        5,
      );
      expect(find.text('Default'), findsNothing);
      expect(find.byKey(const ValueKey('ai-reasoning-reset')), findsNothing);
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
      await tester.pumpAndSettle();
      expect(scope.provider.reasoningEffort, AiReasoningEffort.ultra);
      expect(find.text('$model · Ultra'), findsOneWidget);

      final beforeHeight = tester
          .getSize(find.byKey(const ValueKey('ai-model-menu-surface')))
          .height;
      await tester.tap(find.byKey(const ValueKey('ai-reasoning-models')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final intermediateHeight = tester
          .getSize(find.byKey(const ValueKey('ai-model-menu-surface')))
          .height;
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
      final finalHeight = tester
          .getSize(find.byKey(const ValueKey('ai-model-menu-surface')))
          .height;
      expect(intermediateHeight, isNot(closeTo(beforeHeight, .01)));
      expect(intermediateHeight, isNot(closeTo(finalHeight, .01)));
      expect(
        intermediateHeight,
        inInclusiveRange(
          beforeHeight < finalHeight ? beforeHeight : finalHeight,
          beforeHeight > finalHeight ? beforeHeight : finalHeight,
        ),
      );
      await tester.tap(find.byKey(ValueKey('ai-model-$service-plain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-reasoning-panel')), findsNothing);
      expect(scope.provider.reasoningEffort, isNull);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('ai-model-$service-$model')));
      await tester.pumpAndSettle();
      expect(scope.provider.reasoningEffort, AiReasoningEffort.ultra);
      expect(find.byKey(const ValueKey('ai-reasoning-reset')), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-reasoning-panel')), findsOneWidget);
      expect(tester.widget<Slider>(slider).value, 1);
      expect(scope.provider.selectedModel, model);
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
        models: ['deepseek-flash', 'plain'],
        apiKey: 'key',
      );
      await scope.provider.setReasoningEffort(AiReasoningEffort.none);
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
      expect(find.text('Model: deepseek-flash'), findsOneWidget);
      expect(find.text('Reasoning effort: Off'), findsOneWidget);
      expect(find.text('Reasoning effort: Low'), findsNothing);
      final modelRect = tester.getRect(find.text('Model: deepseek-flash'));
      final effortRect = tester.getRect(find.text('Reasoning effort: Off'));
      expect(effortRect.left, modelRect.left);
      expect(effortRect.top, greaterThan(modelRect.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('processing speed popup fits narrow windows and larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => scope.provider.initialized);
    await scope.provider.saveService(
      name: 'Speed',
      protocol: AiApiProtocol.openAiResponses,
      baseUrl: 'https://example.test/v1',
      models: ['gpt-6.1-sol'],
      apiKey: 'key',
    );
    for (final type in ThemeType.values) {
      theme.setTheme(type);
      for (final locale in ['en', 'zh']) {
        await tester.pumpWidget(app(scale: 1.6, locale: locale));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('ai-processing-speed-toggle'));
        final icons = find.descendant(of: toggle, matching: find.byType(Icon));
        expect(icons, findsOneWidget);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(scope.provider.processingSpeed, AiProcessingSpeed.fast);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(scope.provider.processingSpeed, AiProcessingSpeed.ultrafast);
        expect(icons, findsNWidgets(2));
        final heading = tester.getRect(
          find.text(locale == 'en' ? 'Reasoning effort' : '思考强度'),
        );
        expect(tester.getCenter(toggle).dx, greaterThan(heading.right));
        expect(tester.getCenter(toggle).dy, closeTo(heading.center.dy, 1));
        expect(tester.takeException(), isNull);
        await capture(tester, 'speed-${type.name}-$locale');
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(scope.provider.processingSpeed, AiProcessingSpeed.standard);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

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
