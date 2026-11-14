/*
 * @Description: 验证多层任务树创建、拖动、独立会话与临时任务只读行为。
 * @Author: LILYGO_L
 * @Date: 2026-11-13 21:03:39
 * @LastEditTime: 2026-11-13 23:16:03
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/core/widgets/card_shadow.dart';
import 'package:lilygobox/core/widgets/interaction_decoration.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/core/widgets/settings/select.dart';
import 'package:lilygobox/core/widgets/tilt_card.dart';
import 'package:lilygobox/core/widgets/title_bar_icon_button.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';
import 'package:lilygobox/features/assistant/domain/task_canvas_style.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/assistant/presentation/pages/task_topology_page.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_connection.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

void main() {
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late AppNavigationProvider navigation;
  late AssistantTestScope scope;
  late AiWorkspaceProvider workspaces;
  final boundary = GlobalKey();
  final overlayBoundary = GlobalKey();
  final requestGates = <String, Completer<void>>{};
  Map<String, Object?>? nextTool;

  setUp(() async {
    requestGates.clear();
    nextTool = null;
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    navigation = AppNavigationProvider();
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      client: MockClient((request) async {
        for (final entry in requestGates.entries) {
          if (request.body.contains(entry.key)) await entry.value.future;
        }
        final tool = nextTool;
        nextTool = null;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': tool == null ? 'Task completed.' : '',
                  if (tool != null) 'tool_calls': [tool],
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
      name: 'Local model',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['gpt-6.1-sol', 'deepseek-flash'],
      apiKey: 'test-key',
    );
    workspaces = AiWorkspaceProvider(scope.provider);
    if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
      final chinese = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      final chineseBold = await File(
        'C:/Windows/Fonts/msyhbd.ttc',
      ).readAsBytes();
      await (FontLoader(
        'Ahem',
      )..addFont(Future.value(ByteData.sublistView(chineseBold)))).load();

      for (final family in [
        'sans-serif',
        'Arial',
        'Segoe UI',
        'Microsoft YaHei',
        'Microsoft YaHei UI',
      ]) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(chinese)))).load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  'D:/flutter sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                ).readAsBytes(),
              ),
            ),
          ))
          .load();

      await (FontLoader(
        'Ahem',
      )..addFont(Future.value(ByteData.sublistView(chinese)))).load();
      await (FontLoader(
            'packages/material_symbols_icons/MaterialSymbolsOutlined',
          )..addFont(
            rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
            ),
          ))
          .load();
      await (FontLoader(
        'WorkspaceChinese',
      )..addFont(Future.value(ByteData.sublistView(chinese)))).load();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(chinese)))).load();
      await (FontLoader(
            'packages/material_symbols_icons/MaterialSymbolsRounded',
          )..addFont(
            rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
            ),
          ))
          .load();
    }
  });
  tearDown(() {
    workspaces.dispose();
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
    navigation.dispose();
  });
  Widget app({
    bool disableAnimations = false,
    double textScale = 1,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<AppShellProvider>.value(value: shell),
      ChangeNotifierProvider<AppNavigationProvider>.value(value: navigation),
      ChangeNotifierProvider<AiAssistantProvider>.value(value: scope.provider),
      ChangeNotifierProvider<AiWorkspaceProvider>.value(value: workspaces),
    ],
    child: RepaintBoundary(
      key: overlayBoundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        locale: const Locale('zh'),
        theme: ThemeData(
          fontFamily: const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')
              ? 'WorkspaceChinese'
              : null,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RepaintBoundary(key: boundary, child: const TaskTopologyPage()),
        ),
      ),
    ),
  );

  Future<void> captureOverlay(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) return;
    await tester.runAsync(() async {
      final image =
          await (overlayBoundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${Directory.systemTemp.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> tick(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> finish(WidgetTester tester) async {
    workspaces.stopAll();
    for (final gate in requestGates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await tick(tester);
  }

  bool selected(WidgetTester tester, String id) =>
      ((tester
                          .widget<AnimatedContainer>(
                            find.byKey(ValueKey('topology-node-$id')),
                          )
                          .foregroundDecoration
                      as BoxDecoration)
                  .border!
              as Border)
          .top
          .color
          .a >
      0;

  for (final textScale in [1.0, 1.5]) {
    testWidgets(
      'floating tools stay centered and clear of the title at scale $textScale',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final root = (await tester.runAsync(
          () => workspaces.createPrimary(title: 'Project', task: 'Coordinate'),
        ))!;
        for (final size in [const Size(1280, 850), const Size(520, 850)]) {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(app(textScale: textScale));
          await tick(tester);
          final canvasFinder = find.byKey(
            const ValueKey('task-topology-canvas'),
          );
          final canvas = tester.getRect(canvasFinder);
          void checkHeader() {
            final title = tester.getRect(
              find.byKey(const ValueKey('topology-canvas-title')),
            );
            final tools = tester.getRect(
              find.byKey(const ValueKey('topology-action-toolbar')),
            );
            expect(title.left, closeTo(canvas.left + 16, .1));
            expect(title.top, greaterThanOrEqualTo(canvas.top + 16));
            expect(tools.center.dx, closeTo(canvas.center.dx, .1));
            expect(title.overlaps(tools), isFalse);
            expect(tools.left, greaterThanOrEqualTo(canvas.left + 16));
            expect(tools.right, lessThanOrEqualTo(canvas.right - 16));
          }

          checkHeader();
          if (!selected(tester, root.id)) {
            await tester.tap(find.byKey(ValueKey('topology-node-${root.id}')));
          }
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('topology-new-child')),
            findsOneWidget,
          );
          checkHeader();
          if (size.width == 1280 && textScale == 1) {
            await captureOverlay(tester, 'lilygobox-floating-workflow-header');
          }
          final controller = tester
              .widget<InteractiveViewer>(canvasFinder)
              .transformationController!;
          final before = controller.value.clone();
          await tester.tap(find.byKey(const ValueKey('topology-new-primary')));
          await tick(tester);
          expect(
            find.byKey(const ValueKey('topology-create-confirm')),
            findsOneWidget,
          );
          expect(controller.value, before);
          Navigator.of(
            tester.element(
              find.byKey(const ValueKey('topology-create-confirm')),
            ),
          ).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await finish(tester);
      },
    );
  }

  testWidgets('floating actions remain visible and use menu feedback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Project', task: 'Coordinate'),
    ))!;
    await tester.pumpWidget(app());
    await tick(tester);
    final child = find.byKey(const ValueKey('topology-new-child'));
    final delete = find.byKey(const ValueKey('topology-delete'));
    final tools = find.byKey(const ValueKey('topology-action-toolbar'));
    final initialSize = tester.getSize(tools);
    expect(tester.widget<MenuItemSurface>(child).onPressed, isNull);
    expect(tester.widget<MenuItemSurface>(delete).onPressed, isNull);
    await tester.tap(child);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topology-create-confirm')), findsNothing);
    await tester.tap(find.byKey(ValueKey('topology-node-${root.id}')));
    await tester.pumpAndSettle();
    expect(tester.widget<MenuItemSurface>(child).onPressed, isNotNull);
    expect(tester.widget<MenuItemSurface>(delete).onPressed, isNotNull);
    expect(tester.getSize(tools), initialSize);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    for (final type in [ThemeType.light, ThemeType.dark]) {
      theme.setTheme(type);
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(child));
      await tester.pumpAndSettle();
      final backgrounds = tester.widgetList<InteractionDecoration>(
        find.descendant(
          of: child,
          matching: find.byType(InteractionDecoration),
        ),
      );
      expect(
        backgrounds.any(
          (item) => item.decoration.color == theme.themeData.basePrimary,
        ),
        isTrue,
      );
      final text = tester.element(
        find.descendant(of: child, matching: find.byType(Text)),
      );
      expect(
        DefaultTextStyle.of(text).style.color,
        theme.themeData.materialColors.onPrimary,
      );
      await mouse.moveTo(const Offset(10, 150));
      await tester.pumpAndSettle();
    }
    await mouse.removePointer();
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();
    expect(tester.widget<MenuItemSurface>(child).onPressed, isNull);
    expect(tester.widget<MenuItemSurface>(delete).onPressed, isNull);
    expect(tester.getSize(tools), initialSize);
    await finish(tester);
  });

  testWidgets(
    'connection preview moves without rebuilding cards or the background',
    (tester) async {
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: '主智能体', task: 'Coordinate'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final port = find.byKey(ValueKey('topology-port-out-${root.id}'));
      final start = tester.getCenter(port);
      final drag = await tester.startGesture(start);
      await drag.moveTo(start + const Offset(60, 40));
      await tester.pump();
      await drag.moveTo(start + const Offset(100, 60));
      await tester.pumpAndSettle();
      final node = find.byKey(ValueKey('topology-node-${root.id}'));
      final cardBefore = tester.widget<AnimatedContainer>(node);
      final preview = find.byKey(const ValueKey('topology-connection-preview'));
      final previewBefore = tester.widget<CustomPaint>(preview);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final background = find
          .descendant(of: canvas, matching: find.byType(CustomPaint))
          .first;
      final backgroundBefore = tester.widget<CustomPaint>(background);
      final firstEnd = (previewBefore.painter as dynamic).pointer.value;
      expect(firstEnd, isNotNull);
      for (var step = 1; step <= 12; step++) {
        await drag.moveTo(start + Offset(100 + step * 7, 60 + step * 5));
        await tester.pump();
        expect(tester.widget<AnimatedContainer>(node), same(cardBefore));
        expect(tester.widget<CustomPaint>(background), same(backgroundBefore));
        expect(tester.widget<CustomPaint>(preview), same(previewBefore));
      }
      expect((previewBefore.painter as dynamic).pointer.value, isNot(firstEnd));
      await drag.up();
      await tester.pumpAndSettle();
      expect(workspaces.connections, isEmpty);
      expect(
        (tester.widget<CustomPaint>(preview).painter as dynamic).pointer.value,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'marquee remains painted outside the original scene after pan and zoom',
    (tester) async {
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final view = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final origin = tester.getTopLeft(canvas);
      final boundaryOrigin = tester.getTopLeft(find.byKey(boundary));
      Future<List<int>> pixel(Offset global) async {
        return (await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final point = global - boundaryOrigin;
          final index = (point.dy.floor() * image.width + point.dx.floor()) * 4;
          final result = bytes.buffer
              .asUint8List(bytes.offsetInBytes + index, 4)
              .toList();
          image.dispose();
          return result;
        }))!;
      }

      for (final scale in [.5, 1.3]) {
        view.value =
            Matrix4.translationValues(300, 200, 0) *
            Matrix4.diagonal3Values(scale, scale, 1);
        await tester.pumpAndSettle();
        // Both points are inside the viewport but outside the scene's top/left.
        final samples = [
          origin + const Offset(160, 260),
          origin + const Offset(360, 170),
        ];
        final before = <List<int>>[];
        for (final point in samples) {
          before.add(await pixel(point));
        }
        final start = origin + const Offset(80, 120);
        final end = origin + const Offset(440, 380);
        final drag = await tester.startGesture(start);
        await drag.moveTo(end);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(
            find.byKey(const ValueKey('topology-selection-overlay')),
          ),
          rectMoreOrLessEquals(Rect.fromPoints(start, end), epsilon: .001),
        );
        for (var i = 0; i < samples.length; i++) {
          expect(
            await pixel(samples[i]),
            isNot(before[i]),
            reason:
                'The selection fill must paint beyond the original scene boundary',
          );
        }
        await drag.up();
        await tester.pumpAndSettle();
      }
      await finish(tester);
    },
  );

  testWidgets(
    'marquee pointer updates repaint only the overlay until release',
    (tester) async {
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: '主智能体', task: 'Coordinate'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final node = find.byKey(ValueKey('topology-node-${root.id}'));
      final bounds = tester.getRect(node);
      final drag = await tester.startGesture(
        bounds.topLeft - const Offset(25, 25),
      );
      await tester.pump();
      final cardBefore = tester.widget<AnimatedContainer>(node);
      for (var step = 1; step <= 12; step++) {
        await drag.moveTo(bounds.topLeft + Offset(step * 8, step * 6));
        await tester.pump();
        expect(tester.widget<AnimatedContainer>(node), same(cardBefore));
        expect(selected(tester, root.id), isFalse);
      }
      expect(
        find.byKey(const ValueKey('topology-selection-overlay')),
        findsOneWidget,
      );
      await drag.up();
      await tester.pumpAndSettle();
      expect(selected(tester, root.id), isTrue);
      expect(
        find.byKey(const ValueKey('topology-selection-overlay')),
        findsNothing,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'source links and model navigation retain drafts and return history',
    (tester) async {
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: '来源任务', task: 'Coordinate'),
      ))!;
      final child = (await tester.runAsync(
        () =>
            workspaces.create(title: '目标任务', task: 'Review', parentId: root.id),
      ))!;
      await tick(tester);
      await tester.runAsync(
        () => child.assistant.receiveAgentMessage(
          sourceId: root.id,
          sourceTitle: root.title,
          content: 'Review this task',
        ),
      );
      await tick(tester);
      await tester.pumpWidget(app());
      await tick(tester);
      await tester.tap(find.byKey(ValueKey('topology-open-${child.id}')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ai-message-input'));
      await tester.enterText(input, '子智能体未发送草稿');
      await tester.tap(find.text('来自智能体：来源任务'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('topology-chat-${root.id}')), findsOneWidget);
      await tester.enterText(input, '主智能体未发送草稿');
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '子智能体未发送草稿');
      final result = await tester.runAsync(
        () => child.assistant.workspaceToolHandler!('open_agent', {
          'agent_id': root.id,
        }),
      );
      expect(result!['navigation_requested'], isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('topology-chat-${root.id}')), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, '主智能体未发送草稿');
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '子智能体未发送草稿');
      workspaces.remove(root.id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('来自智能体：来源任务'));
      await tester.pumpAndSettle();
      expect(find.text('该智能体已删除或当前无法打开。'), findsOneWidget);
      expect(find.byKey(ValueKey('topology-chat-${child.id}')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'box commits on release and Ctrl adds consecutive boxes and toggles clicks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'First', task: 'one'),
      ))!;
      final second = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Second', task: 'two'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      Future<void> box(
        String id, {
        required bool beforeFirst,
        required bool beforeSecond,
      }) async {
        final rect = tester.getRect(find.byKey(ValueKey('topology-node-$id')));
        final gesture = await tester.startGesture(
          rect.topLeft - const Offset(15, 15),
        );
        await gesture.moveTo(rect.bottomRight + const Offset(15, 15));
        await tester.pump();
        expect(selected(tester, first.id), beforeFirst);
        expect(selected(tester, second.id), beforeSecond);
        expect(
          find
              .ancestor(
                of: find.byKey(ValueKey('topology-node-$id')),
                matching: find.byType(IgnorePointer),
              )
              .evaluate()
              .any((element) => (element.widget as IgnorePointer).ignoring),
          isTrue,
        );
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await box(first.id, beforeFirst: false, beforeSecond: false);
      expect(selected(tester, first.id), isTrue);
      expect(selected(tester, second.id), isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await box(second.id, beforeFirst: true, beforeSecond: false);
      expect(selected(tester, first.id), isTrue);
      expect(selected(tester, second.id), isTrue);
      await tester.tap(find.byKey(ValueKey('topology-node-${first.id}')));
      await tester.pump();
      expect(selected(tester, first.id), isFalse);
      expect(selected(tester, second.id), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await finish(tester);
    },
  );

  testWidgets(
    'marquee crossing empty creation tile blocks hover and pointer interaction',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tick(tester);
      final tile = find.byKey(const ValueKey('topology-empty-create'));
      final rect = tester.getRect(tile);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: rect.topLeft - const Offset(20, 20));
      await mouse.down(rect.topLeft - const Offset(20, 20));
      await tester.pump();
      await mouse.moveTo(rect.center);
      await tester.pumpAndSettle();
      final overlay = find.byKey(const ValueKey('topology-selection-overlay'));
      final decoration =
          tester.widget<DecoratedBox>(overlay).decoration as BoxDecoration;
      expect(decoration.color!.a, closeTo(.08, .005));
      final sceneStack = tester.widget<Stack>(
        find.ancestor(of: overlay, matching: find.byType(Stack)).first,
      );
      expect(
        (sceneStack.children.last as Positioned).child,
        isA<IgnorePointer>(),
      );
      final ignored = find
          .ancestor(of: tile, matching: find.byType(IgnorePointer))
          .evaluate()
          .any((element) => (element.widget as IgnorePointer).ignoring);
      expect(ignored, isTrue);
      final tileRender = tester.renderObject(tile);
      expect(
        tester
            .hitTestOnBinding(rect.center)
            .path
            .any((entry) => identical(entry.target, tileRender)),
        isFalse,
      );
      expect(find.byKey(const ValueKey('topology-title-input')), findsNothing);
      expect(workspaces.selectedId, isNull);
      await mouse.moveTo(rect.bottomRight + const Offset(20, 20));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topology-title-input')), findsNothing);
      expect(workspaces.sessions, isEmpty);
      expect(workspaces.selectedId, isNull);
      expect(
        find
            .ancestor(of: tile, matching: find.byType(IgnorePointer))
            .evaluate()
            .any((element) => (element.widget as IgnorePointer).ignoring),
        isFalse,
      );
      await mouse.removePointer();
      await finish(tester);
    },
  );

  testWidgets(
    'bring to front changes card stacking without changing task relationships',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'First', task: 'one'),
      ))!;
      final second = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Second', task: 'two'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      List<Key?> order() {
        final node = find.byKey(ValueKey('topology-position-${first.id}'));
        final stack = tester.widget<Stack>(
          find.ancestor(of: node, matching: find.byType(Stack)).first,
        );
        return stack.children
            .whereType<Positioned>()
            .where((w) => w.key != null)
            .map((w) => w.key)
            .toList();
      }

      expect(order().last, ValueKey('topology-position-${second.id}'));
      await tester.tap(
        find.byKey(ValueKey('topology-node-${first.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topology-context-bring-front')),
      );
      await tester.pumpAndSettle();
      expect(order().last, ValueKey('topology-position-${first.id}'));
      expect(first.parentId, isNull);
      expect(second.parentId, isNull);
      await finish(tester);
    },
  );

  testWidgets('canvas multiselect moves a group and blank clears selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final first = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'First', task: 'one'),
    ))!;
    final second = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Second', task: 'two'),
    ))!;
    await tester.pumpWidget(app());
    await tick(tester);
    final a = find.byKey(ValueKey('topology-node-${first.id}'));
    final b = find.byKey(ValueKey('topology-node-${second.id}'));
    expect(selected(tester, first.id), isFalse);
    await tester.tap(a);
    await tester.pump();
    expect(selected(tester, first.id), isTrue);
    expect(find.byKey(const ValueKey('ai-message-input')), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(b);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(selected(tester, first.id), isTrue);
    expect(selected(tester, second.id), isTrue);
    final beforeA = tester.getCenter(a);
    final beforeB = tester.getCenter(b);
    await tester.drag(a, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect((tester.getCenter(a) - beforeA).dx, closeTo(60, 2));
    expect((tester.getCenter(b) - beforeB).dx, closeTo(60, 2));
    await captureOverlay(tester, 'lilygobox-task-multiselection');
    await tester.tap(a, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(selected(tester, first.id), isTrue);
    expect(selected(tester, second.id), isTrue);

    final canvas = tester.getRect(
      find.byKey(const ValueKey('task-topology-canvas')),
    );
    await tester.tapAt(canvas.topLeft + const Offset(12, 12));
    await tester.pump();
    expect(selected(tester, first.id), isFalse);
    expect(selected(tester, second.id), isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(selected(tester, first.id), isTrue);
    expect(selected(tester, second.id), isTrue);
    await tester.tap(a, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topology-context-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-topology-delete')));
    await tester.pumpAndSettle();
    expect(workspaces.find(first.id), isNull);
    expect(workspaces.find(second.id), isNull);
    await finish(tester);
  });

  testWidgets(
    'first Shift drag from another focus selects nodes without panning',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Box target', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final node = tester.getRect(
        find.byKey(ValueKey('topology-node-${first.id}')),
      );
      final viewer = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey('task-topology-canvas')),
      );
      final matrix = viewer.transformationController!.value.clone();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final gesture = await tester.startGesture(
        node.topLeft - const Offset(20, 20),
      );
      await tester.pump();
      await gesture.moveTo(node.bottomRight + const Offset(20, 20));
      await tester.pump();
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(selected(tester, first.id), isTrue);
      expect(viewer.transformationController!.value, matrix);
      await finish(tester);
    },
  );

  testWidgets(
    'ports connect siblings without replacing root links or changing roles',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Root', task: 'one'),
      ))!;
      final first = (await tester.runAsync(
        () => workspaces.create(title: 'First', task: 'two', parentId: root.id),
      ))!;
      final second = (await tester.runAsync(
        () => workspaces.create(
          title: 'Second',
          task: 'three',
          parentId: root.id,
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      Offset position(String id) {
        final item = tester.widget<Positioned>(
          find.byKey(ValueKey('topology-position-$id')),
        );
        return Offset(item.left!, item.top!);
      }

      final before = {
        for (final task in [root, first, second]) task.id: position(task.id),
      };
      Future<void> connect(String from, String to) async {
        final start = tester.getCenter(
          find.byKey(ValueKey('topology-port-bottom-$from')),
        );
        final end = tester.getCenter(
          find.byKey(ValueKey('topology-port-top-$to')),
        );
        final gesture = await tester.startGesture(start);
        await gesture.moveTo(start + const Offset(0, 20));
        await tester.pump();
        await gesture.moveTo(end);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await connect(first.id, second.id);
      expect(first.parentId, root.id);
      expect(second.parentId, root.id);
      expect(first.kind, AiWorkspaceKind.permanent);
      expect(second.kind, AiWorkspaceKind.permanent);
      expect(workspaces.connections, hasLength(3));
      final peer = workspaces.connections.singleWhere(
        (connection) => !connection.isHierarchy,
      );
      expect({peer.fromId, peer.toId}, {first.id, second.id});
      for (final task in [root, first, second])
        expect(position(task.id), before[task.id]);
      await connect(second.id, first.id);
      expect(workspaces.connections, hasLength(3));
      await connect(root.id, first.id);
      expect(workspaces.connections, hasLength(3));
      expect(root.kind, AiWorkspaceKind.primary);
      Offset edgePoint() {
        Rect bounds(String id) {
          final item = tester.widget<Positioned>(
            find.byKey(ValueKey('topology-position-$id')),
          );
          return Rect.fromLTWH(
            item.left!,
            item.top!,
            item.width!,
            item.height!,
          );
        }

        final route = TaskTopologyConnection.between(
          bounds(first.id),
          bounds(second.id),
        );
        final metric = route.path.computeMetrics().first;
        final point = metric.getTangentForOffset(metric.length / 2)!.position;
        final canvas = find.byKey(const ValueKey('task-topology-canvas'));
        final viewer = tester.widget<InteractiveViewer>(canvas);
        return tester.getTopLeft(canvas) +
            MatrixUtils.transformPoint(
              viewer.transformationController!.value,
              point,
            );
      }

      await tester.tapAt(edgePoint());
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('confirm-topology-disconnect')),
        findsNothing,
      );
      expect(workspaces.connections, hasLength(2));
      expect(second.parentId, root.id);
      await connect(first.id, second.id);
      await tester.tapAt(edgePoint(), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-edge-disconnect')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('confirm-topology-disconnect')),
        findsNothing,
      );

      expect(workspaces.connections, hasLength(2));
      expect(first.parentId, root.id);
      expect(second.parentId, root.id);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  for (final useChildren in [false, true]) {
    testWidgets(
      'cross-tree drag requires confirmation even with child endpoints: $useChildren',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1180, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final rootA = (await tester.runAsync(
          () => workspaces.createPrimary(title: 'Root A', task: 'one'),
        ))!;
        final rootB = (await tester.runAsync(
          () => workspaces.createPrimary(title: 'Root B', task: 'two'),
        ))!;
        final a = useChildren
            ? (await tester.runAsync(
                () => workspaces.create(
                  title: 'Child A',
                  task: 'three',
                  parentId: rootA.id,
                ),
              ))!
            : rootA;
        final b = useChildren
            ? (await tester.runAsync(
                () => workspaces.create(
                  title: 'Child B',
                  task: 'four',
                  parentId: rootB.id,
                ),
              ))!
            : rootB;
        await tester.pumpWidget(app());
        await tick(tester);
        final count = workspaces.connections.length;
        Future<void> connect() async {
          final start = tester.getCenter(
            find.byKey(ValueKey('topology-port-out-${a.id}')),
          );
          final end = tester.getCenter(
            find.byKey(ValueKey('topology-port-in-${b.id}')),
          );
          final gesture = await tester.startGesture(start);
          await gesture.moveTo(start + const Offset(20, 0));
          await tester.pump();
          await gesture.moveTo(end);
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
        }

        await connect();
        expect(
          find.byKey(const ValueKey('confirm-topology-merge')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TaskTopologyPage)),
        );
        expect(
          find.text(
            useChildren
                ? l10n.aiTopologyMergeChildHelp(
                    '${b.title} (${b.id})',
                    '${a.title} (${a.id})',
                  )
                : l10n.aiTopologyMergeRootHelp(
                    '${rootB.title} (${rootB.id})',
                    '${a.title} (${a.id})',
                  ),
          ),
          findsOneWidget,
        );
        expect(rootB.kind, AiWorkspaceKind.primary);
        expect(rootB.parentId, isNull);
        expect(workspaces.connections, hasLength(count));
        await tester.tap(find.byKey(const ValueKey('cancel-topology-merge')));
        await tester.pumpAndSettle();
        expect(rootB.kind, AiWorkspaceKind.primary);
        expect(workspaces.connections, hasLength(count));
        await connect();
        await tester.tap(find.byKey(const ValueKey('confirm-topology-merge')));
        await tester.pumpAndSettle();
        expect(rootA.kind, AiWorkspaceKind.primary);
        expect(
          rootB.kind,
          useChildren ? AiWorkspaceKind.primary : AiWorkspaceKind.permanent,
        );
        expect(rootB.parentId, useChildren ? isNull : a.id);
        if (useChildren) {
          expect(b.parentId, a.id);
          expect(a.parentId, rootA.id);
        }
        expect(workspaces.isConnected(a.id, b.id), isTrue);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tick(tester);
        expect(rootB.kind, AiWorkspaceKind.primary);
        expect(rootB.parentId, isNull);
        expect(b.parentId, useChildren ? rootB.id : null);
        expect(workspaces.connections, hasLength(count));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tick(tester);
        expect(workspaces.isConnected(a.id, b.id), isTrue);
        expect(b.parentId, a.id);
        await finish(tester);
      },
    );
  }

  testWidgets('two selected cards offer connect and hide it once linked', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Root', task: 'one'),
    ))!;
    final a = (await tester.runAsync(
      () => workspaces.create(title: 'A', task: 'two', parentId: root.id),
    ))!;
    final b = (await tester.runAsync(
      () => workspaces.create(title: 'B', task: 'three', parentId: root.id),
    ))!;
    await tester.pumpWidget(app());
    await tick(tester);
    final nodeA = find.byKey(ValueKey('topology-node-${a.id}'));
    final nodeB = find.byKey(ValueKey('topology-node-${b.id}'));
    await tester.tap(nodeA);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(nodeB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tap(nodeA, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('topology-context-connect')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('topology-context-connect')));
    await tester.pumpAndSettle();
    expect(workspaces.isConnected(a.id, b.id), isTrue);
    expect(a.parentId, root.id);
    expect(b.parentId, root.id);
    expect(find.byKey(const ValueKey('confirm-topology-merge')), findsNothing);
    await tester.tap(nodeA, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('topology-context-connect')),
      findsNothing,
    );
    await finish(tester);
  });

  testWidgets(
    'cancel mixed select-all deletion preserves every wire parent and task',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Root', task: 'one'),
      ))!;
      final a = (await tester.runAsync(
        () => workspaces.create(title: 'A', task: 'two', parentId: root.id),
      ))!;
      final b = (await tester.runAsync(
        () => workspaces.create(title: 'B', task: 'three', parentId: root.id),
      ))!;
      workspaces.connectTasks(a.id, b.id);
      await tester.pumpWidget(app());
      await tick(tester);
      await tester.tap(find.byKey(ValueKey('topology-node-${root.id}')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      Set<String> selectedWires() {
        final dynamic painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .firstWhere(
              (painter) => painter.runtimeType.toString() == '_TopologyPainter',
            );
        return Set<String>.of(painter.selectedEdges as Set<String>);
      }

      final ids = workspaces.connections.map((c) => c.id).toSet();
      expect(selectedWires(), ids);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(workspaces.connections.map((c) => c.id).toSet(), ids);
      expect(a.parentId, root.id);
      expect(b.parentId, root.id);
      await tester.tap(find.byKey(const ValueKey('cancel-topology-delete')));
      await tester.pumpAndSettle();
      expect(workspaces.sessions, hasLength(3));
      expect(workspaces.connections.map((c) => c.id).toSet(), ids);
      expect(selectedWires(), ids);
      expect(a.parentId, root.id);
      expect(b.parentId, root.id);
      expect(root.kind, AiWorkspaceKind.primary);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-topology-delete')));
      await tester.pumpAndSettle();
      expect(workspaces.sessions, isEmpty);
      expect(workspaces.connections, isEmpty);
      await finish(tester);
    },
  );

  testWidgets(
    'marquee selects wires on release and Ctrl adds wires for batch disconnect',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Root', task: 'one'),
      ))!;
      final first = (await tester.runAsync(
        () => workspaces.create(title: 'First', task: 'two', parentId: root.id),
      ))!;
      final second = (await tester.runAsync(
        () => workspaces.create(
          title: 'Second',
          task: 'three',
          parentId: root.id,
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final controller = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      controller.value = Matrix4.identity()..scaleByDouble(.5, .5, 1, 1);
      await tester.pump();
      Offset edgePoint(String childId) {
        Rect bounds(String id) {
          final node = tester.widget<Positioned>(
            find.byKey(ValueKey('topology-position-$id')),
          );
          return Rect.fromLTWH(
            node.left!,
            node.top!,
            node.width!,
            node.height!,
          );
        }

        final route = TaskTopologyConnection.between(
          bounds(root.id),
          bounds(childId),
        );
        final metric = route.path.computeMetrics().first;
        final point = metric.getTangentForOffset(metric.length * .8)!.position;
        return tester.getTopLeft(canvas) +
            MatrixUtils.transformPoint(controller.value, point);
      }

      Set<String> selectedWires() {
        final dynamic painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .firstWhere(
              (painter) => painter.runtimeType.toString() == '_TopologyPainter',
            );
        return Set<String>.of(painter.selectedEdges as Set<String>);
      }

      final point = edgePoint(first.id);
      final gesture = await tester.startGesture(point - const Offset(3, 15));
      await gesture.moveTo(point + const Offset(3, 15));
      await tester.pump();
      expect(selectedWires(), isEmpty);
      await gesture.up();
      await tester.pump();
      expect(selectedWires(), {first.id});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final other = edgePoint(second.id);
      await tester.dragFrom(other - const Offset(3, 15), const Offset(6, 30));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(selectedWires(), {first.id, second.id});
      await tester.tapAt(other, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(selectedWires(), {first.id, second.id});
      await tester.tap(find.byKey(const ValueKey('topology-edge-disconnect')));
      await tester.pumpAndSettle();
      expect(workspaces.connections, hasLength(2));
      for (final child in [first, second]) {
        expect(child.parentId, root.id);
        expect(child.kind, AiWorkspaceKind.permanent);
      }
      expect(find.textContaining('将变为主智能体'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('cancel-topology-disconnect')),
      );
      await tester.pumpAndSettle();
      expect(workspaces.connections, hasLength(2));
      expect(selectedWires(), {first.id, second.id});
      await tester.tapAt(other, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-edge-disconnect')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-topology-disconnect')),
      );
      await tester.pumpAndSettle();
      for (final child in [first, second]) {
        expect(child.parentId, isNull);
        expect(child.kind, AiWorkspaceKind.primary);
      }
      expect(workspaces.sessions, hasLength(3));
      expect(selectedWires(), isEmpty);
      await finish(tester);
    },
  );

  testWidgets(
    'curved wires click and Ctrl toggle like cards at every canvas zoom',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Root', task: 'one'),
      ))!;
      final first = (await tester.runAsync(
        () => workspaces.create(title: 'First', task: 'two', parentId: root.id),
      ))!;
      final second = (await tester.runAsync(
        () => workspaces.create(
          title: 'Second',
          task: 'three',
          parentId: root.id,
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final view = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      Offset edgePoint(String childId) {
        Rect bounds(String id) {
          final node = tester.widget<Positioned>(
            find.byKey(ValueKey('topology-position-$id')),
          );
          return Rect.fromLTWH(
            node.left!,
            node.top!,
            node.width!,
            node.height!,
          );
        }

        final route = TaskTopologyConnection.between(
          bounds(root.id),
          bounds(childId),
        );
        final metric = route.path.computeMetrics().first;
        return tester.getTopLeft(canvas) +
            MatrixUtils.transformPoint(
              view.value,
              metric.getTangentForOffset(metric.length * .55)!.position,
            );
      }

      Set<String> selectedWires() {
        final dynamic painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .firstWhere(
              (painter) => painter.runtimeType.toString() == '_TopologyPainter',
            );
        return Set<String>.of(painter.selectedEdges as Set<String>);
      }

      for (final scale in [.25, .65, 1.3]) {
        view.value =
            Matrix4.translationValues(20, 20, 0) *
            Matrix4.diagonal3Values(scale, scale, 1);
        await tester.pump();
        await tester.tap(find.byKey(ValueKey('topology-node-${root.id}')));
        await tester.pumpAndSettle();
        expect(selected(tester, root.id), isTrue);
        final point = edgePoint(second.id);
        final click = await tester.startGesture(point + const Offset(0, 2));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('topology-selection-overlay')),
          findsNothing,
        );
        await click.moveBy(const Offset(1, 1));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('topology-selection-overlay')),
          findsNothing,
        );
        await click.up();
        await tester.pump();
        expect(selectedWires(), {second.id});
        expect(selected(tester, root.id), isFalse);
        expect(workspaces.selectedId, isNull);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tapAt(edgePoint(first.id));
        await tester.pump();
        expect(selectedWires(), {first.id, second.id});
        await tester.tapAt(edgePoint(second.id));
        await tester.pump();
        expect(selectedWires(), {first.id});
        await tester.tap(find.byKey(ValueKey('topology-node-${root.id}')));
        await tester.pump();
        expect(selectedWires(), {first.id});
        expect(selected(tester, root.id), isTrue);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.tapAt(tester.getTopLeft(canvas) + const Offset(5, 5));
        await tester.pump();
        expect(selectedWires(), isEmpty);
        expect(selected(tester, root.id), isFalse);
      }
      await finish(tester);
    },
  );

  testWidgets(
    'right drag dismisses existing card and canvas menus without reopening',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Menus', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final view = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final node = find.byKey(ValueKey('topology-node-${task.id}'));
      for (final overCard in [false, true]) {
        await tester.tap(node, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topology-context-open')),
          findsOneWidget,
        );
        final before = view.value.clone();
        final start = overCard
            ? tester.getCenter(node)
            : tester.getTopLeft(canvas) + const Offset(20, 20);
        final drag = await tester.startGesture(
          start,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('topology-context-open')),
          findsNothing,
        );
        await drag.moveBy(const Offset(60, 35));
        await drag.up();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topology-context-open')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('topology-canvas-reset')),
          findsNothing,
        );
        expect(view.value.entry(0, 3), closeTo(before.entry(0, 3) + 60, .01));
        expect(view.value.entry(1, 3), closeTo(before.entry(1, 3) + 35, .01));
      }
      final blank = tester.getTopLeft(canvas) + const Offset(20, 20);
      await tester.tapAt(blank, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topology-canvas-reset')),
        findsOneWidget,
      );
      await tester.dragFrom(
        blank,
        const Offset(40, 20),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topology-canvas-reset')), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('conversation input owns selection and Delete shortcuts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final task = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Input target', task: 'one'),
    ))!;
    await tester.pumpWidget(app());
    await tick(tester);
    await tester.tap(find.byKey(ValueKey('topology-open-${task.id}')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('ai-message-input'));
    await tester.enterText(input, 'draft text');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: input, matching: find.byType(EditableText)),
          )
          .controller
          .selection,
      const TextSelection(baseOffset: 0, extentOffset: 10),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(workspaces.find(task.id), isNotNull);
    expect(find.byKey(const ValueKey('confirm-topology-delete')), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'default blank drag selects while Space and middle drag pan without bounds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Selection target', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final canvasFinder = find.byKey(const ValueKey('task-topology-canvas'));
      final viewer = tester.widget<InteractiveViewer>(canvasFinder);
      final controller = viewer.transformationController!;
      final before = controller.value.clone();
      final bounds = tester.getRect(
        find.byKey(ValueKey('topology-node-${task.id}')),
      );
      final box = await tester.startGesture(
        bounds.topLeft - const Offset(20, 20),
      );
      await tester.pump();
      await box.moveTo(bounds.bottomRight + const Offset(20, 20));
      await tester.pump();
      await box.up();
      await tester.pumpAndSettle();
      expect(selected(tester, task.id), isTrue);
      expect(controller.value, before);
      final blank = tester.getTopLeft(canvasFinder) + const Offset(20, 20);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.dragFrom(blank, const Offset(60, 35));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        controller.value.entry(0, 3),
        closeTo(before.entry(0, 3) + 60, .01),
      );
      expect(
        controller.value.entry(1, 3),
        closeTo(before.entry(1, 3) + 35, .01),
      );
      await tester.dragFrom(
        blank,
        const Offset(60, 35),
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        controller.value.entry(0, 3),
        closeTo(before.entry(0, 3) + 120, .01),
      );
      expect(
        controller.value.entry(1, 3),
        closeTo(before.entry(1, 3) + 70, .01),
      );
      controller.value = Matrix4.translationValues(-100000, -100000, 0);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.dragFrom(blank, const Offset(60, 35));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 3), closeTo(-99940, .01));
      expect(controller.value.entry(1, 3), closeTo(-99965, .01));
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'cards cross scene origin continuously and auto layout restores positions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Boundary target', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final canvasFinder = find.byKey(const ValueKey('task-topology-canvas'));
      final viewer = tester.widget<InteractiveViewer>(canvasFinder);
      final controller = viewer.transformationController!;
      final node = find.byKey(ValueKey('topology-node-${task.id}'));
      Offset position() {
        final item = tester.widget<Positioned>(
          find.byKey(ValueKey('topology-position-${task.id}')),
        );
        return Offset(item.left!, item.top!);
      }

      final original = position();
      controller.value =
          Matrix4.translationValues(
            800 - original.dx * .5,
            230 - original.dy * .5,
            0,
          ) *
          Matrix4.diagonal3Values(.5, .5, 1);
      await tester.pump();
      final before = tester.getCenter(node);
      final gesture = await tester.startGesture(before);
      await gesture.moveTo(before - const Offset(400, 100));
      await tester.pump();
      expect((tester.getCenter(node) - before).dx, closeTo(-400, 2));
      expect((tester.getCenter(node) - before).dy, closeTo(-100, 2));
      await gesture.moveTo(before - const Offset(460, 130));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect((tester.getCenter(node) - before).dx, closeTo(-460, 2));
      expect((tester.getCenter(node) - before).dy, closeTo(-130, 2));
      expect(position().dx, greaterThan(0));
      expect(position().dy, greaterThan(0));
      final rebased = position();
      controller.value =
          Matrix4.translationValues(
            700 - rebased.dx * 1.5,
            330 - rebased.dy * 1.5,
            0,
          ) *
          Matrix4.diagonal3Values(1.5, 1.5, 1);
      await tester.pump();
      final zoomedBefore = tester.getCenter(node);
      await tester.drag(node, const Offset(-600, -400));
      await tester.pumpAndSettle();
      expect((tester.getCenter(node) - zoomedBefore).dx, closeTo(-600, 2));
      expect((tester.getCenter(node) - zoomedBefore).dy, closeTo(-400, 2));
      await tester.tap(find.byKey(ValueKey('topology-open-${task.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      final moved = position();
      await tester.tap(find.byIcon(Symbols.fit_screen_rounded));
      await tester.pumpAndSettle();
      expect(
        position(),
        moved,
        reason: 'Reset view preserves manual arrangement',
      );
      await tester.tap(find.byKey(const ValueKey('topology-auto-layout')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(position(), original);
      await tester.pumpAndSettle();
      final canvas = tester.getRect(canvasFinder);
      final footer = tester.getRect(
        find.byKey(const ValueKey('topology-footer')),
      );
      expect(footer.top, greaterThanOrEqualTo(canvas.bottom));
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'scene expands beyond its initial right edge and remains clickable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Expand target', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final finder = find.byKey(const ValueKey('task-topology-canvas'));
      final viewer = tester.widget<InteractiveViewer>(finder);
      final originalSize = (viewer.child as SizedBox).width!;
      final positioned = tester.widget<Positioned>(
        find.byKey(ValueKey('topology-position-${task.id}')),
      );
      viewer.transformationController!.value =
          Matrix4.translationValues(
            80 - positioned.left! * .5,
            180 - positioned.top! * .5,
            0,
          ) *
          Matrix4.diagonal3Values(.5, .5, 1);
      await tester.pump();
      final node = find.byKey(ValueKey('topology-node-${task.id}'));
      final before = tester.getCenter(node);
      await tester.drag(node, const Offset(800, 100));
      await tester.pumpAndSettle();
      expect((tester.getCenter(node) - before).dx, closeTo(800, 2));
      expect(
        (tester.widget<InteractiveViewer>(finder).child as SizedBox).width!,
        greaterThan(originalSize),
      );
      await tester.tap(find.byKey(ValueKey('topology-open-${task.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'card Space and middle panning do not select or open its conversation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Pan target', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final node = find.byKey(ValueKey('topology-node-${task.id}'));
      final controller = tester
          .widget<InteractiveViewer>(
            find.byKey(const ValueKey('task-topology-canvas')),
          )
          .transformationController!;
      final start = controller.value.clone();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.drag(node, const Offset(60, 30));
      await tester.pumpAndSettle();
      await tester.tap(node);
      await tester.tap(node);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(selected(tester, task.id), isFalse);
      expect(find.byKey(const ValueKey('ai-message-input')), findsNothing);
      expect(
        controller.value.entry(0, 3),
        closeTo(start.entry(0, 3) + 60, .01),
      );
      await tester.drag(
        node,
        const Offset(60, 30),
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();
      expect(selected(tester, task.id), isFalse);
      expect(
        controller.value.entry(0, 3),
        closeTo(start.entry(0, 3) + 120, .01),
      );
      await finish(tester);
    },
  );

  testWidgets(
    'light card open button hovers using its actual surface and compact footer fits',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      theme.setTheme(ThemeType.light);
      final task = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Hover target', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final buttonFinder = find.byKey(ValueKey('topology-open-${task.id}'));
      final button = tester.widget<TitleBarIconButton>(buttonFinder);
      expect(button.surfaceColor, button.theme.primary);
      expect(button.backgroundColor, Colors.transparent);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(buttonFinder));
      await tester.pumpAndSettle();
      final decoration = tester
          .widget<InteractionDecoration>(
            find.descendant(
              of: buttonFinder,
              matching: find.byType(InteractionDecoration),
            ),
          )
          .decoration;
      expect(
        decoration.color,
        button.theme.buttonColorsForSurface(button.theme.primary).hover,
      );
      expect(decoration.color!.computeLuminance(), greaterThan(.5));
      await mouse.removePointer();
      await tester.binding.setSurfaceSize(const Size(320, 500));
      await tester.pumpAndSettle();
      final footer = tester.getRect(
        find.byKey(const ValueKey('topology-footer')),
      );
      final canvas = tester.getRect(
        find.byKey(const ValueKey('task-topology-canvas')),
      );
      expect(footer.top, greaterThanOrEqualTo(canvas.bottom));
      expect(
        find.byKey(const ValueKey('topology-auto-layout')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'role menu converts only its target and excludes descendants from parents',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Move tree', task: 'one'),
      ))!;
      final child = (await tester.runAsync(
        () => workspaces.create(
          title: 'Descendant',
          task: 'two',
          parentId: root.id,
        ),
      ))!;
      final other = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'New parent', task: 'three'),
      ))!;
      final temporary = (await tester.runAsync(
        () => workspaces.create(
          title: 'Temporary',
          task: 'four',
          parentId: other.id,
          kind: AiWorkspaceKind.permanent,
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final rootNode = find.byKey(ValueKey('topology-node-${root.id}'));
      final otherNode = find.byKey(ValueKey('topology-node-${other.id}'));
      await tester.tap(rootNode);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(otherNode);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.tap(rootNode, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topology-context-make-child')),
      );
      await tester.pumpAndSettle();
      final select = tester.widget<SettingSelect<String>>(
        find.byKey(const ValueKey('topology-parent-select')),
      );
      expect(select.items.map((item) => item.value), [other.id, temporary.id]);
      expect(
        select.items.any((item) => [root.id, child.id].contains(item.value)),
        isFalse,
      );
      final assistant = root.assistant;
      await tester.tap(find.byKey(const ValueKey('topology-parent-confirm')));
      await tester.pumpAndSettle();
      expect(root.parentId, other.id);
      expect(root.kind, AiWorkspaceKind.permanent);
      expect(other.parentId, isNull);
      expect(child.parentId, root.id);
      expect(root.assistant, same(assistant));
      await tester.tap(rootNode, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('topology-context-make-root')),
          matching: find.byIcon(Symbols.hub_rounded),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('topology-context-make-root')),
      );
      await tester.pumpAndSettle();
      expect(root.kind, AiWorkspaceKind.permanent);
      expect(root.parentId, other.id);
      await tester.tap(find.byKey(const ValueKey('cancel-topology-make-root')));
      await tester.pumpAndSettle();
      expect(root.kind, AiWorkspaceKind.permanent);
      await tester.tap(rootNode, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topology-context-make-root')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-topology-make-root')),
      );
      await tester.pumpAndSettle();
      expect(root.kind, AiWorkspaceKind.primary);
      expect(root.parentId, isNull);
      expect(child.parentId, root.id);
      expect(root.assistant, same(assistant));
      await finish(tester);
    },
  );

  testWidgets('root with only descendants cannot choose an invalid parent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Root', task: 'one'),
    ))!;
    await tester.runAsync(
      () => workspaces.create(
        title: 'Only descendant',
        task: 'two',
        parentId: root.id,
      ),
    );
    await tester.pumpWidget(app());
    await tick(tester);
    await tester.tap(
      find.byKey(ValueKey('topology-node-${root.id}')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('topology-context-make-child')),
      findsNothing,
    );
    await finish(tester);
  });

  testWidgets(
    'rename targets the right clicked card and retains identity and conversation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Old title', task: 'one'),
      ))!;
      final other = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Keep title', task: 'two'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final assistant = root.assistant;
      await tester.tap(
        find.byKey(ValueKey('topology-node-${root.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-context-rename')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('topology-rename-input'));
      await tester.enterText(input, '   ');
      await tester.pump();
      expect(
        tester
            .widget<AppActionButton>(
              find.byKey(const ValueKey('topology-rename-confirm')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: input, matching: find.byType(TextField)),
            )
            .maxLines,
        4,
      );
      await tester.enterText(input, '  Updated\ntitle  ');
      await tester.pump();
      expect(
        find.descendant(
          of: input,
          matching: find.byWidgetPredicate((widget) => widget is RawScrollbar),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('topology-rename-confirm')));
      await tester.pumpAndSettle();
      expect(root.title, 'Updated\ntitle');
      expect(other.title, 'Keep title');
      expect(workspaces.find(root.id), same(root));
      expect(root.assistant, same(assistant));
      await tester.tap(find.byKey(ValueKey('topology-open-${root.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Updated\ntitle'), findsWidgets);
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'canvas undo redo restores moves copies deletion and clears redo after a new edit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: 'History task',
          task: 'Keep context',
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      Offset position(String id) {
        final widget = tester.widget<Positioned>(
          find.byKey(ValueKey('topology-position-$id')),
        );
        return Offset(widget.left!, widget.top!);
      }

      Future<void> shortcut(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tick(tester);
      }

      final initial = position(original.id);
      await tester.drag(
        find.byKey(ValueKey('topology-node-${original.id}')),
        const Offset(60, 30),
      );
      await tester.pumpAndSettle();
      final moved = position(original.id);
      expect(moved, isNot(initial));
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(position(original.id), initial);
      await shortcut(LogicalKeyboardKey.keyY);
      expect(position(original.id), moved);
      await tester.tap(find.byKey(const ValueKey('topology-auto-layout')));
      await tester.pumpAndSettle();
      expect(position(original.id), initial);
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(position(original.id), moved);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tick(tester);
      expect(position(original.id), initial);
      await tester.tap(
        find.byKey(ValueKey('topology-node-${original.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topology-context-duplicate')),
      );
      await tick(tester);
      final copy = workspaces.sessions.singleWhere(
        (task) => task.id != original.id,
      );
      expect(copy.title, 'History task (2)');
      final copyId = copy.id;
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(workspaces.sessions, hasLength(1));
      await shortcut(LogicalKeyboardKey.keyY);
      expect(workspaces.find(copyId), isNotNull);
      expect(workspaces.find(copyId)!.title, 'History task (2)');
      await tester.tap(find.byKey(ValueKey('topology-node-${copyId}')));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-topology-delete')));
      await tick(tester);
      expect(workspaces.find(copyId), isNull);
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(workspaces.find(copyId), isNotNull);
      await shortcut(LogicalKeyboardKey.keyY);
      expect(workspaces.find(copyId), isNull);
      await shortcut(LogicalKeyboardKey.keyZ);
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(workspaces.find(copyId), isNull);
      await tester.drag(
        find.byKey(ValueKey('topology-node-${original.id}')),
        const Offset(60, 30),
      );
      await tester.pumpAndSettle();
      await shortcut(LogicalKeyboardKey.keyY);
      expect(workspaces.find(copyId), isNull);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'duplicate card is offset selected and idle with no tilt effect',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: List.filled(200, '测').join(),
          task: 'Keep task draft',
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final originalPosition = tester.widget<Positioned>(
        find.byKey(ValueKey('topology-position-${original.id}')),
      );
      await tester.tap(
        find.byKey(ValueKey('topology-node-${original.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topology-context-duplicate')),
      );
      await tick(tester);
      expect(workspaces.sessions, hasLength(2));
      final copy = workspaces.sessions.firstWhere(
        (item) => item.id != original.id,
      );
      final copiedPosition = tester.widget<Positioned>(
        find.byKey(ValueKey('topology-position-${copy.id}')),
      );
      expect(copiedPosition.left, originalPosition.left! + 40);
      expect(copiedPosition.top, originalPosition.top! + 40);
      expect(selected(tester, copy.id), isTrue);
      expect(selected(tester, original.id), isFalse);
      expect(find.byKey(const ValueKey('ai-message-input')), findsNothing);
      expect(copy.title, original.title);
      expect(copy.busy, isFalse);
      expect(
        copy.assistant.messages.map((m) => m.content),
        original.assistant.messages.map((m) => m.content),
      );
      expect(copy.assistant, isNot(same(original.assistant)));
      expect(find.byType(TiltCard), findsNothing);
      for (final task in [original, copy]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('topology-node-${task.id}')),
            matching: find.byType(CardShadow),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(ValueKey('topology-open-${copy.id}')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ai-message-input')))
            .controller!
            .text,
        isEmpty,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'canvas clipboard pastes complete independent cards and leaves text input shortcuts alone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final name = List.filled(200, '测').join();
      final source = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: name,
          task: 'Complete original task instructions',
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      await tester.tap(find.byKey(ValueKey('topology-node-${source.id}')));
      await tester.pumpAndSettle();
      Future<void> shortcut(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tick(tester);
      }

      await shortcut(LogicalKeyboardKey.keyC);
      workspaces.rename(source.id, 'Changed after copying');
      await tester.pumpAndSettle();
      await shortcut(LogicalKeyboardKey.keyV);
      expect(workspaces.sessions, hasLength(2));
      final copy = workspaces.sessions.last;
      expect(copy.title, name);
      expect(copy.task, source.task);
      expect(copy.id, isNot(source.id));
      expect(
        copy.assistant.messages.map((m) => m.content),
        source.assistant.messages.map((m) => m.content),
      );
      expect(copy.busy, isFalse);
      expect(selected(tester, copy.id), isTrue);
      await shortcut(LogicalKeyboardKey.keyV);
      expect(workspaces.sessions, hasLength(3));
      clipboard = 'ordinary text';
      await shortcut(LogicalKeyboardKey.keyV);
      expect(workspaces.sessions, hasLength(3));
      final last = workspaces.sessions.last;
      await tester.tap(find.byKey(ValueKey('topology-open-${last.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-message-input')));
      await shortcut(LogicalKeyboardKey.keyV);
      expect(workspaces.sessions, hasLength(3));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ai-message-input')))
            .controller!
            .text,
        contains('ordinary text'),
      );
      await finish(tester);
    },
  );

  testWidgets(
    'right drag pans on blank and cards but right click still opens the menu',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Right drag target', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final controller = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final start = controller.value.clone();
      final blank = tester.getTopLeft(canvas) + const Offset(20, 20);
      await tester.dragFrom(
        blank,
        const Offset(60, 35),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        controller.value.entry(0, 3),
        closeTo(start.entry(0, 3) + 60, .01),
      );
      expect(
        controller.value.entry(1, 3),
        closeTo(start.entry(1, 3) + 35, .01),
      );
      expect(find.byKey(const ValueKey('topology-context-open')), findsNothing);
      expect(
        find.byKey(const ValueKey('topology-edge-disconnect')),
        findsNothing,
      );
      final node = find.byKey(ValueKey('topology-node-${task.id}'));
      await tester.drag(
        node,
        const Offset(60, 35),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        controller.value.entry(0, 3),
        closeTo(start.entry(0, 3) + 120, .01),
      );
      expect(
        controller.value.entry(1, 3),
        closeTo(start.entry(1, 3) + 70, .01),
      );
      expect(selected(tester, task.id), isFalse);
      expect(find.byKey(const ValueKey('topology-context-open')), findsNothing);
      await tester.tap(node, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topology-context-open')),
        findsOneWidget,
      );
      expect(selected(tester, task.id), isTrue);
      await finish(tester);
    },
  );

  testWidgets(
    'card selection border fades both ways and respects reduced motion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Selection fade', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final node = find.byKey(ValueKey('topology-node-${task.id}'));
      BorderSide border() =>
          ((tester
                              .widget<DecoratedBox>(
                                find
                                    .descendant(
                                      of: node,
                                      matching: find.byWidgetPredicate(
                                        (widget) =>
                                            widget is DecoratedBox &&
                                            widget.position ==
                                                DecorationPosition.foreground,
                                      ),
                                    )
                                    .first,
                              )
                              .decoration
                          as BoxDecoration)
                      .border!
                  as Border)
              .top;
      expect(border().color.a, 0);
      await tester.tap(node);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(border().color.a, greaterThan(0));
      expect(border().color.a, lessThan(1));
      expect(border().width, 1);
      await tester.pumpAndSettle();
      expect(border().color, theme.themeData.basePrimary);
      final blank =
          tester.getTopLeft(
            find.byKey(const ValueKey('task-topology-canvas')),
          ) +
          const Offset(20, 20);
      await tester.tapAt(blank);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(border().color.a, greaterThan(0));
      expect(border().color.a, lessThan(1));
      await tester.pumpAndSettle();
      expect(border().color.a, 0);
      await tester.pumpWidget(app(disableAnimations: true));
      await tester.pumpAndSettle();
      await tester.tap(node);
      await tester.pumpAndSettle();
      expect(border().color, theme.themeData.basePrimary);
      await finish(tester);
    },
  );

  testWidgets(
    'blank mouse release clears selection and another card replaces it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'First', task: 'one'),
      ))!;
      final second = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Second', task: 'two'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      await tester.tap(find.byKey(ValueKey('topology-node-${first.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('topology-node-${second.id}')));
      await tester.pumpAndSettle();
      expect(selected(tester, first.id), isFalse);
      expect(selected(tester, second.id), isTrue);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final blank = tester.getTopLeft(canvas) + const Offset(20, 20);
      final click = await tester.startGesture(
        blank,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await click.moveBy(const Offset(1, 1));
      await tester.pump();
      await click.up();
      await tester.pumpAndSettle();
      expect(selected(tester, first.id), isFalse);
      expect(selected(tester, second.id), isFalse);
      expect(workspaces.selectedId, isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'blank right click clears node selection and offers canvas controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Canvas target', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final view = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final blank = tester.getTopLeft(canvas) + const Offset(20, 20);
      await tester.tap(
        find.byKey(ValueKey('topology-node-${task.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(selected(tester, task.id), isTrue);
      expect(
        find.byKey(const ValueKey('topology-context-open')),
        findsOneWidget,
      );
      await tester.tapAt(blank, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(selected(tester, task.id), isFalse);
      expect(workspaces.selectedId, isNull);
      expect(find.byKey(const ValueKey('topology-context-open')), findsNothing);
      for (final key in [
        'zoom-out',
        'zoom-in',
        'auto-layout',
        'reset',
        'background-dots',
        'background-grid',
        'background-plain',
      ]) {
        expect(find.byKey(ValueKey('topology-canvas-$key')), findsOneWidget);
      }
      final scale = view.value.entry(0, 0);
      await tester.tap(find.byKey(const ValueKey('topology-canvas-zoom-in')));
      await tester.pumpAndSettle();
      expect(view.value.entry(0, 0), greaterThan(scale));
      expect(
        find.byKey(const ValueKey('topology-canvas-zoom-in')),
        findsNothing,
      );
      await tester.tapAt(blank, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topology-canvas-background-grid')),
      );
      await tester.pumpAndSettle();
      expect(workspaces.canvasStyle, AiTaskCanvasStyle.grid);
      await tester.dragFrom(
        blank,
        const Offset(60, 35),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topology-canvas-zoom-in')),
        findsNothing,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'Ctrl wheel zooms once around pointer without prior focus and stays inside canvas',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Wheel target', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final controller = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final local = const Offset(250, 150);
      final pointer = tester.getTopLeft(canvas) + local;
      Future<void> scrollAt(Offset point) async {
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: point,
            scrollDelta: const Offset(0, -100),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();
      }

      final initial = controller.value.clone();
      await scrollAt(pointer);
      expect(controller.value.entry(0, 0), initial.entry(0, 0));
      expect(controller.value.entry(1, 3), initial.entry(1, 3) + 100);
      controller.value = initial.clone();
      await tester.pump();
      final anchored = controller.toScene(local);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await scrollAt(pointer);
      expect(
        controller.value.entry(0, 0),
        closeTo((initial.entry(0, 0) * math.exp(.5)).clamp(.25, 1.8), .001),
      );
      expect((controller.toScene(local) - anchored).distance, lessThan(.001));
      await tester.tap(
        find.byKey(ValueKey('topology-node-${task.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final afterZoom = controller.value.clone();
      await scrollAt(
        tester.getCenter(
          find.byKey(const ValueKey('topology-context-copy-id')),
        ),
      );
      expect(
        controller.value.entry(0, 0),
        greaterThan(afterZoom.entry(0, 0)),
        reason: 'Ctrl wheel closes the menu and zooms the canvas',
      );
      expect(
        find.byKey(const ValueKey('topology-context-copy-id')),
        findsNothing,
      );
      final beforeChat = controller.value.clone();
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(20, 20));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('topology-open-${task.id}')));
      await tester.pumpAndSettle();
      await scrollAt(
        tester.getCenter(find.byKey(const ValueKey('ai-message-input'))),
      );
      expect(
        controller.value,
        beforeChat,
        reason: 'Chat wheel must not reach retained canvas',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await finish(tester);
    },
  );

  testWidgets(
    'wheel pans vertically and Shift pans horizontally with cumulative smooth motion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(
        () => workspaces.createPrimary(title: 'Pan', task: 'one'),
      );
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final controller = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final point = tester.getTopLeft(canvas) + const Offset(20, 20);
      final initial = controller.value.clone();
      void wheel(double dy) => tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: point,
          scrollDelta: Offset(0, dy),
          kind: PointerDeviceKind.mouse,
        ),
      );
      wheel(40);
      wheel(40);
      expect(controller.value, initial);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.value.entry(1, 3), lessThan(initial.entry(1, 3)));
      expect(
        controller.value.entry(1, 3),
        greaterThan(initial.entry(1, 3) - 80),
      );
      await tester.pumpAndSettle();
      expect(
        controller.value.entry(1, 3),
        closeTo(initial.entry(1, 3) - 80, .001),
      );
      expect(controller.value.entry(0, 3), initial.entry(0, 3));
      final vertical = controller.value.clone();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      wheel(30);
      wheel(30);
      await tester.pumpAndSettle();
      expect(
        controller.value.entry(0, 3),
        closeTo(vertical.entry(0, 3) - 60, .001),
      );
      expect(controller.value.entry(1, 3), vertical.entry(1, 3));
      expect(controller.value.entry(0, 0), initial.entry(0, 0));
      wheel(40);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final reversedFrom = controller.value.entry(0, 3);
      wheel(-20);
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 3), closeTo(reversedFrom + 20, .001));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpWidget(app(disableAnimations: true));
      await tester.pumpAndSettle();
      final before = controller.value.entry(1, 3);
      wheel(30);
      expect(controller.value.entry(1, 3), before - 30);
      await finish(tester);
    },
  );

  testWidgets(
    'Ctrl wheel animates cumulative zoom around pointer and reverses from current frame',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(
        () => workspaces.createPrimary(title: 'Smooth wheel', task: 'one'),
      );
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final view = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      view.value = Matrix4.diagonal3Values(.5, .5, 1);
      await tester.pump();
      const local = Offset(250, 150);
      final point = tester.getTopLeft(canvas) + local;
      final anchored = view.toScene(local);
      void wheel(double delta) => tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: point,
          scrollDelta: Offset(0, delta),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      wheel(-20);
      wheel(-20);
      expect(view.value.entry(0, 0), .5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midway = view.value.entry(0, 0);
      expect(midway, greaterThan(.5));
      expect(midway, lessThan(.5 * math.exp(.2)));
      expect((view.toScene(local) - anchored).distance, lessThan(.001));
      await tester.pumpAndSettle();
      expect(view.value.entry(0, 0), closeTo(.5 * math.exp(.2), .001));
      wheel(-20);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final beforeReverse = view.value.entry(0, 0);
      wheel(20);
      await tester.pumpAndSettle();
      expect(
        view.value.entry(0, 0),
        closeTo(beforeReverse * math.exp(-.1), .001),
      );
      expect((view.toScene(local) - anchored).distance, lessThan(.001));
      await tester.pumpWidget(app(disableAnimations: true));
      await tester.pumpAndSettle();
      view.value = Matrix4.diagonal3Values(.5, .5, 1);
      await tester.pump();
      wheel(-20);
      expect(view.value.entry(0, 0), closeTo(.5 * math.exp(.1), .001));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await finish(tester);
    },
  );

  testWidgets(
    'selecting an off-center card and opening it never fits the view',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync(
        () =>
            workspaces.createPrimary(title: 'Keep this position', task: 'one'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final view = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final position = tester.widget<Positioned>(
        find.byKey(ValueKey('topology-position-${task.id}')),
      );
      view.value =
          Matrix4.translationValues(
            70 - position.left! * .7,
            450 - position.top! * .7,
            0,
          ) *
          Matrix4.diagonal3Values(.7, .7, 1);
      await tester.pump();
      final before = view.value.clone();
      final node = find.byKey(ValueKey('topology-node-${task.id}'));
      final location = tester.getRect(node);
      final click = tester.getCenter(node);
      await tester.tapAt(click);
      await tester.pump(const Duration(milliseconds: 50));
      expect(selected(tester, task.id), isTrue);
      expect(view.value, before);
      expect(tester.getRect(node), location);
      await tester.tapAt(click);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      expect(view.value, before);
      await tester.binding.setSurfaceSize(const Size(1080, 800));
      await tester.pumpAndSettle();
      expect(
        view.value,
        before,
        reason: 'Resizing must not implicitly fit the view',
      );
      await finish(tester);
    },
  );

  testWidgets('short title remains a card drag target', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final task = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Short title', task: 'one'),
    ))!;
    await tester.pumpWidget(app());
    await tick(tester);
    final node = find.byKey(ValueKey('topology-node-${task.id}'));
    final region = find.byKey(ValueKey('topology-title-${task.id}'));
    expect(
      tester
          .widget<MenuItemSurface>(
            find.byKey(const ValueKey('topology-new-child')),
          )
          .onPressed,
      isNull,
    );
    final before = tester.getCenter(node);
    await tester.drag(region, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect((tester.getCenter(node) - before).dx, closeTo(60, 2));
    expect(find.byKey(const ValueKey('topology-new-child')), findsOneWidget);
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MenuItemSurface>(
            find.byKey(const ValueKey('topology-new-child')),
          )
          .onPressed,
      isNull,
    );
    await finish(tester);
  });

  for (final textScale in [1.0, 1.5]) {
    testWidgets(
      'card grows to show full title and conversation stays compact at scale $textScale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1180, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final root = (await tester.runAsync(
          () => workspaces.createPrimary(title: 'Short', task: 'one'),
        ))!;
        await tester.pumpWidget(app(textScale: textScale));
        await tick(tester);
        final canvas = find.byKey(const ValueKey('task-topology-canvas'));
        final view = tester
            .widget<InteractiveViewer>(canvas)
            .transformationController!;
        final viewBefore = view.value.clone();
        Positioned position() => tester.widget<Positioned>(
          find.byKey(ValueKey('topology-position-${root.id}')),
        );
        final initial = position();
        expect(initial.width, 252);
        expect(initial.height, lessThan(164 * textScale));
        const title =
            'First title line\nSecond title line\nThird title line\nFourth title line\nFifth title line\nSixth title line';
        workspaces.rename(root.id, title);
        await tester.pumpAndSettle();
        expect(position().width, 252);
        expect(
          position().height,
          greaterThan(initial.height! + 50 * textScale),
        );
        expect(position().left, initial.left);
        expect(position().top, initial.top);
        expect(view.value, viewBefore);
        final node = find.byKey(ValueKey('topology-node-${root.id}'));
        final region = find.byKey(ValueKey('topology-title-${root.id}'));
        final text = tester.widget<Text>(region);
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        expect(
          find.descendant(of: node, matching: find.byType(Scrollable)),
          findsNothing,
        );
        final modelRect = tester.getRect(
          find.byKey(ValueKey('topology-model-label-${root.id}')),
        );
        expect(tester.getRect(region).bottom, lessThan(modelRect.top));
        final label = tester.widget<Text>(
          find.byKey(ValueKey('topology-model-label-${root.id}')),
        );
        expect(label.data, '模型服务：Local model · gpt-6.1-sol');
        final cardId = tester.widget<Text>(
          find.byKey(ValueKey('topology-task-id-${root.id}')),
        );
        expect(cardId.data, endsWith(root.id));
        expect(cardId.maxLines, isNull);
        expect(cardId.overflow, isNot(TextOverflow.ellipsis));
        final cardRect = tester.getRect(node);
        final bottomPort = tester.getCenter(
          find.byKey(ValueKey('topology-port-bottom-${root.id}')),
        );
        expect(bottomPort.dy, closeTo(cardRect.bottom, 2));
        final rightPort = tester.getCenter(
          find.byKey(ValueKey('topology-port-out-${root.id}')),
        );
        expect(rightPort.dy, closeTo(cardRect.center.dy, 2));
        // Select a visible strip below the original short card bounds.
        final visibleBottom = math.min(
          cardRect.bottom,
          tester.getRect(canvas).bottom - 20,
        );
        await tester.tapAt(const Offset(50, 200));
        final box = await tester.startGesture(
          Offset(cardRect.left - 15, visibleBottom - 8),
        );
        await box.moveTo(Offset(cardRect.right + 15, visibleBottom - 2));
        await tester.pump();
        expect(selected(tester, root.id), isFalse);
        await box.up();
        await tester.pumpAndSettle();
        expect(
          selected(tester, root.id),
          isTrue,
          reason:
              'card=$cardRect actual=${tester.getRect(node)} canvas=${tester.getRect(canvas)}',
        );
        workspaces.rename(root.id, 'Short');
        await tester.pumpAndSettle();
        expect(position().height, initial.height);
        workspaces.rename(
          root.id,
          List.filled(8, 'Long unbroken task name').join(' '),
        );
        await tester.pumpAndSettle();
        expect(position().height, greaterThan(initial.height!));
        expect(tester.takeException(), isNull);
        workspaces.rename(root.id, title);
        await tester.pumpAndSettle();
        await captureOverlay(tester, 'lilygobox-auto-height-title-$textScale');
        await tester.tap(find.byKey(ValueKey('topology-open-${root.id}')));
        await tester.pumpAndSettle();
        final header = find.byKey(
          ValueKey('topology-conversation-title-scroll-${root.id}'),
        );
        final headerScroll = tester
            .widget<SingleChildScrollView>(
              find.descendant(
                of: header,
                matching: find.byType(SingleChildScrollView),
              ),
            )
            .controller!;
        expect(headerScroll.position.maxScrollExtent, greaterThan(0));
        expect(
          find.descendant(of: header, matching: find.byType(Scrollbar)),
          findsOneWidget,
        );
        expect(
          tester.getSize(header).height,
          lessThanOrEqualTo(38 * textScale),
        );
        final backBefore = tester.getRect(
          find.byKey(const ValueKey('topology-back')),
        );
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: tester.getCenter(header),
            scrollDelta: const Offset(0, 70),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();
        expect(headerScroll.offset, greaterThan(0));
        expect(
          tester.getRect(find.byKey(const ValueKey('topology-back'))),
          backBefore,
        );
        expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
        await captureOverlay(tester, 'lilygobox-conversation-title-$textScale');
        workspaces.rename(root.id, '2');
        await tester.pumpAndSettle();
        final info = find.byKey(
          ValueKey('topology-conversation-info-${root.id}'),
        );
        expect(tester.widget(info), isA<Column>());
        expect(
          find.descendant(
            of: info,
            matching: find.textContaining('gpt-6.1-sol'),
          ),
          findsNothing,
        );
        final infoIcon = tester.widget<Icon>(
          find.descendant(of: info, matching: find.byType(Icon)),
        );
        expect(infoIcon.icon, Symbols.hub_rounded);
        expect(infoIcon.fill, 1);
        expect(tester.getRect(info).right, closeTo(1180 - 16, 1));
        final headerId = tester.widget<Text>(
          find.byKey(ValueKey('topology-conversation-task-id-${root.id}')),
        );
        expect(headerId.data, endsWith(root.id));
        expect(headerId.maxLines, isNull);
        expect(headerId.overflow, isNot(TextOverflow.ellipsis));
        await captureOverlay(
          tester,
          'lilygobox-inline-conversation-title-$textScale',
        );

        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }

  for (final asking in [false, true]) {
    testWidgets(
      'read-only task retains ${asking ? "question" : "approval"} controls',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1180, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        nextTool = {
          'id': 'required-input',
          'type': 'function',
          'function': {
            'name': asking ? 'request_user_input' : 'write_file',
            'arguments': jsonEncode(
              asking
                  ? {
                      'questions': [
                        {
                          'id': 'scope',
                          'header': '处理范围',
                          'question': '需要处理哪些文件？',
                          'options': [
                            {'label': '当前目录', 'description': '处理当前目录。'},
                            {'label': '整个项目', 'description': '处理整个项目。'},
                          ],
                        },
                      ],
                    }
                  : {
                      'path':
                          'C:/Users/XK/AppData/Local/Temp/lilygobox-readonly-approval-test.txt',
                      'content': 'Never approved in this test.',
                      'expected_content': null,
                    },
            ),
          },
        };
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<AppShellProvider>.value(value: shell),
              ChangeNotifierProvider<AppNavigationProvider>.value(
                value: navigation,
              ),
              ChangeNotifierProvider<AiAssistantProvider>.value(
                value: scope.provider,
              ),
            ],
            child: MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: AssistantPage(readOnly: true)),
            ),
          ),
        );
        final sending = scope.provider.sendMessage('Request required input.');
        for (
          var i = 0;
          i < 30 &&
              (asking
                  ? scope.provider.pendingUserInput == null
                  : scope.provider.pendingApproval == null);
          i++
        ) {
          await tick(tester);
        }
        expect(
          asking
              ? scope.provider.pendingUserInput
              : scope.provider.pendingApproval,
          isNotNull,
          reason:
              'error=${scope.provider.error} messages=${scope.provider.messages.map((m) => m.content).toList()}',
        );
        expect(
          find.byKey(
            ValueKey(asking ? 'ai-user-input-panel' : 'ai-approval-panel'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('ai-message-input')), findsNothing);
        await tester.tap(
          find.byKey(
            ValueKey(asking ? 'ai-user-input-cancel' : 'ai-approval-deny'),
          ),
        );
        await tick(tester);
        await sending;
        expect(scope.provider.pendingApproval, isNull);
        expect(scope.provider.pendingUserInput, isNull);
        expect(scope.provider.busy, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dragging zoomed nodes tracks the same screen distance', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final primary = (await tester.runAsync(
      () => workspaces.createPrimary(
        title: 'Drag target',
        task: 'Complete task.',
      ),
    ))!;
    await tester.pumpWidget(app());
    await tick(tester);
    final node = find.byKey(ValueKey('topology-node-${primary.id}'));
    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('task-topology-canvas')),
    );
    for (final scale in [.5, 1.5]) {
      final positioned = tester.widget<Positioned>(
        find.byKey(ValueKey('topology-position-${primary.id}')),
      );
      viewer.transformationController!.value =
          Matrix4.translationValues(
            150 - positioned.left! * scale,
            200 - positioned.top! * scale,
            0,
          ) *
          Matrix4.diagonal3Values(scale, scale, 1);
      await tester.pump();
      final before = tester.getCenter(node);
      await tester.drag(node, const Offset(60, 0));
      await tester.pumpAndSettle();
      final moved = tester.getCenter(node) - before;
      expect(moved.dx, closeTo(60, 2), reason: 'scale=$scale');
      expect(moved.dy, closeTo(0, 2), reason: 'scale=$scale');
    }
    await finish(tester);
  });

  testWidgets('reset view interpolates and manual zoom interrupts it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(
      () => workspaces.createPrimary(
        title: 'Reset target',
        task: 'Complete task.',
      ),
    );
    await tester.pumpWidget(app());
    await tick(tester);
    final controller = tester
        .widget<InteractiveViewer>(
          find.byKey(const ValueKey('task-topology-canvas')),
        )
        .transformationController!;
    final target = controller.value.clone();
    final before =
        Matrix4.translationValues(300, 150, 0) *
        Matrix4.diagonal3Values(.5, .5, 1);
    controller.value = before;
    await tester.pump();
    await tester.tap(find.byIcon(Symbols.fit_screen_rounded));
    await tester.pump();
    expect(controller.value.storage, orderedEquals(before.storage));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.value.entry(0, 0), greaterThan(.5));
    expect(controller.value.entry(0, 0), lessThan(target.entry(0, 0)));
    await tester.pumpAndSettle();
    for (var i = 0; i < 16; i++) {
      expect(controller.value.storage[i], closeTo(target.storage[i], .001));
    }
    controller.value = before;
    await tester.pump();
    await tester.tap(find.byIcon(Symbols.fit_screen_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byIcon(Symbols.add_rounded).last);
    await tester.pump();
    final interrupted = controller.value.clone();
    final zoomTarget = (interrupted.entry(0, 0) * 1.2).clamp(.25, 1.8);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.value.entry(0, 0), greaterThan(interrupted.entry(0, 0)));
    expect(controller.value.entry(0, 0), lessThan(zoomTarget));
    await tester.pumpAndSettle();
    expect(controller.value.entry(0, 0), closeTo(zoomTarget, .001));
    await tester.pumpWidget(app(disableAnimations: true));
    await tester.pumpAndSettle();
    controller.value = before;
    await tester.pump();
    await tester.tap(find.byIcon(Symbols.fit_screen_rounded));
    await tester.pump();
    for (var i = 0; i < 16; i++) {
      expect(controller.value.storage[i], closeTo(target.storage[i], .001));
    }
    await finish(tester);
  });

  testWidgets(
    'node context menu stays unscaled and deletes the clicked subtree only',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: 'Keep this task',
          task: 'Complete task.',
        ),
      ))!;
      final second = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: 'Context target',
          task: 'Complete task.',
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      String? copiedId;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedId = (call.arguments as Map)['text'] as String;
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
      final controller = tester
          .widget<InteractiveViewer>(
            find.byKey(const ValueKey('task-topology-canvas')),
          )
          .transformationController!;
      final pos = tester.widget<Positioned>(
        find.byKey(ValueKey('topology-position-${second.id}')),
      );
      controller.value =
          Matrix4.translationValues(
            800 - pos.left! * .5,
            450 - pos.top! * .5,
            0,
          ) *
          Matrix4.diagonal3Values(.5, .5, 1);
      await tester.pump();
      final clickPosition = tester.getCenter(
        find.byKey(ValueKey('topology-node-${second.id}')),
      );
      await tester.tap(
        find.byKey(ValueKey('topology-node-${second.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final item = find.byKey(const ValueKey('topology-context-delete'));
      final rect = tester.getRect(item);
      final firstItemRect = tester.getRect(
        find.byKey(const ValueKey('topology-context-open')),
      );
      expect(firstItemRect.left, closeTo(clickPosition.dx + 5, 1));
      expect(firstItemRect.top, closeTo(clickPosition.dy - 8 + 5, 1));
      final duplicateRect = tester.getRect(
        find.byKey(const ValueKey('topology-context-duplicate')),
      );
      final copyIdRect = tester.getRect(
        find.byKey(const ValueKey('topology-context-copy-id')),
      );
      expect(copyIdRect.top - duplicateRect.bottom, closeTo(4, 1));
      expect(rect.width, greaterThan(100));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1180));
      expect(rect.bottom, lessThanOrEqualTo(850));
      expect(find.byKey(const ValueKey('topology-context-stop')), findsNothing);
      await captureOverlay(tester, 'lilygobox-task-context-menu');
      workspaces.select(first.id);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('topology-context-copy-id')));
      await tester.pumpAndSettle();
      expect(copiedId, second.id);
      expect(
        find.byKey(const ValueKey('topology-context-copy-id')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(ValueKey('topology-node-${second.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      workspaces.select(first.id);
      await tester.pump();
      await tester.tap(item);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-topology-delete')));
      await tester.pumpAndSettle();
      expect(workspaces.find(second.id), isNull);
      expect(workspaces.find(first.id), isNotNull);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('canvas background uses shared selection menu and follows zoom', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    theme.setTheme(ThemeType.light);
    await tester.runAsync(
      () => workspaces.createPrimary(title: '画布示例', task: '检查任务。'),
    );
    await tester.pumpWidget(app());
    await tick(tester);
    expect(workspaces.canvasStyle, AiTaskCanvasStyle.dots);
    final control = find.byKey(const ValueKey('topology-canvas-background'));
    final icons = <IconData>{};
    for (final expected in [
      AiTaskCanvasStyle.grid,
      AiTaskCanvasStyle.plain,
      AiTaskCanvasStyle.dots,
    ]) {
      icons.add(
        tester
            .widget<Icon>(
              find.descendant(of: control, matching: find.byType(Icon)),
            )
            .icon!,
      );
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(workspaces.canvasStyle, expected);
      expect(
        find.byKey(const ValueKey('topology-canvas-style-grid')),
        findsNothing,
      );
    }
    expect(icons, hasLength(3));
    for (final style in [
      AiTaskCanvasStyle.grid,
      AiTaskCanvasStyle.plain,
      AiTaskCanvasStyle.dots,
    ]) {
      await tester.tap(
        find.byKey(const ValueKey('topology-canvas-background')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('topology-canvas-style-${style.name}')),
      );
      await tick(tester);
      expect(workspaces.canvasStyle, style);
      expect(
        find.byKey(ValueKey('topology-canvas-style-${style.name}')),
        findsNothing,
      );
      await captureOverlay(tester, 'lilygobox-task-canvas-${style.name}');
    }
    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('task-topology-canvas')),
    );
    viewer.transformationController!.value = Matrix4.diagonal3Values(.5, .5, 1);
    await tester.pump();
    final paint = tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byKey(const ValueKey('task-topology-canvas')),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    final dynamic painter = paint.painter;
    expect(painter.scale, .5);
    await finish(tester);
  });

  testWidgets(
    'deleting a root promotes its latest long task and retains its conversation draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: 'Original root',
          task: 'Coordinate task.',
        ),
      ))!;
      final older = (await tester.runAsync(
        () => workspaces.create(
          title: 'Older long task',
          task: 'Complete task.',
          parentId: root.id,
        ),
      ))!;
      final latest = (await tester.runAsync(
        () => workspaces.create(
          title: 'Latest long task',
          task: 'Complete task.',
          parentId: root.id,
        ),
      ))!;
      final nested = (await tester.runAsync(
        () => workspaces.create(
          title: 'Nested long task',
          task: 'Complete task.',
          parentId: older.id,
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      await tester.tap(find.byKey(ValueKey('topology-open-${latest.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-message-input')),
        'Retain promoted task draft',
      );
      final draftController = tester
          .widget<TextField>(find.byKey(const ValueKey('ai-message-input')))
          .controller!;
      expect(draftController.text, 'Retain promoted task draft');
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('topology-node-${root.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-context-delete')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          AppLocalizations.of(
            tester.element(find.byType(TaskTopologyPage)),
          ).aiTopologyRootPromotionNotice(latest.title),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('confirm-topology-delete')));
      await tick(tester);
      expect(
        draftController.text,
        'Retain promoted task draft',
        reason: 'original controller after deletion',
      );
      expect(workspaces.find(root.id), isNull);
      expect(workspaces.find(latest.id)!.kind, AiWorkspaceKind.primary);
      expect(workspaces.find(older.id)!.parentId, latest.id);
      expect(workspaces.find(nested.id)!.parentId, older.id);
      Positioned position(String id) => tester.widget<Positioned>(
        find.byKey(ValueKey('topology-position-$id')),
      );
      expect(position(latest.id).left, lessThan(position(older.id).left!));
      expect(position(older.id).left, lessThan(position(nested.id).left!));
      await tester.tap(find.byKey(ValueKey('topology-open-${latest.id}')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ai-message-input')))
            .controller,
        same(draftController),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ai-message-input')))
            .controller!
            .text,
        'Retain promoted task draft',
      );
      await finish(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'root deletion reconfirms when the task receiving the root role changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Root', task: 'one'),
      ))!;
      final first = (await tester.runAsync(
        () => workspaces.create(
          title: 'First candidate',
          task: 'two',
          parentId: root.id,
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      await tester.tap(
        find.byKey(ValueKey('topology-node-${root.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-context-delete')));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TaskTopologyPage)),
      );
      expect(
        find.textContaining(l10n.aiTopologyRootPromotionNotice(first.title)),
        findsOneWidget,
      );
      final latest = (await tester.runAsync(
        () => workspaces.create(
          title: 'New candidate',
          task: 'three',
          parentId: root.id,
          startImmediately: false,
        ),
      ))!;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-topology-delete')));
      await tester.pumpAndSettle();
      expect(workspaces.find(root.id), same(root));
      expect(latest.kind, AiWorkspaceKind.permanent);
      expect(
        find.textContaining(l10n.aiTopologyRootPromotionNotice(latest.title)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('cancel-topology-delete')));
      await tester.pumpAndSettle();
      expect(workspaces.sessions, hasLength(3));
      expect(first.kind, AiWorkspaceKind.permanent);
      expect(latest.kind, AiWorkspaceKind.permanent);
      expect(first.parentId, root.id);
      expect(latest.parentId, root.id);
      await finish(tester);
    },
  );

  testWidgets(
    'last of 25 primary nodes remains inside the scene and clickable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (var index = 0; index < 25; index++) {
        await tester.runAsync(
          () => workspaces.createPrimary(
            title: 'Task $index',
            task: 'Complete task $index.',
          ),
        );
      }
      await tester.pumpWidget(app());
      await tick(tester);
      final last = workspaces.sessions.last;
      final positioned = tester.widget<Positioned>(
        find.byKey(ValueKey('topology-position-${last.id}')),
      );
      final viewer = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey('task-topology-canvas')),
      );
      final scene = viewer.child as SizedBox;
      expect(scene.height, greaterThan(positioned.top! + positioned.height!));
      viewer.transformationController!.value = Matrix4.translationValues(
        180 - positioned.left!,
        180 - positioned.top!,
        0,
      );
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('topology-open-${last.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      expect(workspaces.selectedId, last.id);
      await finish(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty topology creates a primary task and opens its own conversation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topology-empty-create')),
        findsOneWidget,
      );
      expect(workspaces.sessions, isEmpty);
      await tester.tap(find.byKey(const ValueKey('topology-empty-create')));
      await tick(tester);
      expect(
        find.byKey(const ValueKey('topology-title-input')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('topology-title-input')),
        '项目检查',
      );
      await tester.enterText(
        find.byKey(const ValueKey('topology-task-input')),
        '检查项目结构并汇总结果。',
      );
      await tester.tap(find.byKey(const ValueKey('topology-model-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-reasoning-models')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-model-search')),
        'deepseek',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey(
            'ai-model-${scope.provider.services.first.id}-deepseek-flash',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-title-input')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-permissions-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-permission-mode-custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-permission-network')));
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('topology-title-input'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-create-confirm')));
      await tick(tester);
      expect(workspaces.sessions, hasLength(1));
      final session = workspaces.sessions.single;
      expect(session.kind, AiWorkspaceKind.primary);
      expect(session.model, 'deepseek-flash');
      expect(session.assistant.permissions.mode, AiApprovalMode.custom);
      expect(session.assistant.permissions.network, isFalse);
      expect(scope.provider.permissions.mode, AiApprovalMode.onRequest);
      expect(scope.provider.permissions.network, isTrue);
      expect(scope.provider.selectedModel, 'gpt-6.1-sol');
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('topology-node-${session.id}')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('topology-empty-create')), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('creation accepts an empty name but requires task content', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app());
    await tick(tester);
    await tester.tap(find.byKey(const ValueKey('topology-empty-create')));
    await tick(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(TaskTopologyPage)),
    );
    expect(find.text(l10n.aiTopologyNameOptional), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('topology-create-confirm')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.aiTopologyTaskContentRequired), findsOneWidget);
    expect(workspaces.sessions, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('topology-task-input')),
      'Inspect this project',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topology-create-confirm')));
    for (
      var attempt = 0;
      attempt < 10 && workspaces.sessions.isEmpty;
      attempt++
    ) {
      await tick(tester);
    }
    expect(workspaces.sessions, hasLength(1));
    expect(workspaces.sessions.single.title, isNotEmpty);
    expect(workspaces.sessions.single.task, 'Inspect this project');
    expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'root creation selects an actual model without inheritance and cancels independently',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final originalPermissions = scope.provider.permissions;
      final originalService = scope.provider.selectedService!.id;
      final originalModel = scope.provider.selectedModel;
      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) return;
        await tester.runAsync(() async {
          final image =
              await (overlayBoundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${Directory.systemTemp.path}/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      for (final type in ThemeType.values) {
        theme.setTheme(type);
        final narrow = type == ThemeType.light;
        await tester.binding.setSurfaceSize(
          narrow ? const Size(560, 850) : const Size(1180, 850),
        );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('topology-empty-create')));
        await tick(tester);
        await capture(
          'lilygobox-create-dialog-${type.name}-${narrow ? 'narrow' : 'wide'}',
        );
        final modelButton = find.byKey(const ValueKey('ai-model-selector'));
        final permissionButton = find.byKey(
          const ValueKey('ai-permissions-button'),
        );
        final modelSurface = tester.widget<MenuItemSurface>(modelButton);
        final permissionSurface = tester.widget<MenuItemSurface>(
          permissionButton,
        );
        expect(modelSurface.backgroundColor, permissionSurface.backgroundColor);
        final modelArrow = tester.widget<AnimatedRotation>(
          find.byKey(const ValueKey('ai-model-selector-arrow')),
        );
        final permissionArrow = tester.widget<AnimatedRotation>(
          find.byKey(const ValueKey('ai-permissions-button-arrow')),
        );
        expect(modelArrow.curve, permissionArrow.curve);
        expect(modelArrow.duration, permissionArrow.duration);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('ai-model-selector-arrow')),
            matching: find.byIcon(Symbols.expand_more_rounded),
          ),
          findsOneWidget,
        );

        expect(modelSurface.borderRadius, BorderRadius.circular(4));
        expect(permissionSurface.borderRadius, BorderRadius.circular(4));
        expect(
          tester.getSize(modelButton).height,
          tester.getSize(permissionButton).height,
        );
        expect(tester.getSize(modelButton).width, lessThan(300));
        expect(
          tester
              .widget<AnimatedRotation>(
                find.byKey(const ValueKey('ai-model-selector-arrow')),
              )
              .turns,
          -.25,
        );
        expect(
          tester
              .widget<AnimatedRotation>(
                find.byKey(const ValueKey('ai-permissions-button-arrow')),
              )
              .turns,
          -.25,
        );
        await tester.tap(find.byKey(const ValueKey('topology-model-select')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final modelTurn = tester
            .widget<RotationTransition>(
              find.descendant(
                of: find.byKey(const ValueKey('ai-model-selector-arrow')),
                matching: find.byType(RotationTransition),
              ),
            )
            .turns
            .value;
        final modelOpacity = tester
            .widget<FadeTransition>(
              find.byKey(const ValueKey('ai-model-menu-fade')),
            )
            .opacity
            .value;
        expect(modelOpacity, greaterThan(0));
        expect(modelOpacity, lessThan(1));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('ai-reasoning-panel')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('ai-reasoning-models')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('ai-model-list-panel')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('ai-reasoning-panel')), findsNothing);
        final modelBounds = tester.getRect(modelButton);
        final modelMenu = tester.getRect(
          find.byKey(const ValueKey('ai-model-menu-surface')),
        );
        expect(modelMenu.left, closeTo(modelBounds.left, .01));
        expect(modelMenu.top, closeTo(modelBounds.bottom + 8, .01));
        expect(
          tester
              .widget<AnimatedRotation>(
                find.byKey(const ValueKey('ai-model-selector-arrow')),
              )
              .turns,
          0,
        );
        await capture(
          'lilygobox-create-model-${type.name}-${narrow ? 'narrow' : 'wide'}',
        );
        await tester.enterText(
          find.byKey(const ValueKey('ai-model-search')),
          'deepseek',
        );
        await tester.pumpAndSettle();
        expect(find.text('Local model'), findsOneWidget);
        expect(
          find.byKey(ValueKey('ai-model-$originalService-gpt-6.1-sol')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(ValueKey('ai-model-$originalService-deepseek-flash')),
        );
        await tester.pumpAndSettle();
        expect(scope.provider.selectedModel, originalModel);
        await tester.tap(find.byKey(const ValueKey('topology-title-input')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('topology-model-select')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ai-model-inherit')), findsNothing);
        if (find
            .byKey(const ValueKey('ai-reasoning-models'))
            .evaluate()
            .isNotEmpty) {
          await tester.tap(find.byKey(const ValueKey('ai-reasoning-models')));
          await tester.pumpAndSettle();
        }
        await tester.enterText(
          find.byKey(const ValueKey('ai-model-search')),
          '',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('ai-model-$originalService-$originalModel')),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: modelButton,
            matching: find.byIcon(Symbols.blur_on),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('topology-title-input')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ai-permissions-button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final permissionTurn = tester
            .widget<RotationTransition>(
              find.descendant(
                of: find.byKey(const ValueKey('ai-permissions-button-arrow')),
                matching: find.byType(RotationTransition),
              ),
            )
            .turns
            .value;
        expect(permissionTurn, closeTo(modelTurn, .001));
        final permissionFade = tester.widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('ai-permissions-menu-surface')),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        expect(permissionFade.opacity.value, closeTo(modelOpacity, .001));
        await tester.pumpAndSettle();
        final permissionBounds = tester.getRect(permissionButton);
        final permissionMenu = tester.getRect(
          find.byKey(const ValueKey('ai-permissions-menu-surface')),
        );
        expect(permissionMenu.left, closeTo(permissionBounds.left, .01));
        expect(permissionMenu.top, closeTo(permissionBounds.bottom + 8, .01));
        expect(
          tester
              .widget<AnimatedRotation>(
                find.byKey(const ValueKey('ai-permissions-button-arrow')),
              )
              .turns,
          0,
        );
        await tester.tap(
          find.byKey(const ValueKey('ai-permission-mode-custom')),
        );
        await tester.pumpAndSettle();
        await capture(
          'lilygobox-create-permissions-${type.name}-${narrow ? 'narrow' : 'wide'}',
        );
        await tester.tap(find.byKey(const ValueKey('ai-permission-network')));
        await tester.pumpAndSettle();
        expect(scope.provider.permissions, same(originalPermissions));
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('topology-title-input'))),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(
            AppLocalizations.of(
              tester.element(find.byType(TaskTopologyPage)),
            ).settingsCancel,
          ),
        );
        await tester.pumpAndSettle();
        expect(workspaces.sessions, isEmpty);
        expect(scope.provider.selectedService!.id, originalService);
        expect(scope.provider.selectedModel, originalModel);
        expect(scope.provider.permissions, same(originalPermissions));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('canvas keyboard shortcuts dismiss a card context menu', (
    tester,
  ) async {
    final agent = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Menu', task: 'Work'),
    ))!;
    await tester.pumpWidget(app());
    await tick(tester);
    await tester.tap(
      find.byKey(ValueKey('topology-node-${agent.id}')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topology-context-open')), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topology-context-open')), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'creation uses chat strength panel and keeps parent configuration isolated',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tick(tester);
      final original = scope.provider.reasoningEffort;
      await tester.tap(find.byKey(const ValueKey('topology-empty-create')));
      await tick(tester);
      await tester.enterText(
        find.byKey(const ValueKey('topology-title-input')),
        'Custom effort',
      );
      await tester.enterText(
        find.byKey(const ValueKey('topology-task-input')),
        'Check effort',
      );
      await tester.tap(find.byKey(const ValueKey('topology-model-select')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-reasoning-panel')), findsOneWidget);
      final slider = find.byType(Slider);
      final bounds = tester.getRect(slider);
      await tester.tapAt(Offset(bounds.right - 2, bounds.center.dy));
      await tester.pumpAndSettle();
      expect(scope.provider.reasoningEffort, original);
      await tester.tap(find.byKey(const ValueKey('topology-title-input')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-create-confirm')));
      await tick(tester);
      expect(
        workspaces.sessions.single.assistant.reasoningEffort,
        AiReasoningCapabilities.forModel('gpt-6.1-sol').levels.last,
      );
      expect(scope.provider.reasoningEffort, original);
      await finish(tester);
    },
  );

  testWidgets(
    'selected child can send while three other children are running',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final primary = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: 'Primary',
          task: 'Coordinate this task.',
        ),
      ))!;
      final idle = (await tester.runAsync(
        () => workspaces.create(
          title: 'Idle child',
          task: 'Finish this task.',
          parentId: primary.id,
        ),
      ))!;
      await tester.pumpWidget(app());
      for (var attempt = 0; attempt < 30 && idle.assistant.busy; attempt++) {
        await tick(tester);
      }
      expect(idle.assistant.busy, isFalse);
      await tester.tap(find.byKey(ValueKey('topology-open-${idle.id}')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ai-message-input'));
      await tester.enterText(input, 'Retain this pending draft');
      final originalCount = idle.assistant.messages.length;
      for (var index = 0; index < 3; index++) {
        final task = 'Hold task $index';
        requestGates[task] = Completer<void>();
        await tester.runAsync(
          () => workspaces.create(
            title: 'Busy $index',
            task: task,
            parentId: primary.id,
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(workspaces.runningCount, 3);
      expect(
        tester
            .widget<TitleBarIconButton>(
              find.byKey(const ValueKey('ai-send-button')),
            )
            .onPressed,
        isNotNull,
      );
      requestGates['Retain this pending draft'] = Completer<void>();
      await tester.tap(input);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(workspaces.runningCount, 4);
      expect(idle.assistant.busy, isTrue);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(idle.assistant.messages.length, greaterThan(originalCount));
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'selected task creates visible nested children with recursive layout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final primary = (await tester.runAsync(
        () => workspaces.createPrimary(title: '产品开发', task: '协调项目。'),
      ))!;
      final child = (await tester.runAsync(
        () => workspaces.create(
          title: '界面设计',
          task: '设计界面。',
          parentId: primary.id,
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      await tester.tap(find.byKey(ValueKey('topology-open-${child.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-new-child')));
      await tick(tester);
      await tester.tap(find.byKey(const ValueKey('topology-model-select')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-model-inherit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-model-inherit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('topology-title-input')),
        '控件设计',
      );
      await tester.enterText(
        find.byKey(const ValueKey('topology-task-input')),
        '设计公共控件。',
      );
      await tester.tap(find.byKey(const ValueKey('topology-create-confirm')));
      await tick(tester);
      expect(workspaces.sessions, hasLength(3));
      final nested = workspaces.sessions.last;
      expect(nested.parentId, child.id);
      expect(nested.kind, AiWorkspaceKind.permanent);
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      Positioned position(String id) => tester.widget<Positioned>(
        find.byKey(ValueKey('topology-position-$id')),
      );
      expect(position(child.id).left, greaterThan(position(primary.id).left!));
      expect(position(nested.id).left, greaterThan(position(child.id).left!));
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final customPaint = tester.widget<CustomPaint>(
        find.descendant(of: canvas, matching: find.byType(CustomPaint)).first,
      );
      final dynamic painter = customPaint.painter;
      expect(
        (painter.sessions as List<AiAgentWorkspace>)
            .singleWhere((item) => item.id == nested.id)
            .parentId,
        child.id,
      );
      final positions = painter.positions as Map<String, Offset>;
      expect(positions[nested.id]!.dx, position(nested.id).left);
      await tester.tap(find.byIcon(Symbols.fit_screen_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('topology-open-${nested.id}')));
      await tester.pumpAndSettle();
      expect(workspaces.selectedId, nested.id);
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      final sibling = (await tester.runAsync(
        () =>
            workspaces.create(title: '交互设计', task: '设计交互。', parentId: child.id),
      ))!;
      await tick(tester);
      expect(position(sibling.id).left, position(nested.id).left);
      expect(
        position(sibling.id).top! - position(nested.id).top!,
        greaterThan(position(nested.id).height!),
      );
      final temporary = (await tester.runAsync(
        () => workspaces.create(
          title: '检查控件',
          task: '检查布局。',
          parentId: child.id,
          kind: AiWorkspaceKind.permanent,
        ),
      ))!;
      await tick(tester);
      expect(
        find.byKey(ValueKey('topology-node-${temporary.id}')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey('topology-open-${child.id}')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('topology-temporary-${temporary.id}')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      await finish(tester);
      if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
        for (final type in ThemeType.values) {
          theme.setTheme(type);
          for (final narrow in [false, true]) {
            await tester.binding.setSurfaceSize(
              narrow ? const Size(560, 850) : const Size(1180, 850),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '${Directory.systemTemp.path}/lilygobox-task-tree-${type.name}-${narrow ? 'narrow' : 'wide'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
      if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
        await tester.binding.setSurfaceSize(const Size(1180, 850));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(ValueKey('topology-node-${primary.id}')),
          const Offset(850, -300),
        );
        await tester.pumpAndSettle();
        await captureOverlay(tester, 'lilygobox-task-tree-repositioned');
        await tick(tester);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nodes drag and all spawned children have editable chats while retaining drafts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final primary = (await tester.runAsync(
        () => workspaces.createPrimary(title: '产品开发', task: '协调本次产品开发任务。'),
      ))!;
      final permanent = (await tester.runAsync(
        () => workspaces.create(
          title: '界面设计',
          task: '研究界面布局与交互。',
          parentId: primary.id,
          kind: AiWorkspaceKind.permanent,
        ),
      ))!;
      await tick(tester);
      nextTool = {
        'id': 'spawn-visible-child-test',
        'type': 'function',
        'function': {
          'name': 'spawn_agent',
          'arguments': jsonEncode({'title': '检查配置文件', 'task': '检查配置文件的字段。'}),
        },
      };
      await tester.runAsync(() => primary.assistant.sendMessage('创建检查任务'));
      await tick(tester);
      expect(
        workspaces
            .childrenOf(primary.id)
            .where((task) => task.title == '检查配置文件'),
        isNotEmpty,
        reason:
            'error=${primary.assistant.error}, messages=${primary.assistant.messages.map((m) => m.content).toList()}, steps=${primary.assistant.messages.expand((m) => m.processingSteps).map((step) => step.output).toList()}',
      );
      final temporary = workspaces
          .childrenOf(primary.id)
          .singleWhere((task) => task.title == '检查配置文件');
      await tester.pumpWidget(app());
      await tick(tester);
      final primaryNode = find.byKey(ValueKey('topology-node-${primary.id}'));
      final before = tester.getCenter(primaryNode);
      await tester.drag(primaryNode, const Offset(110, 45));
      await tester.pumpAndSettle();
      expect(
        (tester.getCenter(primaryNode) - before).distance,
        greaterThan(20),
      );
      await tester.tap(find.byKey(ValueKey('topology-open-${primary.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-message-input')),
        '主智能体草稿',
      );
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => permanent.assistant.receiveAgentMessage(
          sourceId: primary.id,
          sourceTitle: primary.title,
          content: 'Review this task.',
        ),
      );
      await tester.tap(find.byKey(ValueKey('topology-open-${permanent.id}')));
      await tester.pumpAndSettle();
      expect(find.text('来自智能体：产品开发'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('来自智能体：产品开发')).style!.color,
        theme.themeData.textColorTertiary,
      );
      await tester.enterText(
        find.byKey(const ValueKey('ai-message-input')),
        '长期任务草稿',
      );
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('topology-node-${temporary.id}')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey('topology-open-${primary.id}')));
      await tester.pumpAndSettle();
      final parentResponse = primary.assistant.messages.singleWhere(
        (message) => message.processEvents.any(
          (event) => event.action?.name == 'spawn_agent',
        ),
      );
      await tester.tap(
        find.byKey(ValueKey('ai-response-details-${parentResponse.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('topology-temporary-${temporary.id}')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ai-task-process-details')),
        findsNothing,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ai-message-input')))
            .controller!
            .text,
        '主智能体草稿',
      );
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('topology-open-${temporary.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('ai-message-input')),
        '子智能体草稿',
      );
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('topology-open-${permanent.id}')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ai-message-input')))
            .controller!
            .text,
        '长期任务草稿',
      );
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tester.pumpAndSettle();
      await finish(tester);
      if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
        for (final type in ThemeType.values) {
          theme.setTheme(type);
          for (final narrow in [false, true]) {
            await tester.binding.setSurfaceSize(
              narrow ? const Size(560, 850) : const Size(1180, 850),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '${Directory.systemTemp.path}/lilygobox-task-topology-${type.name}-${narrow ? 'narrow' : 'wide'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
            expect(tester.takeException(), isNull);
          }
        }
      }
      expect(tester.takeException(), isNull);
    },
  );
}
