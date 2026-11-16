import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/tray/menu_app.dart';
import 'package:lilygobox/app/widgets/title_bar.dart';
import 'package:lilygobox/core/theme/provider.dart';
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
  testWidgets(
    'production application survives repeated animated theme changes',
    (tester) async {
      await tester.runAsync(app.main);
      await tester.pump(const Duration(milliseconds: 300));
      final context = tester.element(find.byType(AppTitleBar));
      final themes = context.read<ThemeProvider>();
      final original = themes.currentTheme;
      const tray = MethodChannel('lilygobox/tray');
      for (var i = 0; i < 20; i++) {
        themes.cycleTheme();
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        await tray.invokeMethod<void>('openMenu');
        var ready = false;
        for (var attempt = 0; attempt < 100 && !ready; attempt++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          ready = await tray.invokeMethod<bool>('menuReady') ?? false;
        }
        expect(ready, isTrue);
        await tray.invokeMethod<void>('dismissMenu');
      }
      expect(themes.currentTheme, original);
    },
  );
}
