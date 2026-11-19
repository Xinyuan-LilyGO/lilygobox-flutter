import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/tray/menu_app.dart';
import 'package:lilygobox/app/widgets/title_bar.dart';
import 'package:lilygobox/app/widgets/window_page_stack.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/title_bar_icon_button.dart';
import 'package:lilygobox/core/window/provider.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/recycle_bin_dialog.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/main.dart' as app;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

@pragma('vm:entry-point')
void trayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrayMenuApp());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('recycle bin preserves native accessibility across routes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.runAsync(app.main);
      Future<void> settle() async {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 750)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      await settle();
      await settle();
      final context = tester.element(find.byType(AppTitleBar));
      final navigation = context.read<AppNavigationProvider>();
      final windows = context.read<WindowProvider>();
      final workspaces = context.read<AiWorkspaceProvider>();
      final sessions = workspaces.sessions.toList()
        ..sort((first, second) {
          int contentLength(AiAgentWorkspace session) => session
              .assistant
              .messages
              .fold(0, (total, message) => total + message.content.length);
          return contentLength(second).compareTo(contentLength(first));
        });
      if (sessions.isNotEmpty) {
        final open = find.byKey(ValueKey('topology-open-${sessions.first.id}'));
        tester.widget<TitleBarIconButton>(open).onPressed!();
        await settle();
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      const cycles = int.fromEnvironment('WINDOW_CYCLES', defaultValue: 12);
      for (var cycle = 0; cycle < cycles; cycle++) {
        debugPrint('RECYCLE_STEP: open $cycle');
        navigation.setPage(AppPage.settings);
        await settle();
        await mouse.moveTo(tester.getCenter(find.byType(AppTitleBarControls)));
        await settle();
        final dialog = showAgentRecycleBin(
          tester.element(find.byType(WindowPageStack)),
          context.read<ThemeProvider>().themeData,
        );
        unawaited(dialog);
        await settle();
        final list = find.byKey(const ValueKey('recycle-agent-list-scroll'));
        expect(list, findsOneWidget);
        await tester.drag(list, const Offset(0, -180));
        await settle();
        await tester.runAsync(windows.handleMaximizeRestore);
        await settle();
        Navigator.of(tester.element(list)).pop();
        await dialog;
        await settle();
        navigation.setPage(AppPage.home);
        await settle();
        debugPrint('RECYCLE_ACCESSIBILITY_CYCLE: $cycle');
      }
      await mouse.removePointer();
    } finally {
      semantics.dispose();
    }
  });
}
