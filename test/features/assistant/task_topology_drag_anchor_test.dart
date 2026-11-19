import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/pages/task_topology_page.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_connection_layer.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_node_layer.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

void main() {
  late ThemeProvider theme;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late LanguageProvider language;
  late AssistantTestScope scope;
  late AiWorkspaceProvider workspace;
  late List<AiAgentWorkspace> cards;

  setUp(() async {
    theme = ThemeProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    language = LanguageProvider();
    scope = await createAssistantTestScope(
      theme: theme,
      shell: shell,
      splitView: split,
      language: language,
    );
    await scope.provider.initialized;
    await scope.provider.saveService(
      name: 'Local model',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['test-model'],
      apiKey: 'test-key',
    );
    workspace = AiWorkspaceProvider(scope.provider);
    cards = [
      for (final title in ['Grabbed', 'Selected', 'Stationary'])
        await workspace.create(
          title: title,
          task: title,
          startImmediately: false,
        ),
    ];
  });

  tearDown(() {
    workspace.dispose();
    scope.dispose();
    theme.dispose();
    shell.dispose();
    split.dispose();
    language.dispose();
  });

  for (final allSelected in [true, false]) {
    testWidgets(
      'large drag preview commits once and keeps edge endpoints, all: $allSelected',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.runAsync(() async {
          for (var index = 3; index < 75; index++) {
            cards.add(
              await workspace.create(
                title: 'Card $index',
                task: 'Card $index',
                startImmediately: false,
              ),
            );
          }
        });
        final edge = workspace.connectTasks(cards[0].id, cards[2].id);
        final original = {
          cards[0].id: [140.0, 170.0],
          cards[1].id: [510.0, 170.0],
          cards[2].id: [860.0, 170.0],
          for (var index = 3; index < 9; index++)
            cards[index].id: [
              140.0 + (index - 3) % 3 * 360,
              400.0 + (index - 3) ~/ 3 * 205,
            ],
          for (var index = 9; index < cards.length; index++)
            cards[index].id: [3000.0 + index * 300, 180.0],
        };
        workspace.updateCanvasPositions(original);
        final canvasImage = GlobalKey();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: workspace),
            ],
            child: MaterialApp(
              localizationsDelegates: appLocalizationDelegates,
              home: Scaffold(
                body: RepaintBoundary(
                  key: canvasImage,
                  child: const TaskTopologyPage(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final viewer = tester.widget<InteractiveViewer>(
          find.byKey(const ValueKey('task-topology-canvas')),
        );
        viewer.transformationController!.value = Matrix4.identity();
        await tester.pumpAndSettle();
        Finder card(int index) =>
            find.byKey(ValueKey('topology-node-${cards[index].id}'));
        await tester.tap(card(0));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        if (!allSelected) await tester.tap(card(2));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        const grab = Offset(92, 60);
        final index = tester
            .widget<TaskTopologyNodeLayer>(find.byType(TaskTopologyNodeLayer))
            .index;
        final originalBounds = index[cards[0].id];
        final swatch = Offset(tester.getSize(card(0)).width - 14, 23);
        Future<int> renderedPixel(Offset global) async {
          final boundary =
              canvasImage.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final local = boundary.globalToLocal(global);
          return (await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final pixels = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              return pixels.getUint32(
                (local.dy.floor() * image.width + local.dx.floor()) * 4,
              );
            } finally {
              image.dispose();
            }
          }))!;
        }

        final sample = tester.getTopLeft(card(0)) + swatch;
        final cardColor = await renderedPixel(sample);
        expect(
          await renderedPixel(sample + const Offset(52, 33)),
          isNot(cardColor),
        );
        var pointer = tester.getTopLeft(card(0)) + grab;
        final drag = await tester.startGesture(
          pointer,
          kind: PointerDeviceKind.mouse,
        );
        pointer += const Offset(52, 33);
        await drag.moveTo(pointer);
        await tester.pump();
        expect(index[cards[0].id], originalBounds);
        expect(
          await renderedPixel(tester.getTopLeft(card(0)) + swatch),
          cardColor,
        );
        void checkAnchorAndEdge() {
          expect(
            (tester.getTopLeft(card(0)) + grab - pointer).distance,
            lessThan(.001),
          );
          final paint = find.byKey(
            const ValueKey('topology-connections-paint'),
          );
          final box = tester.renderObject<RenderBox>(paint);
          final painter =
              tester.widget<CustomPaint>(paint).painter!
                  as TaskTopologyConnectionsPainter;
          final route = painter.routes[edge.id]!;
          expect(
            (box.localToGlobal(route.start) -
                    tester.getRect(card(0)).centerRight)
                .distance,
            lessThan(.001),
          );
          expect(
            (box.localToGlobal(route.end) - tester.getRect(card(2)).centerLeft)
                .distance,
            lessThan(.001),
          );
        }

        checkAnchorAndEdge();
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: pointer,
            kind: PointerDeviceKind.mouse,
            scrollDelta: const Offset(0, -240),
          ),
        );
        await tester.pump();
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          checkAnchorAndEdge();
        }
        expect(workspace.canvasPositions, original);
        expect(card(74), findsNothing);
        await drag.up();
        await tester.pumpAndSettle();
        expect(
          workspace.canvasPositions[cards.last.id],
          isNot(original[cards.last.id]),
        );
        final after = Map.of(workspace.canvasPositions);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(workspace.canvasPositions, original);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(workspace.canvasPositions, after);
        await tester.pump(const Duration(milliseconds: 501));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'wheel pan and zoom keep a dragged group at the pointer, reduced motion $reducedMotion',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final original = {
          cards[0].id: [55.0, 65.0],
          cards[1].id: [435.0, 105.0],
          cards[2].id: [815.0, 205.0],
        };
        workspace.updateCanvasPositions(original);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: workspace),
            ],
            child: MaterialApp(
              localizationsDelegates: appLocalizationDelegates,
              home: Scaffold(
                body: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: reducedMotion),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 108, top: 48),
                      child: TaskTopologyPage(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controller = tester
            .widget<InteractiveViewer>(
              find.byKey(const ValueKey('task-topology-canvas')),
            )
            .transformationController!;
        const scale = .8;
        controller.value = Matrix4.translationValues(105, 180, 0)
          ..scaleByDouble(scale, scale, 1, 1);
        await tester.pumpAndSettle();
        Finder card(int index) =>
            find.byKey(ValueKey('topology-node-${cards[index].id}'));
        await tester.tap(card(0));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(card(1));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        const grabOffset = Offset(101, 56);
        var pointer = tester.getTopLeft(card(0)) + grabOffset * scale;
        final drag = await tester.startGesture(
          pointer,
          kind: PointerDeviceKind.mouse,
        );

        void checkAnchor() {
          final currentScale = controller.value.entry(0, 0);
          final first = tester.getTopLeft(card(0));
          expect(
            (first + grabOffset * currentScale - pointer).distance,
            lessThan(.001),
            reason: 'the grabbed point stays under the mouse',
          );
          expect(
            (tester.getTopLeft(card(1)) -
                    first -
                    const Offset(380, 40) * currentScale)
                .distance,
            lessThan(.001),
            reason: 'selected cards retain their scene spacing',
          );
        }

        void wheel(Offset delta) => tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: pointer,
            kind: PointerDeviceKind.mouse,
            scrollDelta: delta,
          ),
        );

        pointer += const Offset(45, 20);
        await drag.moveTo(pointer);
        await tester.pump();
        checkAnchor();
        final stationary = tester.getTopLeft(card(2));
        wheel(const Offset(0, -180));
        await tester.pump();
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          checkAnchor();
        }
        expect(
          (tester.getTopLeft(card(2)) - stationary).dy,
          closeTo(180, .001),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        wheel(const Offset(0, 41));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        checkAnchor();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        wheel(const Offset(0, -70));
        await tester.pump();
        for (var frame = 0; frame < 3; frame++) {
          pointer += const Offset(14, -9);
          await drag.moveTo(pointer);
          await tester.pump(const Duration(milliseconds: 50));
          checkAnchor();
        }
        expect(controller.value.entry(0, 0), greaterThan(scale));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(workspace.canvasPositions, original);
        await drag.up();
        await tester.pumpAndSettle();
        final dropped = Map.of(workspace.canvasPositions);
        expect(dropped, isNot(original));
        wheel(const Offset(0, 32));
        await tester.pumpAndSettle();
        expect(workspace.canvasPositions, dropped);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
