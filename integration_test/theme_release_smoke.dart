// Runs the real desktop application in release mode without a VM service.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:lilygobox/app/tray/menu_app.dart';
import 'package:lilygobox/app/widgets/title_bar.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/window/provider.dart';
import 'package:lilygobox/main.dart' as app;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

@pragma('vm:entry-point')
void trayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrayMenuApp());
}

Element? titleBar(Element element) {
  if (element.widget is AppTitleBar) return element;
  Element? result;
  element.visitChildren((child) => result ??= titleBar(child));
  return result;
}

Future<void> main() async {
  try {
    await app.main();
    Element? context;
    for (var attempt = 0; attempt < 100 && context == null; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (WidgetsBinding.instance.rootElement case final root?) {
        context = titleBar(root);
      }
    }
    if (context == null) throw StateError('Main application did not mount');
    final theme = context.read<ThemeProvider>();
    const tray = MethodChannel('lilygobox/tray');
    for (var i = 0; i < 20; i++) {
      theme.cycleTheme();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tray.invokeMethod<void>('openMenu');
      var ready = false;
      for (var attempt = 0; attempt < 100 && !ready; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        ready = await tray.invokeMethod<bool>('menuReady') ?? false;
      }
      if (!ready) throw StateError('Menu failed at iteration $i');
      await tray.invokeMethod<void>('dismissMenu');
    }
    await File('tmp/theme-release-result.json')
        .writeAsString(jsonEncode({'passed': true, 'iterations': 20}));
    await context.read<WindowProvider>().exit();
  } catch (error, stack) {
    await File('tmp/theme-release-result.json').writeAsString(
      jsonEncode({'passed': false, 'error': '$error', 'stack': '$stack'}),
    );
    exit(1);
  }
}
