import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/pages/page.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
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
    'homepage shows topology without an extra global workspace entry',
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
      await tester.tap(find.byKey(ValueKey('topology-open-${agent.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      expect(workspaces.activeConversationId, agent.id);
      await tester.tap(find.byKey(const ValueKey('sidebar-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      expect(workspaces.activeConversationId, agent.id);
      expect(workspaces.find(agent.id), same(agent));
      // Switching sections preserves the active conversation.
      await tester.tap(find.byKey(const ValueKey('sidebar-devices')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sidebar-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
      expect(workspaces.activeConversationId, agent.id);
      expect(tester.takeException(), isNull);
    },
  );
}
