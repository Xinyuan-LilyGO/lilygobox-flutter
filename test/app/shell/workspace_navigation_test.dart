import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/pages/page.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/retained_page_stack.dart';
import 'package:lilygobox/app/shell/pages/home_page_content.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/pages/task_topology_page.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../features/assistant/assistant_test_scope.dart';

void main() {
  test('sidebar section switching preserves the last device detail', () {
    final shell = AppShellProvider();
    addTearDown(shell.dispose);
    shell.updateSelectedIndex(2);
    shell.openDeviceSection();
    expect(shell.selectedIndex, 2);
    shell.openAssistant();
    expect(shell.selectedIndex, 0);
    shell.openDeviceSection();
    expect(shell.selectedIndex, 2);
    shell.openDeviceManagement();
    expect(shell.selectedIndex, 0);
    expect(shell.deviceManagementSelected, isTrue);
    shell.openAssistant();
    shell.openDeviceSection();
    expect(shell.selectedIndex, 0);
    expect(shell.deviceManagementSelected, isTrue);
  });
  testWidgets(
    'homepage retains canvas and chat state across sidebar navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1150, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shell = AppShellProvider();
      final devices = DeviceManagerProvider();
      final theme = ThemeProvider();
      final split = SplitViewProvider();
      final navigation = AppNavigationProvider();
      final language = LanguageProvider();
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
      );
      await scope.provider.initialized;
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test-model'],
        apiKey: 'test-key',
      );
      final workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      addTearDown(() {
        workspaces.dispose();
        scope.dispose();
        shell.dispose();
        devices.dispose();
        theme.dispose();
        split.dispose();
        navigation.dispose();
        language.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: shell),
            ChangeNotifierProvider.value(value: devices),
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: split),
            ChangeNotifierProvider.value(value: navigation),
            ChangeNotifierProvider.value(value: language),
            ChangeNotifierProvider<AiAssistantProvider>.value(
              value: scope.provider,
            ),
            ChangeNotifierProvider.value(value: workspaces),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: appLocalizationDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AppShell()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sidebar-agent-workspaces')),
        findsNothing,
      );
      expect(find.text('智能体工作流'), findsOneWidget);
      expect(find.text('智能体'), findsOneWidget);
      expect(find.text('创建主智能体'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('sidebar-devices')));
      await tester.pumpAndSettle();
      expect(shell.deviceManagementSelected, isTrue);
      await tester.tap(find.byKey(const ValueKey('sidebar-home')));
      await tester.pumpAndSettle();
      expect(shell.deviceManagementSelected, isFalse);
      expect(find.text('智能体工作流'), findsOneWidget);
      expect(find.text('智能体'), findsOneWidget);
      await tester.runAsync(() async {
        await workspaces.create(
          title: 'Saved agent',
          task: 'Keep context',
          startImmediately: false,
        );
      });
      await tester.pumpAndSettle();
      final agent = workspaces.sessions.single;
      await tester.binding.setSurfaceSize(const Size(2560, 1440));
      await tester.pumpAndSettle();
      final topology = find.byType(TaskTopologyPage);
      final canvas = find.byKey(const ValueKey('task-topology-canvas'));
      final card = find.byKey(ValueKey('topology-node-${agent.id}'));
      final controller = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final initialTransform = controller.value.clone();
      final blank = tester.getTopLeft(canvas) + const Offset(8, 120);
      await tester.tapAt(blank);
      await tester.pumpAndSettle();
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: blank,
          scrollDelta: const Offset(0, 80),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        controller.value.entry(1, 3),
        lessThan(initialTransform.entry(1, 3)),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: blank,
          scrollDelta: const Offset(0, -40),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        controller.value.entry(0, 0),
        greaterThan(initialTransform.entry(0, 0)),
      );
      await tester.tap(card);
      await tester.pumpAndSettle();
      final topologyState = tester.state(topology);
      final canvasElement = tester.element(canvas);
      final retainedTransform = controller.value.clone();
      final agentIds = workspaces.sessions
          .map((session) => session.id)
          .toList();
      expect(workspaces.selectedId, agent.id);
      expect(workspaces.activeConversationId, isNull);

      for (final hiddenSize in [
        const Size(1920, 1080),
        const Size(2560, 1440),
      ]) {
        final previousSize = tester.getSize(canvas);
        await tester.tap(find.byKey(const ValueKey('sidebar-devices')));
        await tester.pumpAndSettle();
        expect(canvas, findsNothing);
        expect(topologyState.mounted, isTrue);
        expect(controller.value, retainedTransform);
        expect(workspaces.activeConversationId, isNull);
        await tester.binding.setSurfaceSize(hiddenSize);
        await tester.pumpAndSettle();
        expect(controller.value, retainedTransform);
        await tester.tap(find.byKey(const ValueKey('sidebar-home')));
        await tester.pumpAndSettle();
        expect(tester.state(topology), same(topologyState));
        expect(tester.element(canvas), same(canvasElement));
        expect(
          tester.widget<InteractiveViewer>(canvas).transformationController,
          same(controller),
        );
        expect(controller.value, retainedTransform);
        expect(tester.getSize(canvas), isNot(previousSize));
        expect(workspaces.selectedId, agent.id);
        expect(workspaces.activeConversationId, isNull);
        expect(workspaces.sessions.map((session) => session.id), agentIds);
        expect(workspaces.find(agent.id), same(agent));
        final decoration =
            tester.widget<AnimatedContainer>(card).foregroundDecoration!
                as BoxDecoration;
        expect((decoration.border! as Border).top.color.a, greaterThan(0));
      }

      await tester.tap(find.byKey(ValueKey('topology-open-${agent.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      expect(workspaces.activeConversationId, agent.id);
      await tester.tap(find.byKey(const ValueKey('sidebar-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      expect(workspaces.activeConversationId, agent.id);
      expect(workspaces.find(agent.id), same(agent));
      final input = find.byKey(const ValueKey('ai-message-input'));
      await tester.enterText(input, 'Unsent draft');
      await tester.pumpAndSettle();
      final inputElement = tester.element(input);
      final shellStack = find.byType(RetainedPageStack).first;
      final fade = find
          .descendant(of: shellStack, matching: find.byType(FadeTransition))
          .first;

      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.byKey(const ValueKey('sidebar-devices')));
        await tester.pump();
        expect(find.byType(HomePageContent), findsOneWidget);
        expect(input, findsNothing);
        expect(workspaces.activeConversationId, isNull);
        expect(tester.widget<FadeTransition>(fade).opacity.value, 1);

        await tester.tap(find.byKey(const ValueKey('sidebar-home')));
        await tester.pump();
        expect(find.byType(HomePageContent), findsNothing);
        expect(tester.element(input), same(inputElement));
        expect(find.text('Unsent draft'), findsOneWidget);
        expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
        expect(workspaces.activeConversationId, agent.id);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
