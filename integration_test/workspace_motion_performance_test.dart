import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/assistant/presentation/pages/task_topology_page.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_scrollbar.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/message_content.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/features/assistant/state/storage_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../test/features/assistant/assistant_test_scope.dart';
import 'fixtures/workspace_motion.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('measure maximized canvas and imported chat motion', (
    tester,
  ) async {
    final storage = AgentStorage(path: ':memory:');
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final split = SplitViewProvider();
    final navigation = AppNavigationProvider();
    final scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      storage: storage,
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await setMotionWindowMaximized(tester, true);
    final semantics = tester.ensureSemantics();
    final clock = Stopwatch()..start();
    final mode = Platform.environment['LILYGOBOX_MOTION_CASE'] ?? 'both';
    binding.reportData = {
      'physical_width': tester.view.physicalSize.width,
      'physical_height': tester.view.physicalSize.height,
      'refresh_rate': tester.view.display.refreshRate,
      'dpr': tester.view.devicePixelRatio,
      'maximized': true,
    };
    AiWorkspaceProvider? workspace;
    Widget app(
      Widget body,
      AiWorkspaceProvider graph,
      AiAssistantProvider assistant,
    ) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: language),
        ChangeNotifierProvider.value(value: shell),
        ChangeNotifierProvider.value(value: navigation),
        ChangeNotifierProvider.value(value: graph),
        ChangeNotifierProvider.value(value: assistant),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: ThemeData(
          platform: TargetPlatform.windows,
          colorScheme: theme.themeData.materialColors,
        ),
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(body: body),
      ),
    );
    Future<void> wheel(Offset point, double delta) => tester.sendEventToBinding(
      PointerScrollEvent(
        viewId: tester.view.viewId,
        timeStamp: clock.elapsed,
        kind: PointerDeviceKind.mouse,
        position: point,
        scrollDelta: Offset(0, delta),
      ),
    );
    Future<void> rest() async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await binding.endOfFrame;
    }

    try {
      if (mode != 'canvas') {
        final chat = workspace = AiWorkspaceProvider(scope.provider);
        await chat.initialized;
        final transfer = AgentStorageController(chat);
        try {
          await transfer.import(await transfer.inspect(motionPackagePath()));
        } finally {
          transfer.dispose();
        }
        final assistant = chat.sessions.single.assistant;
        expect(assistant.messages, hasLength(10000));
        await tester.pumpWidget(app(const AssistantPage(), chat, assistant));
        await rest();
        final viewport = find.byKey(const ValueKey('ai-message-scroll'));
        final scrollbar = tester.widget<ChatHistoryScrollbar>(
          find.byType(ChatHistoryScrollbar),
        );
        scrollbar.seek(.552);
        await rest();
        final point = tester.getCenter(viewport);
        final bodies = tester.elementList(find.byType(ChatMessageBody));
        final anchor = bodies.firstWhere((element) {
          final box = element.findRenderObject() as RenderBox;
          return (box.localToGlobal(Offset.zero).dy - point.dy).abs() < 115;
        });
        final anchorId = (anchor.widget as ChatMessageBody).message.id;
        final number = int.parse(anchorId.split('-').last);
        expect(number, inInclusiveRange(5500, 5540));
        final box = anchor.findRenderObject() as RenderBox;
        double anchorY() => box.localToGlobal(Offset.zero).dy;
        final trace = <List<num>>[];
        await binding.watchPerformance(() async {
          final start = anchorY();
          final time = Stopwatch()..start();
          await wheel(point, -100);
          while (time.elapsedMilliseconds < 350) {
            await binding.endOfFrame;
            trace.add([time.elapsedMicroseconds, anchorY() - start]);
          }
          expect(anchorY() - start, closeTo(100, 1));
          for (var index = 1; index < trace.length; index++) {
            expect(
              trace[index][1],
              greaterThanOrEqualTo(trace[index - 1][1] - .05),
            );
          }
        }, reportKey: 'chat_single_wheel');
        binding.reportData!['anchor_id'] = anchorId;
        binding.reportData!['chat_single_wheel_xy'] = trace;
        await binding.watchPerformance(() async {
          final start = scrollbar.readFraction();
          for (var event = 0; event < 48; event++) {
            await wheel(point, -65);
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
          await rest();
          final delta = start - scrollbar.readFraction();
          expect(delta, greaterThan(.001));
          binding.reportData!['chat_burst_messages_travelled'] = delta * 10000;
        }, reportKey: 'chat_burst');
        await tester.pumpWidget(const SizedBox.shrink());
        await chat.flush();
        chat.dispose();
        workspace = null;
      }
      if (mode != 'chat') {
        final count = int.parse(
          Platform.environment['LILYGOBOX_MOTION_CARDS'] ?? '3000',
        );
        await seedMotionCanvas(storage, count);
        final graph = workspace = AiWorkspaceProvider(scope.provider);
        await graph.initialized;
        expect(graph.sessions, hasLength(count));
        final cold = Stopwatch()..start();
        await tester.pumpWidget(
          app(const TaskTopologyPage(), graph, scope.provider),
        );
        final canvas = find.byType(InteractiveViewer);
        await waitForMotionCards(tester);
        binding.reportData!['canvas_first_frame_ms'] = cold.elapsedMilliseconds;
        final transform = tester
            .widget<InteractiveViewer>(canvas)
            .transformationController!;
        final point = tester.getCenter(canvas);
        for (final scale in [1.0, .25]) {
          transform.value = Matrix4.diagonal3Values(scale, scale, 1);
          await rest();
          final drawnCards = motionCanvasCards().evaluate().length;
          final key = 'canvas_${(scale * 100).round()}';
          expect(drawnCards, greaterThan(0));
          binding.reportData!['${key}_mounted'] = drawnCards;
          await binding.watchPerformance(() async {
            final start = transform.value.entry(1, 3);
            for (var event = 0; event < 24; event++) {
              await wheel(point, 55);
              await Future<void>.delayed(const Duration(milliseconds: 30));
            }
            await rest();
            final distance = (transform.value.entry(1, 3) - start).abs();
            expect(distance, greaterThan(1000));
            binding.reportData!['${key}_travel'] = distance;
          }, reportKey: key);
        }
        binding.reportData!['canvas_nodes'] = graph.sessions.length;
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      await workspace?.flush();
      workspace?.dispose();
      scope.dispose();
      await storage.close();
      theme.dispose();
      language.dispose();
      shell.dispose();
      split.dispose();
      navigation.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
