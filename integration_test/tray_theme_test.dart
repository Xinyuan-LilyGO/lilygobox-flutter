import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/bootstrap/window_bootstrap.dart';
import 'package:lilygobox/app/tray/menu_app.dart';
import 'package:material_ui/material_ui.dart';

@pragma('vm:entry-point')
void trayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrayMenuApp());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native tray paints and survives repeated theme changes and reopen',
    (tester) async {
      const tray = MethodChannel('lilygobox/tray');
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Tray theme regression'))),
      );
      await configureDesktopWindow();
      Future<void> configure(String theme) => tray.invokeMethod('configure', {
        'show': 'Show',
        'exit': 'Exit',
        'theme': theme,
        'reduceMotion': false,
      });
      await configure('light');
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      for (var i = 0; i < 20; i++) {
        await configure(i.isEven ? 'dark' : 'light');
        await tray.invokeMethod<void>('openMenu');
        var ready = false;
        for (var attempt = 0; attempt < 100 && !ready; attempt++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          ready = await tray.invokeMethod<bool>('menuReady') ?? false;
        }
        expect(
          ready,
          isTrue,
          reason: 'The isolated menu must paint and stay alive',
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tray.invokeMethod<void>('dismissMenu');
      }
    },
  );
}
