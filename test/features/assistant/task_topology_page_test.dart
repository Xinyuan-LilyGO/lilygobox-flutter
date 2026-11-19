/*
 * @Description: 验证多层任务树创建、拖动、独立会话与临时任务只读行为。
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/core/widgets/card_shadow.dart';
import 'package:lilygobox/core/widgets/interaction_decoration.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/core/widgets/popup_menu_surface.dart';
import 'package:lilygobox/core/widgets/settings/select.dart';
import 'package:lilygobox/core/widgets/tilt_card.dart';
import 'package:lilygobox/core/widgets/title_bar_icon_button.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';
import 'package:lilygobox/features/assistant/domain/task_canvas_style.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/assistant/presentation/pages/task_topology_page.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/agent_transfer_error.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/storage_content.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_canvas_background.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_connection.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_connection_layer.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_overview_card.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

class _RasterFailure implements ui.PictureRasterizationException {
  @override
  String get message => 'Test texture failure';
  @override
  StackTrace? get stack => null;
}

class _TextureFailureCanvas extends TestRecordingCanvas {
  int attempts = 0;

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    attempts++;
    throw _RasterFailure();
  }
}

class _GatedWorkflowStorage extends AgentStorage {
  _GatedWorkflowStorage() : super(path: ':memory:');
  final workflow = Completer<Object?>();

  @override
  Future<Object?> request(
    String operation, [
    Map<String, Object?> args = const {},
  ]) async => operation == 'readWorkflowData' ? workflow.future : null;
}

class _TitleCountingScaler extends TextScaler {
  const _TitleCountingScaler(this.onTitleMeasure);

  final VoidCallback onTitleMeasure;

  @override
  double get textScaleFactor => 1;

  @override
  double scale(double fontSize) {
    if (fontSize == 13) onTitleMeasure();
    return fontSize;
  }
}

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
      final chineseBold = await File('C:/Windows/Fonts/msyhbd.ttc')
          .readAsBytes();
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
    TextScaler? textScaler,
    AiWorkspaceProvider? restored,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<AppShellProvider>.value(value: shell),
      ChangeNotifierProvider<AppNavigationProvider>.value(value: navigation),
      ChangeNotifierProvider<AiAssistantProvider>.value(
        value: restored?.main ?? scope.provider,
      ),
      ChangeNotifierProvider<AiWorkspaceProvider>.value(
        value: restored ?? workspaces,
      ),
    ],
    child: RepaintBoundary(
      key: overlayBoundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            textScaler: textScaler ?? TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        locale: const Locale('zh'),
        theme: ThemeData(
          fontFamily: const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')
              ? 'WorkspaceChinese'
              : null,
        ),
        localizationsDelegates: appLocalizationDelegates,
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
      await File('${Directory.systemTemp.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
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

  for (final outcome in ['empty', 'saved', 'invalid']) {
    testWidgets('canvas waits for storage before showing $outcome workflow', (
      tester,
    ) async {
      final storage = _GatedWorkflowStorage();
      addTearDown(storage.close);
      final restoreScope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        storage: storage,
      );
      final restored = AiWorkspaceProvider(restoreScope.provider);
      try {
        await tester.pumpWidget(app(restored: restored));
        await tester.pump();
        final emptyCard = find.byKey(const ValueKey('topology-empty-create'));
        expect(find.text('正在加载智能体…'), findsOneWidget);
        expect(emptyCard, findsNothing);
        storage.workflow.complete(switch (outcome) {
          'empty' => null,
          'invalid' => {'version': -1},
          _ => {
            'version': 1,
            'connections': [],
            'sessions': [
              {
                'id': '10000-0',
                'title': 'Saved card',
                'task': '',
                'kind': 'primary',
                'conversation': {
                  'serviceId': '',
                  'model': '',
                  'messages': [],
                  'history': [],
                },
              },
            ],
          },
        });
        await tester.pumpAndSettle();
        expect(find.text('正在加载智能体…'), findsNothing);
        expect(emptyCard, outcome == 'empty' ? findsOneWidget : findsNothing);
        expect(
          find.text('未能读取已保存的智能体。'),
          outcome == 'invalid' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('topology-node-10000-0')),
          outcome == 'saved' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        restored.dispose();
        restoreScope.dispose();
      }
    });
  }

  testWidgets('large cold canvas measures across frames with live card edits', (
    tester,
  ) async {
    const count = 1024;
    final storage = _GatedWorkflowStorage();
    addTearDown(storage.close);
    final restoreScope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      storage: storage,
    );
    final restored = (await tester.runAsync(() async {
      storage.workflow.complete({
        'version': 1,
        'connections': [],
        'canvas': {
          for (var index = 0; index < count; index++)
            '10000-$index': [(index % 32) * 350, (index ~/ 32) * 240],
        },
        'sessions': [
          for (var index = 0; index < count; index++)
            {
              'id': '10000-$index',
              'title': 'Saved card $index',
              'task': '',
              'kind': 'primary',
              'conversation': {
                'serviceId': '',
                'model': '',
                'messages': [],
                'history': [],
              },
            },
        ],
      });
      final provider = AiWorkspaceProvider(restoreScope.provider);
      await provider.initialized;
      return provider;
    }))!;
    final progress = find.byKey(const ValueKey('topology-loading-progress'));
    final canvas = find.byKey(const ValueKey('task-topology-canvas'));
    double measured() =>
        tester.widget<LinearProgressIndicator>(progress).value!;
    try {
      await tester.pumpWidget(
        TickerMode(enabled: false, child: app(restored: restored)),
      );
      await tester.pump();
      expect(measured(), 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(measured(), 0);
      await tester.pumpWidget(
        TickerMode(enabled: true, child: app(restored: restored)),
      );
      await tester.pump();
      final first = measured();
      expect(first, inExclusiveRange(0, 1));
      expect(canvas, findsNothing);
      await tester.pump();
      expect(measured(), greaterThan(first));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(app(restored: restored));
      await tester.pump();
      expect(progress, findsOneWidget);
      final title = List.filled(8, 'A longer card title').join(' ');
      restored.rename('10000-0', title);
      restored.remove('10000-1');
      await tester.pumpWidget(app(restored: restored, textScale: 1.25));
      expect(progress, findsOneWidget);
      for (
        var frame = 0;
        frame < 1026 && progress.evaluate().isNotEmpty;
        frame++
      ) {
        await tester.pump();
      }
      expect(progress, findsNothing);
      final view = tester.widget<InteractiveViewer>(canvas);
      final scale = view.transformationController!.value.entry(0, 0);
      expect(scale, lessThan(1));
      final firstFrameCards = find.byWidgetPredicate(
        (widget) =>
            widget is Positioned &&
            widget.key.toString().contains('topology-position-'),
      );
      final bounds = tester.getRect(canvas);
      expect(
        firstFrameCards.evaluate().any((element) {
          final card = find.byWidget(element.widget);
          return bounds.contains(tester.getCenter(card));
        }),
        isTrue,
      );
      final card = firstFrameCards.first;
      expect(
        tester.getRect(card).width / tester.getSize(card).width,
        closeTo(scale, .0001),
      );
      view.transformationController!.value = Matrix4.translationValues(
        60,
        80,
        0,
      );
      await tester.pumpAndSettle();
      final firstCard = find.byKey(const ValueKey('topology-node-10000-0'));
      expect(
        find.descendant(of: firstCard, matching: find.text(title)),
        findsOneWidget,
      );
      expect(tester.getSize(firstCard).height, greaterThan(180));
      expect(find.byKey(const ValueKey('topology-node-10000-1')), findsNothing);
      restored.rename('10000-0', 'Renamed after opening');
      await tester.pump();
      expect(progress, findsNothing);
      expect(canvas, findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      restored.dispose();
      restoreScope.dispose();
    }
  });

  testWidgets('unique agent IDs do not evict recurring title measurements', (
    tester,
  ) async {
    final storage = _GatedWorkflowStorage();
    addTearDown(storage.close);
    final restoreScope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      storage: storage,
    );
    final restored = AiWorkspaceProvider(restoreScope.provider);
    var titleScaleCalls = 0;
    final scaler = _TitleCountingScaler(() => titleScaleCalls++);
    try {
      const count = 1024;
      await tester.pumpWidget(app(restored: restored, textScaler: scaler));
      storage.workflow.complete({
        'version': 1,
        'sessions': [
          for (var index = 0; index < count; index++)
            {
              'id': '1000-$index',
              'title': '画布 👩‍💻 ${index % 256}',
              'task': '',
              'kind': 'primary',
              'conversation': {
                'serviceId': '',
                'model': '',
                'messages': [],
                'history': [],
              },
            },
        ],
        'connections': [],
        'canvas': {
          for (var index = 0; index < count; index++)
            '1000-$index': [
              index * 1500 + (index < count ~/ 2 ? 0 : 4000000),
              100,
            ],
        },
      });
      await tester.pumpAndSettle();
      expect(restored.sessions, hasLength(count));
      expect(
        find.byKey(const ValueKey('task-topology-canvas')),
        findsOneWidget,
      );
      expect(titleScaleCalls, lessThan(1500));
      final viewport = tester.getRect(
        find.byKey(const ValueKey('task-topology-canvas')),
      );
      final firstCard = find.byKey(const ValueKey('topology-position-1000-0'));
      expect(viewport.contains(tester.getCenter(firstCard)), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      restored.dispose();
      restoreScope.dispose();
    }
  });

  testWidgets('creation without a model service asks before opening settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      for (final service in scope.provider.services.toList()) {
        await scope.provider.removeService(service.id);
      }
    });
    await tester.pumpWidget(app());
    await tick(tester);
    await tester.tap(find.byKey(const ValueKey('topology-empty-create')));
    await tick(tester);
    expect(find.text('请先配置模型服务'), findsOneWidget);
    expect(navigation.currentPage, AppPage.home);
    expect(find.byKey(const ValueKey('topology-create-confirm')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('cancel-topology-model-service-required')),
    );
    await tick(tester);
    expect(find.text('请先配置模型服务'), findsNothing);
    expect(navigation.currentPage, AppPage.home);
    await tester.tap(find.byKey(const ValueKey('topology-empty-create')));
    await tick(tester);
    await tester.tap(
      find.byKey(const ValueKey('confirm-topology-model-service-required')),
    );
    await tick(tester);
    expect(navigation.currentPage, AppPage.settings);
    expect(navigation.settingsSection, AppSettingsSection.aiServices);
    expect(tester.takeException(), isNull);
  });

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

  void expectPortWithoutOpacityLayers(WidgetTester tester, Finder port) {
    final opacityLayers = <OpacityLayer>[];
    var visitedRenderObjects = 0;
    void visit(RenderObject renderObject) {
      visitedRenderObjects++;
      if (renderObject.debugLayer case final OpacityLayer layer) {
        opacityLayers.add(layer);
      }
      renderObject.visitChildren(visit);
    }

    visit(tester.renderObject(port));
    expect(visitedRenderObjects, greaterThan(1));
    expect(
      opacityLayers,
      isEmpty,
      reason: 'Connection port fades must paint without offscreen opacity',
    );
  }

  testWidgets('ports fade on selection and hover without opacity layers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(
      () => workspaces.create(
        title: 'Port fade',
        task: 'Wait for instructions',
        kind: AiWorkspaceKind.primary,
        startImmediately: false,
      ),
    ))!;
    final node = find.byKey(ValueKey('topology-node-${root.id}'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    const blank = Offset(20, 200);
    await mouse.addPointer(location: blank);

    void expectPortPaint(Matcher opacityMatcher) {
      for (final side in ['in', 'out', 'top', 'bottom']) {
        final port = find.byKey(ValueKey('topology-port-$side-${root.id}'));
        final visual = find.descendant(
          of: port,
          matching: find.byType(DecoratedBox),
        );
        final decoration =
            tester.renderObject<RenderDecoratedBox>(visual).decoration
                as BoxDecoration;
        final color = decoration.color!;
        final opacity = color.a / theme.themeData.primary.a;
        expect(opacity, opacityMatcher, reason: '$side connection port');
        expect(
          color.withValues(alpha: 1),
          theme.themeData.primary.withValues(alpha: 1),
        );
        final border = decoration.border! as Border;
        expect(
          border.top.color.a,
          closeTo(theme.themeData.basePrimary.a * opacity, .001),
        );
        expect(
          border.top.color.withValues(alpha: 1),
          theme.themeData.basePrimary.withValues(alpha: 1),
        );
        expect(border.top.width, 1.5);
        expect(decoration.shape, BoxShape.circle);
        expect(tester.getSize(visual), const Size(9, 9));
        expect(tester.getSize(port), const Size(24, 24));
        expectPortWithoutOpacityLayers(tester, port);
      }
    }

    for (final type in [ThemeType.light, ThemeType.dark]) {
      theme.setTheme(type);
      await tester.pumpWidget(app());
      await tick(tester);
      expect(selected(tester, root.id), isFalse);
      expectPortPaint(closeTo(.16, .001));

      await tester.tap(node);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(selected(tester, root.id), isTrue);
      expectPortPaint(closeTo(.58, .01));
      await tester.pump(const Duration(milliseconds: 75));
      expectPortPaint(closeTo(1, .001));

      await tester.tapAt(blank);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(selected(tester, root.id), isFalse);
      expectPortPaint(closeTo(.58, .01));
      await tester.pump(const Duration(milliseconds: 75));
      expectPortPaint(closeTo(.16, .001));

      await mouse.moveTo(tester.getCenter(node));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(selected(tester, root.id), isFalse);
      expectPortPaint(closeTo(.58, .01));
      await tester.pump(const Duration(milliseconds: 75));
      expectPortPaint(closeTo(1, .001));

      await mouse.moveTo(blank);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expectPortPaint(closeTo(.58, .01));
      await tester.pump(const Duration(milliseconds: 75));
      expectPortPaint(closeTo(.16, .001));
    }
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('rebuilding independent cards keeps agent lookups linear', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final countedWorkspaces = (await tester.runAsync(() async {
      await workspaces.initialized;
      workspaces.dispose();
      final replacement = _LookupCountingWorkspaceProvider(scope.provider);
      workspaces = replacement;
      await replacement.initialized;
      return replacement;
    }))!;
    final lookupCounts = <int>[];
    for (final cardCount in [20, 40]) {
      await tester.runAsync(() async {
        for (
          var index = countedWorkspaces.sessions.length;
          index < cardCount;
          index++
        ) {
          await countedWorkspaces.create(
            title: 'Independent $index',
            task: 'Wait for instructions',
            kind: AiWorkspaceKind.primary,
            startImmediately: false,
          );
        }
      });
      await tester.pumpWidget(app());
      await tick(tester);
      final firstAgent = countedWorkspaces.sessions.first;
      final updatedTitle = 'Updated with $cardCount cards';
      countedWorkspaces.rename(firstAgent.id, updatedTitle);
      countedWorkspaces.findCalls = 0;
      await tester.pump();
      final lookups = countedWorkspaces.findCalls;
      expect(
        tester
            .widget<Text>(
              find.byKey(ValueKey('topology-title-${firstAgent.id}')),
            )
            .data,
        updatedTitle,
      );
      expect(lookups, greaterThan(0));
      expect(
        lookups,
        lessThanOrEqualTo(cardCount * 16),
        reason: 'A card rebuild must not scan all agents for every card menu',
      );
      lookupCounts.add(lookups);

      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final transform = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final blank = tester.getTopLeft(canvas) + const Offset(4, 4);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: blank);
      await tester.tapAt(blank);
      await tester.pumpAndSettle();
      expect(
        countedWorkspaces.sessions.any(
          (agent) => tester
              .getRect(find.byKey(ValueKey('topology-node-${agent.id}')))
              .inflate(12)
              .contains(blank),
        ),
        isFalse,
      );

      void scroll(Offset delta) {
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: blank,
            scrollDelta: delta,
            kind: PointerDeviceKind.mouse,
          ),
        );
      }

      MenuAnchor cardMenu(String id) => tester.widget<MenuAnchor>(
        find
            .ancestor(
              of: find.byKey(ValueKey('topology-node-$id')),
              matching: find.byType(MenuAnchor),
            )
            .first,
      );

      Map<String, MenuAnchor> cardMenus() => {
        for (final agent in countedWorkspaces.sessions)
          agent.id: cardMenu(agent.id),
      };

      void expectMenusReused(Map<String, MenuAnchor> before, String motion) {
        for (final entry in before.entries) {
          expect(
            cardMenu(entry.key),
            same(entry.value),
            reason: '$motion must reuse every existing card menu',
          );
        }
      }

      scroll(const Offset(0, 1));
      await tester.pumpAndSettle();
      final beforePan = transform.value.clone();
      final menusBeforePan = cardMenus();
      scroll(const Offset(0, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expectMenusReused(menusBeforePan, 'Wheel panning');
      await tester.pumpAndSettle();
      expectMenusReused(menusBeforePan, 'Wheel panning');
      expect(transform.value.entry(1, 3), lessThan(beforePan.entry(1, 3)));
      expect(transform.value.entry(0, 0), beforePan.entry(0, 0));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      scroll(const Offset(0, -1));
      await tester.pumpAndSettle();
      final beforeZoom = transform.value.clone();
      final menusBeforeZoom = cardMenus();
      scroll(const Offset(0, -40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expectMenusReused(menusBeforeZoom, 'Ctrl wheel zoom');
      await tester.pumpAndSettle();
      expectMenusReused(menusBeforeZoom, 'Ctrl wheel zoom');
      expect(transform.value.entry(0, 0), greaterThan(beforeZoom.entry(0, 0)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final visibleAgent = countedWorkspaces.sessions.firstWhere(
        (agent) => tester
            .getRect(canvas)
            .deflate(80)
            .contains(
              tester.getCenter(
                find.byKey(ValueKey('topology-node-${agent.id}')),
              ),
            ),
      );
      final menusBeforeHover = cardMenus();
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(ValueKey('topology-node-${visibleAgent.id}')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expectMenusReused(menusBeforeHover, 'Card hover enter');
      await tester.pumpAndSettle();
      expectMenusReused(menusBeforeHover, 'Card hover enter');

      await mouse.moveTo(blank);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expectMenusReused(menusBeforeHover, 'Card hover exit');
      await tester.pumpAndSettle();
      expectMenusReused(menusBeforeHover, 'Card hover exit');
      await mouse.removePointer();
    }
    expect(
      lookupCounts.last,
      lessThanOrEqualTo(lookupCounts.first * 3),
      reason: 'Doubling independent cards must not quadruple agent lookups',
    );
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('page activity changes reuse the complete canvas graph', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      for (var index = 0; index < 8; index++) {
        await workspaces.create(
          title: 'Activity card $index',
          task: 'Wait for instructions',
          kind: AiWorkspaceKind.primary,
          startImmediately: false,
        );
      }
    });
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (context, enabled, child) =>
            TickerMode(enabled: enabled, child: child!),
        child: app(),
      ),
    );
    await tick(tester);
    MenuAnchor menu(String id) => tester.widget<MenuAnchor>(
      find
          .ancestor(
            of: find.byKey(ValueKey('topology-node-$id'), skipOffstage: false),
            matching: find.byType(MenuAnchor, skipOffstage: false),
          )
          .first,
    );
    final menus = {
      for (final agent in workspaces.sessions) agent.id: menu(agent.id),
    };
    void expectGraphReused() {
      for (final entry in menus.entries) {
        expect(menu(entry.key), same(entry.value));
      }
    }

    for (final enabled in [false, true]) {
      active.value = enabled;
      await tester.pumpAndSettle();
      expectGraphReused();
      expect(workspaces.activeConversationId, isNull);
    }
    final topologyContext = tester.element(find.byType(TaskTopologyPage));
    unawaited(
      showDialog<void>(
        context: topologyContext,
        builder: (context) => const Dialog(child: Text('Activity modal')),
      ),
    );
    await tester.pumpAndSettle();
    expectGraphReused();
    Navigator.of(topologyContext).pop();
    await tester.pumpAndSettle();
    expectGraphReused();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('covered conversations reject navigation without replaying it', (
    tester,
  ) async {
    final primary = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Activity main', task: 'Wait'),
    ))!;
    final child = (await tester.runAsync(
      () => workspaces.create(
        title: 'Activity child',
        task: 'Wait',
        parentId: primary.id,
      ),
    ))!;
    await tester.pumpWidget(app());
    await tick(tester);
    await tester.tap(find.byKey(ValueKey('topology-open-${primary.id}')));
    await tester.pumpAndSettle();
    expect(workspaces.activeConversationId, primary.id);
    final topologyContext = tester.element(find.byType(TaskTopologyPage));
    unawaited(
      showDialog<void>(
        context: topologyContext,
        builder: (context) => const Dialog(child: Text('Activity modal')),
      ),
    );
    await tester.pumpAndSettle();
    expect(workspaces.activeConversationId, isNull);
    final result = await tester.runAsync(
      () => primary.assistant.workspaceToolHandler!('open_agent', {
        'agent_id': child.id,
      }),
    );
    expect(result!['navigation_requested'], isFalse);
    Navigator.of(topologyContext).pop();
    await tester.pumpAndSettle();
    expect(workspaces.activeConversationId, primary.id);
    expect(find.byKey(ValueKey('topology-chat-${primary.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('topology-chat-${child.id}')), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
    'canvas transforms preserve agent semantics and the accessible open action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(1180, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final leader = (await tester.runAsync(
          () => workspaces.createPrimary(
            title: 'Accessible leader',
            task: 'Coordinate',
          ),
        ))!;
        final child = (await tester.runAsync(
          () => workspaces.create(
            title: 'Accessible child',
            task: 'Assist',
            parentId: leader.id,
            startImmediately: false,
          ),
        ))!;
        await tester.pumpWidget(app());
        await tick(tester);
        final leaderCard = find.byKey(ValueKey('topology-node-${leader.id}'));
        final childCard = find.byKey(ValueKey('topology-node-${child.id}'));
        await tester.tap(leaderCard);
        await tester.pumpAndSettle();
        final leaderSemanticsId = tester.getSemantics(leaderCard).id;
        final childSemanticsId = tester.getSemantics(childCard).id;
        final openChild = find.byKey(ValueKey('topology-open-${child.id}'));
        final openSemanticsId = tester.getSemantics(openChild).id;
        final canvas = tester.widget<InteractiveViewer>(
          find.byKey(const ValueKey('task-topology-canvas')),
        );
        final position = tester.widget<Positioned>(
          find.byKey(ValueKey('topology-position-${leader.id}')),
        );
        for (final scale in [.25, .7, 1.2]) {
          canvas.transformationController!.value =
              Matrix4.translationValues(
                100 - position.left! * scale,
                200 - position.top! * scale,
                0,
              ) *
              Matrix4.diagonal3Values(scale, scale, 1);
          await tester.pumpAndSettle();
          final leaderNode = tester.getSemantics(leaderCard);
          final childNode = tester.getSemantics(childCard);
          expect(leaderNode.id, leaderSemanticsId);
          expect(childNode.id, childSemanticsId);
          final leaderData = leaderNode.getSemanticsData();
          final childData = childNode.getSemanticsData();
          expect(leaderData.label, contains('Accessible leader'));
          expect(leaderData.label, contains('主智能体'));
          expect(childData.label, contains('Accessible child'));
          expect(childData.label, contains('子智能体'));
          expect(leaderData.flagsCollection.isSelected, ui.Tristate.isTrue);
          expect(childData.flagsCollection.isSelected, ui.Tristate.isFalse);
          expect(leaderData.flagsCollection.isHidden, isFalse);
          expect(childData.flagsCollection.isHidden, isFalse);
          final openNode = tester.getSemantics(openChild);
          expect(openNode.id, openSemanticsId);
          expect(
            openNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
        }
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          openSemanticsId,
          ui.SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
        expect(
          find.byKey(ValueKey('topology-conversation-task-id-${child.id}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await finish(tester);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'dense overview cards select, open menus, connect and expose an accessible open action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(1280, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final cards = (await tester.runAsync(
          () async => [
            for (var index = 0; index < 66; index++)
              await workspaces.create(
                title: 'Overview $index',
                task: 'Wait for instructions',
                kind: AiWorkspaceKind.primary,
                startImmediately: false,
              ),
          ],
        ))!;
        workspaces.updateCanvasPositions({
          for (final (index, card) in cards.indexed)
            card.id: [(index % 11) * 400.0, (index ~/ 11) * 300.0],
        });
        await tester.pumpWidget(app());
        await tick(tester);
        final view = tester.widget<InteractiveViewer>(
          find.byKey(const ValueKey('task-topology-canvas')),
        );
        view.transformationController!.value = Matrix4.translationValues(
          120,
          180,
          0,
        )..scaleByDouble(.3, .3, 1, 1);
        await tester.pumpAndSettle();
        final first = find.byKey(ValueKey('topology-node-${cards[0].id}'));
        final second = find.byKey(ValueKey('topology-node-${cards[1].id}'));
        expect(tester.widget(first), isA<TaskTopologyOverviewCard>());
        final failedSurface = _TextureFailureCanvas();
        for (final card in [first, second]) {
          final paint = tester.widget<CustomPaint>(
            find.descendant(of: card, matching: find.byType(CustomPaint)),
          );
          paint.painter!.paint(failedSurface, tester.getSize(card));
        }
        expect(
          failedSurface.attempts,
          !kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.windows &&
                  !ui.ImageFilter.isShaderFilterSupported
              ? 0
              : 1,
        );
        expect(
          failedSurface.invocations.where(
            (record) => record.invocation.memberName == #drawRRect,
          ),
          hasLength(2),
        );
        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(workspaces.selected?.id, cards[0].id);
        await tester.tap(second, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topology-context-copy-id')),
          findsOneWidget,
        );
        expect(workspaces.selected?.id, cards[1].id);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final start = tester.getRect(first).centerRight - const Offset(1, 0);
        final drag = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveTo(start + const Offset(30, 0));
        await tester.pump();
        await drag.moveTo(tester.getCenter(second));
        await drag.up();
        await tester.pumpAndSettle();
        expect(workspaces.isConnected(cards[0].id, cards[1].id), isTrue);
        final accessible = tester.getSemantics(second);
        expect(accessible.getSemanticsData().label, contains(cards[1].id));
        expect(accessible.getSemanticsData().label, contains('子智能体'));
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          accessible.id,
          ui.SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('topology-conversation-task-id-${cards[1].id}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await finish(tester);
      } finally {
        semantics.dispose();
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.android,
    }),
  );

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

  testWidgets('add child never falls back to an arbitrary active agent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Root', task: 'Coordinate'),
    ))!;
    await tester.runAsync(
      () => workspaces.create(
        title: 'Orphan',
        task: 'Wait',
        parentId: root.id,
        kind: AiWorkspaceKind.permanent,
        startImmediately: false,
      ),
    );
    await tester.pumpWidget(app());
    await tick(tester);
    await tester.tap(find.byKey(ValueKey('topology-node-${root.id}')));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('topology-new-child'));
    expect(tester.widget<MenuItemSurface>(button).onPressed, isNotNull);
    root.closed = true;
    workspaces.rename(root.id, 'Closed root');
    await tick(tester);
    expect(tester.widget<MenuItemSurface>(button).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('selected child can still receive another level of children', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Root', task: 'Coordinate'),
    ))!;
    final child = (await tester.runAsync(
      () => workspaces.create(
        title: 'Child',
        task: 'Delegate',
        parentId: root.id,
        startImmediately: false,
      ),
    ))!;
    await tester.pumpWidget(app());
    await tick(tester);
    await tester.tap(find.byKey(ValueKey('topology-node-${child.id}')));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('topology-new-child'));
    expect(tester.widget<MenuItemSurface>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tick(tester);
    expect(
      find.byKey(const ValueKey('topology-create-confirm')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    Navigator.of(
      tester.element(find.byKey(const ValueKey('topology-create-confirm'))),
    ).pop();
    await finish(tester);
  });

  testWidgets('main layout changes only its own workflow positions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final leader = (await tester.runAsync(
      () => workspaces.create(
        title: 'Leader',
        task: 'Coordinate',
        startImmediately: false,
      ),
    ))!;
    final child = (await tester.runAsync(
      () => workspaces.create(
        title: 'Child',
        task: 'Work',
        parentId: leader.id,
        startImmediately: false,
      ),
    ))!;
    final outside = (await tester.runAsync(
      () => workspaces.create(
        title: 'Outside',
        task: 'Unrelated',
        startImmediately: false,
      ),
    ))!;
    workspaces.updateCanvasPositions({
      leader.id: [180, 140],
      child.id: [260, 180],
      outside.id: [400, 700],
    });
    await tester.pumpWidget(app());
    await tick(tester);
    final outsideCard = find.byKey(ValueKey('topology-node-${outside.id}'));
    final outsideBefore = tester.getTopLeft(outsideCard);
    await expectLater(
      child.assistant.workspaceToolHandler!('layout_workflow', {}),
      throwsStateError,
    );
    final result = await leader.assistant.workspaceToolHandler!(
      'layout_workflow',
      {},
    );
    await tester.pumpAndSettle();
    expect(result['applied'], isTrue);
    expect(result['agent_ids'], unorderedEquals([leader.id, child.id]));
    expect(workspaces.canvasPositions[child.id], isNot([260, 180]));
    expect(workspaces.canvasPositions[outside.id], [400, 700]);
    expect(tester.getTopLeft(outsideCard), outsideBefore);
    expect(child.parentId, leader.id);
    await finish(tester);
  });

  for (final interval in [100, 400, 650]) {
    testWidgets('card double click tolerates desktop cadence $interval ms', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Double click', task: 'Wait'),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final node = find.byKey(ValueKey('topology-node-${root.id}'));
      final position = tester.getCenter(node);
      Future<void> click(
        int pointer,
        int milliseconds, {
        Offset drift = Offset.zero,
      }) async {
        await tester.sendEventToBinding(
          PointerDownEvent(
            pointer: pointer,
            position: position,
            timeStamp: Duration(milliseconds: milliseconds),
            kind: PointerDeviceKind.mouse,
            buttons: kPrimaryMouseButton,
          ),
        );
        if (drift != Offset.zero) {
          await tester.sendEventToBinding(
            PointerMoveEvent(
              pointer: pointer,
              position: position + drift,
              delta: drift,
              timeStamp: Duration(milliseconds: milliseconds + 10),
              kind: PointerDeviceKind.mouse,
              buttons: kPrimaryMouseButton,
            ),
          );
        }
        await tester.sendEventToBinding(
          PointerUpEvent(
            pointer: pointer,
            position: position + drift,
            timeStamp: Duration(milliseconds: milliseconds + 20),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pump();
      }

      await click(1, 1000);
      await click(2, 1000 + interval, drift: const Offset(4, 0));
      await tick(tester);
      expect(
        find.byKey(const ValueKey('ai-message-input')),
        interval <= 500 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }

  testWidgets('toolbar deletion skips confirmation and keeps a recycled copy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Project', task: 'Coordinate'),
    ))!;
    await tester.pumpWidget(app());
    await tick(tester);
    await tester.tap(find.byKey(ValueKey('topology-node-${root.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topology-delete')));
    await tick(tester);
    expect(find.byKey(const ValueKey('confirm-topology-delete')), findsNothing);
    expect(workspaces.find(root.id), isNull);
    expect(
      workspaces.recycledAgents.map((entry) => entry.id),
      contains(root.id),
    );
    await finish(tester);
  });

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

  testWidgets('dragging a card reuses all unchanged card contents', (
    tester,
  ) async {
    final tasks = (await tester.runAsync(() async {
      return [
        for (var index = 0; index < 20; index++)
          await workspaces.create(
            title: 'Task $index',
            task: 'Coordinate',
            kind: AiWorkspaceKind.primary,
            startImmediately: false,
          ),
      ];
    }))!;
    await tester.pumpWidget(app());
    await tick(tester);
    final viewport = tester.getRect(find.byType(TaskTopologyPage));
    final toolbar = tester.getRect(
      find.byKey(const ValueKey('topology-action-toolbar')),
    );
    final visibleTask = tasks.firstWhere(
      (task) =>
          !toolbar
              .inflate(8)
              .contains(
                tester.getCenter(
                  find.byKey(ValueKey('topology-node-${task.id}')),
                ),
              ) &&
          viewport
              .deflate(60)
              .contains(
                tester.getCenter(
                  find.byKey(ValueKey('topology-node-${task.id}')),
                ),
              ),
    );
    final node = find.byKey(ValueKey('topology-node-${visibleTask.id}'));
    await tester.tap(node);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final start = tester.getCenter(node);
    final drag = await tester.startGesture(start);
    await drag.moveTo(start + const Offset(25, 20));
    await tester.pumpAndSettle();
    await drag.moveTo(start + const Offset(50, 40));
    await tester.pumpAndSettle();
    final cards = {
      for (final task in tasks)
        task.id: tester.widget<AnimatedContainer>(
          find.byKey(ValueKey('topology-node-${task.id}')),
        ),
    };
    for (final card in cards.values) {
      final border =
          (card.foregroundDecoration as BoxDecoration).border as Border;
      expect(border.top.color, theme.themeData.basePrimary);
    }
    final before = tester.getTopLeft(node);
    for (var step = 1; step <= 5; step++) {
      await drag.moveTo(start + Offset(50 + step * 8, 40 + step * 6));
      await tester.pump();
      for (final task in tasks) {
        expect(
          tester.widget<AnimatedContainer>(
            find.byKey(ValueKey('topology-node-${task.id}')),
          ),
          same(cards[task.id]),
        );
      }
    }
    expect(tester.getTopLeft(node), isNot(before));
    await drag.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  for (final multiple in [false, true]) {
    testWidgets(
      '${multiple ? 'multiple' : 'single'} card drag retains all menus and updates routes positions and history',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final tasks = (await tester.runAsync(() async {
          return [
            for (var index = 0; index < 12; index++)
              await workspaces.create(
                title: 'Drag task $index',
                task: 'Wait for instructions',
                kind: AiWorkspaceKind.primary,
                startImmediately: false,
              ),
          ];
        }))!;
        workspaces.connectCanvasTasks(tasks[0].id, tasks[1].id);
        workspaces.connectCanvasTasks(tasks[2].id, tasks[3].id);
        final initialPositions = {
          for (final (index, task) in tasks.indexed)
            task.id: Offset(180 + (index % 4) * 350, 180 + (index ~/ 4) * 240),
        };
        final savedPositions = {
          for (final entry in initialPositions.entries)
            entry.key: [entry.value.dx, entry.value.dy],
        };
        workspaces.updateCanvasPositions(savedPositions);
        await tester.pumpWidget(app());
        await tick(tester);
        final canvas = find.byKey(const ValueKey('task-topology-canvas'));
        final controller = tester
            .widget<InteractiveViewer>(canvas)
            .transformationController!;
        const scale = .8;
        controller.value = Matrix4.identity()
          ..scaleByDouble(scale, scale, 1, 1);
        await tester.pumpAndSettle();
        Finder card(String id) => find.byKey(ValueKey('topology-node-$id'));
        Offset position(String id) {
          final placed = tester.widget<Positioned>(
            find.byKey(ValueKey('topology-position-$id')),
          );
          return Offset(placed.left!, placed.top!);
        }

        MenuAnchor menu(String id) => tester.widget<MenuAnchor>(
          find.ancestor(of: card(id), matching: find.byType(MenuAnchor)).first,
        );
        Rect bounds(String id) {
          final placed = tester.widget<Positioned>(
            find.byKey(ValueKey('topology-position-$id')),
          );
          return position(id) & Size(placed.width!, placed.height!);
        }

        final edges = workspaces.connections;
        void expectRoutesFollowCards() {
          final painter =
              tester
                      .widget<CustomPaint>(
                        find.byKey(
                          const ValueKey('topology-connections-paint'),
                        ),
                      )
                      .painter!
                  as TaskTopologyConnectionsPainter;
          expect(
            painter.routes.keys,
            unorderedEquals(edges.map((edge) => edge.id)),
          );
          for (final edge in edges) {
            final expected = TaskTopologyConnection.between(
              bounds(edge.fromId),
              bounds(edge.toId),
            );
            final actual = painter.routes[edge.id]!;
            expect((actual.start - expected.start).distance, lessThan(.001));
            expect((actual.end - expected.end).distance, lessThan(.001));
            expect(actual.path.getBounds(), expected.path.getBounds());
          }
        }

        await tester.tap(card(tasks.first.id));
        if (multiple) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.tap(card(tasks[1].id));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
        await tester.pumpAndSettle();
        final targetIds = {tasks.first.id, if (multiple) tasks[1].id};
        for (final task in tasks) {
          expect(selected(tester, task.id), targetIds.contains(task.id));
        }
        final start = tester.getCenter(card(tasks.first.id));
        final drag = await tester.startGesture(start);
        await drag.moveTo(start + const Offset(30, 20));
        await tester.pumpAndSettle();
        await drag.moveTo(start + const Offset(60, 40));
        await tester.pumpAndSettle();
        final menusBefore = {for (final task in tasks) task.id: menu(task.id)};
        final cardsBefore = {
          for (final task in tasks)
            task.id: tester.widget<AnimatedContainer>(card(task.id)),
        };
        var totalScreenDelta = const Offset(60, 40);
        for (var step = 1; step <= 6; step++) {
          totalScreenDelta = Offset(60 + step * 8, 40 + step * 6);
          await drag.moveTo(start + totalScreenDelta);
          await tester.pump();
          for (final task in tasks) {
            expect(menu(task.id), same(menusBefore[task.id]));
            expect(
              tester.widget<AnimatedContainer>(card(task.id)),
              same(cardsBefore[task.id]),
            );
            final expected =
                initialPositions[task.id]! +
                (targetIds.contains(task.id)
                    ? totalScreenDelta / scale
                    : Offset.zero);
            expect((position(task.id) - expected).distance, lessThan(.001));
          }
          expectRoutesFollowCards();
          expect(workspaces.canvasPositions, savedPositions);
        }
        final finalPositions = {
          for (final task in tasks) task.id: position(task.id),
        };
        await drag.up();
        await tester.pumpAndSettle();
        for (final task in tasks) {
          expect(position(task.id), finalPositions[task.id]);
          expect(workspaces.canvasPositions[task.id], [
            finalPositions[task.id]!.dx,
            finalPositions[task.id]!.dy,
          ]);
        }
        expectRoutesFollowCards();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tick(tester);
        for (final task in tasks) {
          expect(position(task.id), initialPositions[task.id]);
        }
        expect(workspaces.canvasPositions, savedPositions);
        expectRoutesFollowCards();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tick(tester);
        for (final task in tasks) {
          expect(position(task.id), finalPositions[task.id]);
          expect(workspaces.canvasPositions[task.id], [
            finalPositions[task.id]!.dx,
            finalPositions[task.id]!.dy,
          ]);
        }
        expectRoutesFollowCards();
        if (!multiple) {
          final external = (await tester.runAsync(
            () => workspaces.create(
              title: 'Created outside canvas history',
              task: 'Wait for instructions',
              kind: AiWorkspaceKind.primary,
              startImmediately: false,
            ),
          ))!;
          const externalPosition = Offset(1500, 900);
          workspaces.updateCanvasPositions({
            ...workspaces.canvasPositions,
            external.id: [externalPosition.dx, externalPosition.dy],
          });
          await tester.pumpAndSettle();
          expect(position(external.id), externalPosition);
          for (final command in [
            LogicalKeyboardKey.keyZ,
            LogicalKeyboardKey.keyY,
          ]) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.sendKeyEvent(command);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            await tick(tester);
            expect(workspaces.find(external.id), same(external));
            expect(position(external.id), externalPosition);
            expect(workspaces.canvasPositions[external.id], [
              externalPosition.dx,
              externalPosition.dy,
            ]);
            for (final task in tasks) {
              expect(
                position(task.id),
                command == LogicalKeyboardKey.keyZ
                    ? initialPositions[task.id]
                    : finalPositions[task.id],
              );
            }
            expectRoutesFollowCards();
          }
        }
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }

  for (final deletion in [
    'keyboard',
    'agent',
    'last card',
    'agent partial selection',
  ]) {
    testWidgets('deleting the dragged card releases drag state: $deletion', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      AiAgentWorkspace? survivor;
      if (deletion != 'last card') {
        survivor = (await tester.runAsync(
          () => workspaces.create(
            title: 'Surviving leader',
            task: 'Coordinate',
            kind: AiWorkspaceKind.primary,
            startImmediately: false,
          ),
        ))!;
      }
      final target = (await tester.runAsync(
        () => workspaces.create(
          title: 'Dragged deletion target',
          task: 'Wait for instructions',
          parentId: survivor?.id,
          kind: survivor == null
              ? AiWorkspaceKind.primary
              : AiWorkspaceKind.permanent,
          startImmediately: false,
        ),
      ))!;
      workspaces.updateCanvasPositions({
        if (survivor != null) survivor.id: [180, 240],
        target.id: [560, 240],
      });
      await tester.pumpWidget(app());
      await tick(tester);
      final controller = tester
          .widget<InteractiveViewer>(
            find.byKey(const ValueKey('task-topology-canvas')),
          )
          .transformationController!;
      controller.value = Matrix4.identity();
      await tester.pumpAndSettle();
      Finder card(String id) => find.byKey(ValueKey('topology-node-$id'));
      Offset position(String id) {
        final placed = tester.widget<Positioned>(
          find.byKey(ValueKey('topology-position-$id')),
        );
        return Offset(placed.left!, placed.top!);
      }

      await tester.tap(card(target.id));
      final partialSelection = deletion == 'agent partial selection';
      if (partialSelection) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(card(survivor!.id));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.pumpAndSettle();
      final start = tester.getCenter(
        card(partialSelection ? survivor!.id : target.id),
      );
      final drag = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(start + const Offset(45, 30));
      await tester.pumpAndSettle();
      expect(position(target.id), const Offset(605, 270));
      final survivorPosition = survivor == null ? null : position(survivor.id);
      final agentDeletion = deletion.startsWith('agent');
      if (agentDeletion) {
        final result = await survivor!.assistant.workspaceToolHandler!(
          'delete_agent',
          {'agent_id': target.id},
        );
        expect(result['status'], 'deleted');
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      }
      await tester.pumpAndSettle();
      expect(workspaces.find(target.id), isNull);
      expect(card(target.id), findsNothing);
      await drag.moveTo(start + const Offset(60, 40));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (partialSelection) {
        expect(position(survivor!.id), survivorPosition);
        expect(workspaces.canvasPositions[survivor.id], [
          survivorPosition!.dx,
          survivorPosition.dy,
        ]);
      }
      if (survivor == null) {
        expect(workspaces.sessions, isEmpty);
        survivor = (await tester.runAsync(
          () => workspaces.create(
            title: 'New leader after last card deletion',
            task: 'Wait for instructions',
            kind: AiWorkspaceKind.primary,
            startImmediately: false,
          ),
        ))!;
        await tester.pumpAndSettle();
        controller.value = Matrix4.identity();
        await tester.pumpAndSettle();
      }
      expect(workspaces.layoutCanvasGroup!({survivor.id}), isTrue);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tick(tester);
      if (!agentDeletion) {
        expect(workspaces.find(target.id), isNotNull);
        expect(workspaces.find(survivor.id), same(survivor));
        expect(position(target.id), const Offset(605, 270));
      } else {
        expect(workspaces.find(target.id), isNull);
      }
      final before = position(survivor.id);
      await tester.drag(card(survivor.id), const Offset(45, 25));
      await tester.pumpAndSettle();
      expect(position(survivor.id), before + const Offset(45, 25));
      expect(workspaces.canvasPositions[survivor.id], [
        before.dx + 45,
        before.dy + 25,
      ]);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }

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
            reason: 'The selection fill must paint beyond the original scene boundary',
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
        final stack = find
            .ancestor(of: node, matching: find.byType(Stack))
            .first;
        final nodeKeys = {
          ValueKey('topology-position-${first.id}'),
          ValueKey('topology-position-${second.id}'),
        };
        return tester
            .widgetList<Positioned>(
              find.descendant(of: stack, matching: find.byType(Positioned)),
            )
            .where((widget) => nodeKeys.contains(widget.key))
            .map((widget) => widget.key)
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
    expect(find.byKey(const ValueKey('confirm-topology-delete')), findsNothing);
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
      void expectConnectionPortLayers() {
        for (final task in [root, first, second]) {
          for (final side in ['in', 'out', 'top', 'bottom']) {
            expectPortWithoutOpacityLayers(
              tester,
              find.byKey(ValueKey('topology-port-$side-${task.id}')),
            );
          }
        }
      }

      expectConnectionPortLayers();
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
        await tester.pump(const Duration(milliseconds: 75));
        expectConnectionPortLayers();
        await gesture.moveTo(end);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expectConnectionPortLayers();
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
      for (final task in [root, first, second]) {
        expect(position(task.id), before[task.id]);
      }
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

  for (final (useChildren, childToRoot) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    testWidgets(
      'cross-tree drag applies immediately and supports undo with child endpoints: $useChildren child to root: $childToRoot',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1180, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final rootA = (await tester.runAsync(
          () => workspaces.createPrimary(title: 'Root A', task: 'one'),
        ))!;
        final rootB = (await tester.runAsync(
          () => workspaces.createPrimary(title: 'Root B', task: 'two'),
        ))!;
        final a = useChildren || childToRoot
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
          findsNothing,
        );
        expect(rootA.kind, AiWorkspaceKind.primary);
        expect(rootB.kind, AiWorkspaceKind.permanent);
        expect(rootB.parentId, useChildren ? b.id : a.id);
        expect(workspaces.primaries, [rootA]);
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
        expect(workspaces.primaries, [rootA]);
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
    'mixed select-all deletion runs without confirmation and supports undo',
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
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      await tester.tapAt(
        tester.getTopLeft(canvas) + const Offset(20, 20),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topology-canvas-select-all')),
      );
      await tester.pumpAndSettle();
      for (final agent in [root, a, b]) {
        expect(selected(tester, agent.id), isTrue);
      }
      Set<String> selectedWires() {
        final dynamic painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .firstWhere(
              (painter) =>
                  painter.runtimeType.toString() ==
                  'TaskTopologyConnectionsPainter',
            );
        return Set<String>.of(painter.selectedEdges as Set<String>);
      }

      final ids = workspaces.connections.map((c) => c.id).toSet();
      expect(selectedWires(), ids);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('confirm-topology-delete')),
        findsNothing,
      );
      expect(workspaces.sessions, isEmpty);
      expect(workspaces.connections, isEmpty);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tick(tester);
      expect(workspaces.sessions, hasLength(3));
      expect(workspaces.connections.map((c) => c.id).toSet(), ids);
      expect(selectedWires(), ids);
      expect(a.parentId, root.id);
      expect(b.parentId, root.id);
      expect(root.kind, AiWorkspaceKind.primary);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
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
              (painter) =>
                  painter.runtimeType.toString() ==
                  'TaskTopologyConnectionsPainter',
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
      expect(workspaces.connections, isEmpty);
      expect(
        find.byKey(const ValueKey('confirm-topology-disconnect')),
        findsNothing,
      );
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
              (painter) =>
                  painter.runtimeType.toString() ==
                  'TaskTopologyConnectionsPainter',
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
      final axes =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is CustomPaint &&
                          widget.painter is TaskCanvasAxesPainter,
                    ),
                  )
                  .painter!
              as TaskCanvasAxesPainter;
      Offset axisPosition() => MatrixUtils.transformPoint(
        axes.transform.value,
        axes.sceneOrigin.value,
      );
      controller.value =
          Matrix4.translationValues(
            800 - original.dx * .5,
            230 - original.dy * .5,
            0,
          ) *
          Matrix4.diagonal3Values(.5, .5, 1);
      await tester.pump();
      final before = tester.getCenter(node);
      final axesBefore = axisPosition();
      final gesture = await tester.startGesture(before);
      await gesture.moveTo(before - const Offset(400, 100));
      await tester.pump();
      expect(axisPosition(), axesBefore);
      expect((tester.getCenter(node) - before).dx, closeTo(-400, 2));
      expect((tester.getCenter(node) - before).dy, closeTo(-100, 2));
      await gesture.moveTo(before - const Offset(460, 130));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect((tester.getCenter(node) - before).dx, closeTo(-460, 2));
      expect((tester.getCenter(node) - before).dy, closeTo(-130, 2));
      expect(axisPosition(), axesBefore);
      expect(position().dx - workspaces.canvasOrigin.dx, lessThan(0));
      expect(position().dy - workspaces.canvasOrigin.dy, lessThan(0));
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
      final axesAfterZoom = axisPosition();
      await tester.drag(node, const Offset(-600, -400));
      await tester.pumpAndSettle();
      expect((tester.getCenter(node) - zoomedBefore).dx, closeTo(-600, 2));
      expect((tester.getCenter(node) - zoomedBefore).dy, closeTo(-400, 2));
      expect(axisPosition(), axesAfterZoom);
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
      expect(find.byKey(const ValueKey('topology-footer')), findsNothing);
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('topology-view-toolbar')),
      );
      expect(toolbar.bottom, closeTo(canvas.bottom - 8, 1));
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
      final originalSize = tester.getSize(find.byWidget(viewer.child!)).width;
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
        tester
            .getSize(
              find.byWidget(tester.widget<InteractiveViewer>(finder).child!),
            )
            .width,
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
      expect(find.byKey(const ValueKey('topology-footer')), findsNothing);
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('topology-view-toolbar')),
      );
      final canvas = tester.getRect(
        find.byKey(const ValueKey('task-topology-canvas')),
      );
      expect(toolbar.bottom, closeTo(canvas.bottom - 8, 1));
      expect(
        find.byKey(const ValueKey('topology-auto-layout')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'manual workflow main action keeps cards linked and is undoable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final main = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Main', task: 'one'),
      ))!;
      final child = (await tester.runAsync(
        () => workspaces.create(title: 'Child', task: 'two', parentId: main.id),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final mainNode = find.byKey(ValueKey('topology-node-${main.id}'));
      final childNode = find.byKey(ValueKey('topology-node-${child.id}'));
      await tester.tap(childNode, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      final mainPosition = tester.getCenter(mainNode);
      final childPosition = tester.getCenter(childNode);
      expect(
        find.byKey(const ValueKey('topology-context-make-root')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('topology-context-make-workflow-main')),
      );
      await tester.pumpAndSettle();
      expect(child.kind, AiWorkspaceKind.primary);
      expect(main.parentId, child.id);
      expect(workspaces.connections, hasLength(1));
      expect(tester.getCenter(mainNode), mainPosition);
      expect(tester.getCenter(childNode), childPosition);
      for (final (key, expected) in [
        (LogicalKeyboardKey.keyZ, main),
        (LogicalKeyboardKey.keyY, child),
      ]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(
          workspaces.sessions.where(
            (agent) => agent.kind == AiWorkspaceKind.primary,
          ),
          [expected],
        );
        expect(workspaces.connections, hasLength(1));
      }
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
          title: other.title,
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
      expect(
        find.byKey(const ValueKey('topology-context-make-child')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(rootNode);
      await tester.pumpAndSettle();
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
      final selectedLabel = '${other.id} · ${other.title}';
      final alternativeLabel = '${temporary.id} · ${temporary.title}';
      expect(find.text(selectedLabel), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topology-parent-select')));
      await tester.pumpAndSettle();
      expect(find.text(alternativeLabel), findsOneWidget);
      await tester.tap(find.text(alternativeLabel));
      await tester.pumpAndSettle();
      expect(find.text(alternativeLabel), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topology-parent-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(selectedLabel).last);
      await tester.pumpAndSettle();
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
      expect(
        find.byKey(const ValueKey('confirm-topology-make-root')),
        findsNothing,
      );
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
      await tester.tap(
        find.byKey(const ValueKey('topology-context-duplicate')),
      );
      await tick(tester);
      expect(workspaces.sessions, hasLength(1));
      await tester.tap(
        find.byKey(ValueKey('topology-node-${original.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-context-paste')));
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
      await tester.tap(find.byKey(ValueKey('topology-node-$copyId')));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('confirm-topology-delete')),
        findsNothing,
      );
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
    'pasted agent starts at the context click and stays selected and idle',
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
      await tester.tap(
        find.byKey(const ValueKey('topology-context-duplicate')),
      );
      await tick(tester);
      expect(workspaces.sessions, hasLength(1));
      await tester.tap(
        find.byKey(ValueKey('topology-node-${original.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topology-context-paste')));
      await tick(tester);
      expect(workspaces.sessions, hasLength(2));
      final copy = workspaces.sessions.firstWhere(
        (item) => item.id != original.id,
      );
      final copiedPosition = tester.widget<Positioned>(
        find.byKey(ValueKey('topology-position-${copy.id}')),
      );
      expect(
        copiedPosition.left,
        originalPosition.left! + originalPosition.width! / 2,
      );
      expect(
        copiedPosition.top,
        originalPosition.top! + originalPosition.height! / 2,
      );
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
    'context menus copy and paste a selected workflow with its links',
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
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: 'Workflow root',
          task: 'Coordinate',
        ),
      ))!;
      final child = (await tester.runAsync(
        () => workspaces.create(
          title: 'Workflow child',
          task: 'Help',
          parentId: root.id,
          startImmediately: false,
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      await tester.tap(find.byKey(ValueKey('topology-node-${root.id}')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.byKey(ValueKey('topology-node-${child.id}')));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('topology-node-${root.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(TaskTopologyPage)),
      );
      expect(find.text(l.aiTopologyCopyWorkflow), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('topology-context-duplicate')),
      );
      await tick(tester);
      expect(workspaces.sessions, hasLength(2));
      await tester.tapAt(
        const Offset(1000, 700),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text(l.aiTopologyPasteWorkflow), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topology-canvas-paste')));
      for (var attempt = 0; attempt < 10; attempt++) {
        await tick(tester);
        if (workspaces.sessions.length == 4 &&
            selected(tester, workspaces.sessions.last.id)) {
          break;
        }
      }
      expect(workspaces.sessions, hasLength(4));
      final copies = workspaces.sessions
          .where((s) => s.id != root.id && s.id != child.id)
          .toList();
      final copiedRoot = copies.singleWhere(
        (s) => s.kind == AiWorkspaceKind.primary,
      );
      final copiedChild = copies.singleWhere(
        (s) => s.parentId == copiedRoot.id,
      );
      expect(workspaces.isConnected(copiedRoot.id, copiedChild.id), isTrue);
      expect(copies.every((s) => !s.busy), isTrue);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'imported nodes with remote saved coordinates land at the pointer after pan and zoom',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: 'Imported far away',
          task: 'Keep layout',
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final transform = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      transform.value =
          Matrix4.translationValues(400, 250, 0) *
          Matrix4.diagonal3Values(.6, .6, 1);
      await tester.pumpAndSettle();
      final existingBefore = tester.getTopLeft(
        find.byKey(ValueKey('topology-node-${source.id}')),
      );
      final data = workspaces.exportData();
      data['canvas'] = {
        source.id: [12000.0, 9000.0],
      };
      final pointer = tester.getTopLeft(canvas) + const Offset(160, 130);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: pointer);
      await mouse.moveTo(pointer);
      await tester.pump();
      late Map<String, String> imported;
      await tester.runAsync(() async {
        imported = await workspaces.importData(data);
      });
      await tick(tester);
      final id = imported[source.id]!;
      final actual = tester.getTopLeft(
        find.byKey(ValueKey('topology-node-$id')),
      );
      expect(actual.dx, closeTo(pointer.dx, 1));
      expect(actual.dy, closeTo(pointer.dy, 1));
      final existingAfter = tester.getTopLeft(
        find.byKey(ValueKey('topology-node-${source.id}')),
      );
      expect(existingAfter.dx, closeTo(existingBefore.dx, 1));
      expect(existingAfter.dy, closeTo(existingBefore.dy, 1));
      expect(selected(tester, id), isTrue);
      expect(workspaces.canvasPositions[id], isNot([12000.0, 9000.0]));
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
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
        'import-agents',
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
    'canvas import opens the native picker directly and cancellation leaves no manager dialog',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var openCalls = 0;
      const picker = MethodChannel('plugins.flutter.io/file_selector');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
        call,
      ) async {
        if (call.method == 'openFile') openCalls++;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        ),
      );
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      await tester.tapAt(
        tester.getTopLeft(canvas) + const Offset(20, 20),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topology-canvas-import-agents')),
      );
      await tester.pumpAndSettle();
      expect(openCalls, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byKey(const ValueKey('storage-transfer-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('topology-canvas-import-agents')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'multiple selected cards offer workflow export and single selection restores agent actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: 'First selected agent',
          task: 'one',
        ),
      ))!;
      final second = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: 'Second selected agent',
          task: 'two',
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final firstCard = find.byKey(ValueKey('topology-node-${first.id}'));
      final secondCard = find.byKey(ValueKey('topology-node-${second.id}'));
      final l = AppLocalizations.of(
        tester.element(find.byType(TaskTopologyPage)),
      );
      final singleActions = [
        l.agentStorageManage,
        l.agentStorageManageContext,
        l.aiTopologyOpen,
        l.aiTopologyCopyId,
        l.aiTopologyRename,
        l.aiTopologyBringToFront,
        l.aiTopologyMakeChild,
        l.agentStorageImportMemory,
        l.agentStorageExportMemory,
        l.agentStorageExportChat,
        l.agentStorageExportAgent,
      ];
      final workflow = find.byKey(
        const ValueKey('topology-context-export-workflow'),
      );

      await tester.tap(firstCard);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(secondCard);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(selected(tester, first.id), isTrue);
      expect(selected(tester, second.id), isTrue);
      await tester.tap(secondCard, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      for (final key in [
        'open',
        'paste',
        'copy-id',
        'rename',
        'bring-front',
        'create',
        'make-root',
        'make-child',
        'manage-chat',
      ]) {
        expect(find.byKey(ValueKey('topology-context-$key')), findsNothing);
      }
      for (final key in ['duplicate', 'export-workflow', 'connect', 'delete']) {
        expect(find.byKey(ValueKey('topology-context-$key')), findsOneWidget);
      }
      expect(workflow, findsOneWidget);
      expect(find.text(l.agentStorageExportWorkflow), findsOneWidget);
      for (final label in singleActions) {
        expect(find.text(label), findsNothing);
      }
      expect(
        find.byKey(const ValueKey('topology-context-export-chat')),
        findsNothing,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(firstCard);
      await tester.pumpAndSettle();
      await tester.tap(firstCard, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(workflow, findsNothing);
      for (final key in [
        'open',
        'paste',
        'copy-id',
        'rename',
        'bring-front',
        'create',
        'make-child',
        'manage-chat',
      ]) {
        expect(find.byKey(ValueKey('topology-context-$key')), findsOneWidget);
      }
      for (final label in singleActions) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('topology-context-export-chat')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await finish(tester);
    },
  );

  testWidgets('card chat export opens the save picker without a manager', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final agent = (await tester.runAsync(
      () => workspaces.createPrimary(title: 'Chat export', task: 'one'),
    ))!;
    var saveCalls = 0;
    Object? saveArguments;
    const picker = MethodChannel('plugins.flutter.io/file_selector');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
      call,
    ) async {
      if (call.method == 'getSavePath') {
        saveCalls++;
        saveArguments = call.arguments;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        null,
      ),
    );
    await tester.pumpWidget(app());
    await tick(tester);
    await tester.tap(
      find.byKey(ValueKey('topology-node-${agent.id}')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('topology-context-export-chat')),
    );
    await tester.pumpAndSettle();
    expect(saveCalls, 1);
    expect(saveArguments.toString(), contains(agent.id));
    expect(saveArguments.toString(), contains('chat'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('storage-transfer-action')), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
    'card exports skip the manager and failed imports retain a visible reason with retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final agent = (await tester.runAsync(
        () => workspaces.createPrimary(
          title: 'Direct transfer',
          task: 'Keep data',
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      final context = tester.element(find.byType(TaskTopologyPage));
      final l = AppLocalizations.of(context);
      const picker = MethodChannel('plugins.flutter.io/file_selector');
      final save = Completer<Object?>();
      var openCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
        call,
      ) async {
        if (call.method == 'getSavePath') return save.future;
        if (call.method == 'openFile') {
          openCalls++;
          if (openCalls == 1) {
            throw PlatformException(
              code: 'test-selector',
              message: 'Cannot read archive',
            );
          }
          return null;
        }
        throw UnsupportedError(call.method);
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        ),
      );
      final exporting = showAgentStorage(
        context,
        theme.themeData,
        agent.id,
        action: 'memory',
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byKey(const ValueKey('storage-transfer-action')),
        findsNothing,
      );
      save.complete(null);
      await exporting;
      final importing = showAgentStorage(
        context,
        theme.themeData,
        agent.id,
        action: 'import',
      );
      await tester.pumpAndSettle();
      expect(find.text(l.agentStorageTransferFailedTitle), findsOneWidget);
      expect(
        find.byKey(const ValueKey('storage-transfer-action')),
        findsNothing,
      );
      final notice = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byType(Text),
      );
      expect(tester.widget<Text>(notice).data, contains('Cannot read archive'));
      expect(tester.widget<Text>(notice).data, isNot(endsWith('详情：')));
      expect(
        agentTransferFailureMessage(
          context,
          const FormatException('Invalid package structure'),
        ),
        l.agentStorageInvalidPackage,
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-storage-transfer-retry')),
      );
      await tester.pumpAndSettle();
      await importing;
      expect(openCalls, 2);
      expect(find.byType(AlertDialog), findsNothing);
      expect(workspaces.find(agent.id), same(agent));
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'card chat deletion confirms in red and clears only the clicked agent',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late AiAgentWorkspace root;
      late AiAgentWorkspace child;
      await tester.runAsync(() async {
        root = await workspaces.createPrimary(
          title: 'Keep root',
          task: 'Coordinate',
        );
        child = await workspaces.create(
          title: 'Clear child chat',
          task: 'Keep agent',
          parentId: root.id,
          startImmediately: false,
        );
        await root.assistant.sendMessage('Keep root history');
        await child.assistant.sendMessage('Clear child history');
      });
      await tester.pumpWidget(app());
      await tick(tester);
      final rootMessages = root.assistant.messages.toList();
      final childMessages = child.assistant.messages.toList();
      expect(childMessages, isNotEmpty);
      await tester.tap(
        find.byKey(ValueKey('topology-node-${child.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(TaskTopologyPage)),
      );
      expect(
        find.byKey(const ValueKey('topology-context-delete-chat')),
        findsNothing,
      );
      expect(
        tester.getTopLeft(find.text(l.agentStorageManageContext)).dy,
        greaterThan(tester.getTopLeft(find.text(l.agentStorageManage)).dy),
      );
      await tester.tap(
        find.byKey(const ValueKey('topology-context-manage-chat')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('storage-context-budget')),
        findsOneWidget,
      );
      Future<void> openDeletion() async {
        final deleteButton = find.widgetWithText(AppActionButton, l.delete);
        await tester.ensureVisible(deleteButton);
        await tester.tap(deleteButton);
        await tester.pumpAndSettle();
      }

      await openDeletion();
      expect(
        tester
            .widget<AppActionButton>(
              find.byKey(const ValueKey('confirm-delete-chat')),
            )
            .destructive,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('cancel-delete-chat')));
      await tester.pumpAndSettle();
      expect(child.assistant.messages, orderedEquals(childMessages));
      await openDeletion();
      await tester.tap(find.byKey(const ValueKey('confirm-delete-chat')));
      await tick(tester);
      expect(child.assistant.messages, isEmpty);
      expect(root.assistant.messages, orderedEquals(rootMessages));
      expect(workspaces.find(child.id), same(child));
      expect(child.parentId, root.id);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'modifier keys preview available canvas shortcuts before an operation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(
        () => workspaces.createPrimary(title: 'Shortcut preview', task: 'one'),
      );
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final hints = find.byKey(const ValueKey('topology-shortcut-hints'));
      final toolbar = find.byKey(const ValueKey('topology-view-toolbar'));
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(30, 100));
      await tester.pumpAndSettle();
      expect(hints, findsNothing);
      expect(find.byKey(const ValueKey('topology-footer')), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(hints, findsOneWidget);
      expect(
        find.descendant(of: hints, matching: find.textContaining('Ctrl')),
        findsWidgets,
      );
      expect(
        find.descendant(of: hints, matching: find.textContaining('全选')),
        findsWidgets,
      );
      expect(
        find.descendant(of: hints, matching: find.textContaining('缩放')),
        findsWidgets,
      );
      expect(
        tester.getRect(hints).bottom,
        closeTo(tester.getRect(toolbar).bottom, 1),
      );
      // Held modifiers continue to help even without another key or operation.
      await tester.pump(const Duration(seconds: 3));
      expect(hints, findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(hints, findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(hints, findsOneWidget);
      expect(
        find.descendant(of: hints, matching: find.textContaining('Shift')),
        findsWidgets,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(hints, findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(hints, findsOneWidget);
      expect(
        find.descendant(of: hints, matching: find.textContaining('空格')),
        findsWidgets,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(hints, findsNothing);
      // Editing zoom text owns modifiers; canvas help must not appear over it.
      await tester.tap(find.byKey(const ValueKey('topology-zoom-percentage')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(hints, findsNothing);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'editable zoom percentage follows the viewport and owns text shortcuts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(
        () => workspaces.createPrimary(title: 'Zoom editor', task: 'one'),
      );
      await tester.pumpWidget(app());
      await tick(tester);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final transform = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final editor = find.byKey(const ValueKey('topology-zoom-percentage'));
      String shown() => tester.widget<TextField>(editor).controller!.text;
      expect(shown(), (transform.value.entry(0, 0) * 100).round().toString());
      final center = tester.getSize(canvas).center(Offset.zero);
      final sceneCenter = transform.toScene(center);
      final frame = find.byKey(const ValueKey('topology-zoom-field-frame'));
      Color frameColor() =>
          ((tester
                              .widget<DecoratedBox>(
                                find
                                    .descendant(
                                      of: frame,
                                      matching: find.byType(DecoratedBox),
                                    )
                                    .first,
                              )
                              .decoration
                          as BoxDecoration)
                      .border!
                  as Border)
              .top
              .color;
      expect(frameColor(), Colors.transparent);
      await tester.tap(editor);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(frameColor(), isNot(Colors.transparent));
      expect(frameColor(), isNot(theme.themeData.basePrimary));
      await tester.pumpAndSettle();
      final frameRect = tester.getRect(frame);
      final toolbarRect = tester.getRect(
        find.byKey(const ValueKey('topology-view-toolbar')),
      );
      expect(frameRect.height, 24);
      expect(frameRect.center.dy, closeTo(toolbarRect.center.dy, .01));
      expect(
        tester.getRect(editor).center.dy,
        closeTo(frameRect.center.dy, .01),
      );
      final focusBorder =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: frame,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(
        (focusBorder.border! as Border).top.color,
        theme.themeData.basePrimary,
      );
      await captureOverlay(tester, 'zoom-field-focused-alignment');
      await tester.enterText(editor, '125');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(transform.value.entry(0, 0), isNot(closeTo(1.25, .001)));
      await tester.pumpAndSettle();
      expect(transform.value.entry(0, 0), closeTo(1.25, .001));
      expect((transform.toScene(center) - sceneCenter).distance, lessThan(.01));
      expect(shown(), '125');

      await tester.tap(editor);
      await tester.enterText(editor, '77');
      // Ongoing viewport updates must not overwrite the draft being edited.
      transform.value = transform.value.clone()
        ..setEntry(0, 0, 1.1)
        ..setEntry(1, 1, 1.1);
      await tester.pump();
      expect(shown(), '77');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(
        tester.widget<TextField>(editor).controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(transform.value.entry(0, 0), closeTo(1.1, .001));
      expect(shown(), '110');

      await tester.tap(editor);
      await tester.enterText(editor, '500');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(transform.value.entry(0, 0), closeTo(2.0, .001));
      expect(shown(), '200');
      await tester.tap(editor);
      await tester.enterText(editor, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(shown(), '200');
      await tester.tap(editor);
      await tester.enterText(editor, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(shown(), '1');
      expect(transform.value.entry(0, 0), closeTo(.01, .00001));
      for (final (input, display) in [
        ('1.5', '1.5'),
        ('1.44', '1.4'),
        ('9', '9'),
        ('10', '10'),
        ('10.6', '11'),
      ]) {
        await tester.tap(editor);
        await tester.enterText(editor, input);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(shown(), display);
        expect(
          transform.value.entry(0, 0),
          closeTo(double.parse(input) / 100, .00001),
        );
      }
      expect(tester.takeException(), isNull);
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
        closeTo((initial.entry(0, 0) * math.exp(.5)).clamp(.01, 2.0), .001),
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

  for (final (axis, input, shift) in [
    ('vertical', const Offset(0, 120), false),
    ('horizontal', const Offset(120, 0), false),
    ('shift', const Offset(0, 120), true),
  ]) {
    for (final direction in [1, -1]) {
      testWidgets(
        'canvas wheel $axis direction=$direction accelerates immediately up to 3x',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1180, 850));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.runAsync(
            () => workspaces.createPrimary(
              title: 'Pan acceleration',
              task: 'one',
            ),
          );
          await tester.pumpWidget(app());
          await tick(tester);
          final canvas = find.byKey(const ValueKey('task-topology-canvas'));
          final controller = tester
              .widget<InteractiveViewer>(canvas)
              .transformationController!;
          final point = tester.getTopLeft(canvas) + const Offset(20, 20);
          final initial = controller.value.clone();
          if (shift) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          }
          for (var eventIndex = 0; eventIndex < 3; eventIndex++) {
            tester.binding.handlePointerEvent(
              PointerScrollEvent(
                timeStamp: Duration(milliseconds: 1000 + eventIndex * 25),
                position: point,
                scrollDelta: input * direction.toDouble(),
                kind: PointerDeviceKind.mouse,
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 25));
          }
          await tester.pumpAndSettle();
          if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          final horizontal = shift || input.dx != 0;
          expect(
            controller.value.entry(horizontal ? 0 : 1, 3),
            closeTo(
              initial.entry(horizontal ? 0 : 1, 3) - direction * 840,
              .01,
            ),
          );
          expect(
            controller.value.entry(horizontal ? 1 : 0, 3),
            closeTo(initial.entry(horizontal ? 1 : 0, 3), .01),
          );
          expect(controller.value.entry(0, 0), initial.entry(0, 0));
          await finish(tester);
        },
      );
    }
  }

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
      final semantics = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(1180, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
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
        final task = (await tester.runAsync(
          () => workspaces.createPrimary(
            title: 'Keep this position',
            task: 'one',
          ),
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
        final input = find.byKey(const ValueKey('ai-message-input'));
        expect(input, findsOneWidget);
        const draft = 'Accessible draft';
        await tester.enterText(input, draft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        final editor = tester.widget<EditableText>(
          find.descendant(of: input, matching: find.byType(EditableText)),
        );
        expect(
          editor.controller.selection,
          TextSelection(baseOffset: 0, extentOffset: draft.length),
        );
        expect(copiedText, draft);
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
      } finally {
        semantics.dispose();
      }
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
        final conversation = tester.widget<Column>(
          find.ancestor(of: header, matching: find.byType(Column)).first,
        );
        expect(conversation.children.whereType<Divider>(), isEmpty);
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
                      'path': 'C:/Users/XK/AppData/Local/Temp/lilygobox-readonly-approval-test.txt',
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
              localizationsDelegates: appLocalizationDelegates,
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
    final zoomTarget = (interrupted.entry(0, 0) * 1.2).clamp(.01, 2.0);
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
    'node context menu stays unscaled and deletes the clicked agent only',
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
      // 菜单较高时允许贴近窗口边缘，始终保持在可用区域内。
      final menuSurface = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const ValueKey('topology-context-open')),
              matching: find.byType(PopupMenuSurface),
            )
            .first,
      );
      expect(menuSurface.top, greaterThanOrEqualTo(0));
      expect(menuSurface.bottom, lessThanOrEqualTo(850));
      final duplicateRect = tester.getRect(
        find.byKey(const ValueKey('topology-context-duplicate')),
      );
      final copyIdRect = tester.getRect(
        find.byKey(const ValueKey('topology-context-copy-id')),
      );
      final pasteRect = tester.getRect(
        find.byKey(const ValueKey('topology-context-paste')),
      );
      expect(pasteRect.top - duplicateRect.bottom, closeTo(4, 1));
      expect(copyIdRect.top - pasteRect.bottom, closeTo(4, 1));
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
      expect(
        find.byKey(const ValueKey('confirm-topology-delete')),
        findsNothing,
      );
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
    'deleting an intermediate child preserves its branch without confirmation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => workspaces.createPrimary(title: 'Keep root', task: 'Coordinate'),
      ))!;
      final middle = (await tester.runAsync(
        () => workspaces.create(
          title: 'Delete middle',
          task: 'Work',
          parentId: root.id,
        ),
      ))!;
      final leaf = (await tester.runAsync(
        () => workspaces.create(
          title: 'Keep descendant',
          task: 'Continue',
          parentId: middle.id,
        ),
      ))!;
      await tester.pumpWidget(app());
      await tick(tester);
      await tester.tap(
        find.byKey(ValueKey('topology-node-${middle.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final deleteItem = find.byKey(const ValueKey('topology-context-delete'));
      await tester.ensureVisible(deleteItem);
      await tester.pumpAndSettle();
      await tester.tap(deleteItem);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('confirm-topology-delete')),
        findsNothing,
      );
      expect(workspaces.find(middle.id), isNull);
      expect(workspaces.find(root.id), same(root));
      expect(workspaces.find(leaf.id), same(leaf));
      expect(leaf.kind, AiWorkspaceKind.permanent);
      expect(leaf.parentId, root.id);
      expect(workspaces.isConnected(root.id, leaf.id), isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tick(tester);
      expect(workspaces.find(middle.id), same(middle));
      expect(leaf.parentId, middle.id);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tick(tester);
      expect(workspaces.find(middle.id), isNull);
      expect(leaf.parentId, root.id);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

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
        find.byKey(const ValueKey('confirm-topology-delete')),
        findsNothing,
      );
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
    'root deletion uses the latest successor and undo restores the hierarchy',
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
      final latest = (await tester.runAsync(
        () => workspaces.create(
          title: 'New candidate',
          task: 'three',
          parentId: root.id,
          startImmediately: false,
        ),
      ))!;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('topology-context-delete')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('confirm-topology-delete')),
        findsNothing,
      );
      expect(workspaces.find(root.id), isNull);
      expect(latest.kind, AiWorkspaceKind.primary);
      expect(first.parentId, latest.id);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tick(tester);
      expect(workspaces.find(root.id), same(root));
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
      final scene = tester.getSize(find.byWidget(viewer.child!));
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

  testWidgets('child promotion preserves the merged subtree with one main', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tasks = (await tester.runAsync(() async {
      final leader = await workspaces.create(
        title: 'Leader',
        task: 'Work',
        startImmediately: false,
      );
      final root = await workspaces.create(
        title: 'Branch',
        parentId: leader.id,
        task: 'Work',
        startImmediately: false,
      );
      final child = await workspaces.create(
        title: 'Delegate',
        task: 'Work',
        parentId: root.id,
        startImmediately: false,
      );
      final peer = await workspaces.create(
        title: 'Peer',
        task: 'Work',
        startImmediately: false,
      );
      workspaces.connectTasks(child.id, peer.id);
      return [root, child, peer];
    }))!;
    await tester.pumpWidget(app());
    await tick(tester);
    Future<void> choose(String action) async {
      await tester.tap(
        find.byKey(ValueKey('topology-node-${tasks.first.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(action)));
      await tester.pumpAndSettle();
    }

    await choose('topology-context-make-root');
    expect(tasks.first.kind, AiWorkspaceKind.primary);
    expect(tasks[1].kind, AiWorkspaceKind.permanent);
    expect(tasks.last.kind, AiWorkspaceKind.permanent);
    expect(tasks.last.parentId, tasks[1].id);
    expect(workspaces.isConnected(tasks[1].id, tasks.last.id), isTrue);
    expect(tasks[1].parentId, tasks.first.id);
    expect(workspaces.isConnected(tasks[1].id, tasks.last.id), isTrue);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
    'empty topology creates a main agent and opens its own conversation',
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

  testWidgets(
    'creation context settings remain usable in a compact dialog and cancel independently',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 620));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      scope.provider.contextBudgetTokens = 180000;
      scope.provider.contextCompactionPercent = 85;
      await tester.pumpWidget(app(textScale: 1.5));
      await tick(tester);
      await tester.tap(find.byKey(const ValueKey('topology-empty-create')));
      await tick(tester);
      final budget = find.byKey(const ValueKey('topology-context-budget'));
      await tester.ensureVisible(budget);
      await tick(tester);
      await tester.enterText(budget, '64000');
      final percent = find.byKey(const ValueKey('topology-context-percent'));
      await tester.enterText(percent, '95');
      await tick(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('topology-create-confirm')).hitTestable(),
        findsOneWidget,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TaskTopologyPage)),
      );
      await tester.tap(find.text(l10n.settingsCancel));
      await tick(tester);
      expect(workspaces.sessions, isEmpty);
      expect(scope.provider.contextBudgetTokens, 180000);
      expect(scope.provider.contextCompactionPercent, 85);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'creation context settings validate and apply to primary and child',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      scope.provider.contextBudgetTokens = 180000;
      scope.provider.contextCompactionPercent = 85;
      await tester.pumpWidget(app());
      await tick(tester);
      await tester.tap(find.byKey(const ValueKey('topology-empty-create')));
      await tick(tester);
      Finder input(String key) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextField),
      );
      expect(
        tester
            .widget<TextField>(input('topology-context-budget'))
            .controller!
            .text,
        '180000',
      );
      expect(
        tester
            .widget<TextField>(input('topology-context-percent'))
            .controller!
            .text,
        '85',
      );
      await tester.enterText(input('topology-context-budget'), '0');
      await tester.enterText(input('topology-context-percent'), '101');
      await tester.tap(find.byKey(const ValueKey('topology-create-confirm')));
      await tick(tester);
      expect(workspaces.sessions, isEmpty);
      await tester.enterText(input('topology-context-budget'), '64000');
      await tester.enterText(input('topology-context-percent'), '80');
      await tester.enterText(
        find.byKey(const ValueKey('topology-task-input')),
        'Context parent task',
      );
      await tester.tap(find.byKey(const ValueKey('topology-create-confirm')));
      await tick(tester);
      final root = workspaces.sessions.single;
      expect(root.assistant.contextBudgetTokens, 64000);
      expect(root.assistant.contextCompactionPercent, 80);
      expect(scope.provider.contextBudgetTokens, 180000);
      await tester.tap(find.byKey(const ValueKey('topology-back')));
      await tick(tester);
      await tester.tap(find.byKey(ValueKey('topology-node-${root.id}')));
      await tester.tap(find.byKey(const ValueKey('topology-new-child')));
      await tick(tester);
      expect(
        tester
            .widget<TextField>(input('topology-context-budget'))
            .controller!
            .text,
        '64000',
      );
      expect(
        tester
            .widget<TextField>(input('topology-context-percent'))
            .controller!
            .text,
        '80',
      );
      await tester.enterText(input('topology-context-budget'), '32000');
      await tester.enterText(input('topology-context-percent'), '70');
      await tester.enterText(
        find.byKey(const ValueKey('topology-task-input')),
        'Context child task',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('topology-create-confirm')),
      );
      await tester.tap(find.byKey(const ValueKey('topology-create-confirm')));
      await tick(tester);
      final child = workspaces.sessions.last;
      expect(child.parentId, root.id);
      expect(child.assistant.contextBudgetTokens, 32000);
      expect(child.assistant.contextCompactionPercent, 70);
      expect(root.assistant.contextBudgetTokens, 64000);
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
          await File('${Directory.systemTemp.path}/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
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
            AppLocalizations.of(tester.element(find.byType(TaskTopologyPage)))
                .settingsCancel,
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
        find.descendant(
          of: canvas,
          matching: find.byKey(const ValueKey('topology-connections-paint')),
        ),
      );
      final dynamic painter = customPaint.painter;
      final edge = workspaces.connections.singleWhere(
        (edge) => edge.fromId == child.id && edge.toId == nested.id,
      );
      final routes = painter.routes as Map<String, TaskTopologyConnection>;
      final route = routes[edge.id]!;
      final parentPosition = position(child.id);
      final nestedPosition = position(nested.id);
      final expected = TaskTopologyConnection.between(
        Rect.fromLTWH(
          parentPosition.left!,
          parentPosition.top!,
          parentPosition.width!,
          parentPosition.height!,
        ),
        Rect.fromLTWH(
          nestedPosition.left!,
          nestedPosition.top!,
          nestedPosition.width!,
          nestedPosition.height!,
        ),
      );
      expect(route.start, expected.start);
      expect(route.end, expected.end);
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

class _LookupCountingWorkspaceProvider extends AiWorkspaceProvider {
  _LookupCountingWorkspaceProvider(super.main);

  int findCalls = 0;

  @override
  AiAgentWorkspace? find(String? id) {
    findCalls++;
    return super.find(id);
  }
}
