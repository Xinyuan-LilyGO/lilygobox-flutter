import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/widgets/window_frame.dart';
import 'package:lilygobox/app/bootstrap/window_bootstrap.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/pages/task_topology_page.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';

import '../test/features/assistant/assistant_test_scope.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile workflow panning, selection and animated zoom', (
    tester,
  ) async {
    await configureDesktopWindow();
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
    );
    await scope.provider.initialized;
    final service = await scope.provider.saveService(
      name: 'Benchmark',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.invalid/v1',
      models: ['gpt-6.1-sol'],
      apiKey: 'benchmark-placeholder',
    );
    final workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
    final root = await workspaces.create(
      title: 'Workflow benchmark',
      task: 'No network request is made.',
      kind: AiWorkspaceKind.primary,
      serviceId: service,
      model: 'gpt-6.1-sol',
      startImmediately: false,
    );
    for (var i = 0; i < 24; i++) {
      await workspaces.create(
        title: 'Agent $i',
        task: 'Local synthetic performance fixture',
        parentId: root.id,
        serviceId: service,
        model: 'gpt-6.1-sol',
        startImmediately: false,
      );
    }
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
          ChangeNotifierProvider<AiWorkspaceProvider>.value(value: workspaces),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationDelegates,
          home: AppWindowFrame(
            theme: theme.themeData,
            isMaximized: false,
            child: const Scaffold(body: TaskTopologyPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topology-auto-layout')));
    await tester.pumpAndSettle();
    final canvas = find.byType(InteractiveViewer);
    final point = tester.getTopLeft(canvas) + const Offset(100, 100);
    Future<void> frame() async {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await tester.pump();
    }

    await binding.watchPerformance(() async {
      final pan = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      for (var i = 0; i < 50; i++) {
        await pan.moveBy(Offset(i < 25 ? 3 : -3, 1));
        await frame();
      }
      await pan.up();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      for (var i = 0; i < 24; i++) {
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: point,
            scrollDelta: Offset(0, i < 12 ? -24 : 24),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await frame();
      }
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await tester.pumpAndSettle();
      final box = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 40; i++) {
        await box.moveBy(const Offset(4, 3));
        await frame();
      }
      await box.up();
      await tester.pumpAndSettle();
    }, reportKey: 'workflow');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await workspaces.flush();
    workspaces.dispose();
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
    navigation.dispose();
  });
}
