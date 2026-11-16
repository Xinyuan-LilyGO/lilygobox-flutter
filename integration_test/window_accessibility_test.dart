import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/tray/menu_app.dart';
import 'package:lilygobox/app/widgets/title_bar.dart';
import 'package:lilygobox/app/widgets/window_page_stack.dart';
import 'package:lilygobox/core/window/provider.dart';
import 'package:lilygobox/main.dart' as app;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

@pragma('vm:entry-point')
void trayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrayMenuApp());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'window transitions preserve accessibility and application layout',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        debugPrint('WINDOW_STEP: startup');
        await tester.runAsync(app.main);
        Future<void> settle() async {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 650)),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        }

        await settle();
        debugPrint('WINDOW_STEP: initial app');
        if (const bool.fromEnvironment('WINDOW_DUMP')) {
          debugDumpSemanticsTree();
        }
        await settle();
        final context = tester.element(find.byType(AppTitleBar));
        final windows = context.read<WindowProvider>();
        final navigation = context.read<AppNavigationProvider>();
        final window = WindowManager.instance.getCurrent()!;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer();
        const cycles = int.fromEnvironment('WINDOW_CYCLES', defaultValue: 12);
        for (var i = 0; i < cycles; i++) {
          debugPrint('WINDOW_STEP: page $i');
          navigation.setPage(i.isEven ? AppPage.settings : AppPage.home);
          await settle();
          if (i == 0 && const bool.fromEnvironment('WINDOW_DUMP')) {
            debugDumpSemanticsTree();
          }
          debugPrint('WINDOW_STEP: hover $i');
          final controls = find.byType(AppTitleBarControls);
          await mouse.moveTo(tester.getCenter(controls));
          await settle();
          debugPrint('WINDOW_STEP: toggle $i');
          if (i == 0 && const bool.fromEnvironment('WINDOW_DUMP')) {
            debugDumpSemanticsTree();
          }
          if (i.isEven) {
            await tester.tapAt(
              tester.getCenter(find.byType(AppTitleBarControls)),
            );
          } else {
            await tester.runAsync(windows.handleMaximizeRestore);
          }
          await settle();
          expect(window.isMaximized, isTrue);
          if (i.isEven) {
            await tester.tapAt(
              tester.getCenter(find.byType(AppTitleBarControls)),
            );
          } else {
            await tester.runAsync(windows.handleMaximizeRestore);
          }
          await settle();
          expect(window.isMaximized, isFalse);
          if (i % 4 == 0) {
            final dialog = showDialog<void>(
              context: tester.element(find.byType(WindowPageStack)),
              builder: (_) => const AlertDialog(
                content: Text('Window accessibility regression'),
              ),
            );
            unawaited(dialog);
            await settle();
            await tester.tapAt(
              tester.getCenter(find.byType(AppTitleBarControls)),
            );
            await settle();
            expect(window.isMaximized, isTrue);
            await tester.tapAt(
              tester.getCenter(find.byType(AppTitleBarControls)),
            );
            await settle();
            expect(window.isMaximized, isFalse);
            Navigator.of(
              tester.element(find.text('Window accessibility regression')),
            ).pop();
            await dialog;
            await settle();
          }
          await tester.runAsync(windows.minimize);
          await settle();
          await tester.runAsync(windows.show);
          await settle();
          expect(window.isMinimized, isFalse);
          debugPrint('WINDOW_ACCESSIBILITY_CYCLE: $i');
        }
        await mouse.removePointer();
      } finally {
        semantics.dispose();
      }
    },
  );
}
