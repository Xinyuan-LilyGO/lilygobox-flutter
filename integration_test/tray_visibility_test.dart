import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/bootstrap/window_bootstrap.dart';
import 'package:lilygobox/app/tray/menu_app.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

@pragma('vm:entry-point')
void trayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrayMenuApp());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'tray callback presents a visible menu and ignores incidental deactivation',
    (tester) async {
      const tray = MethodChannel('lilygobox/tray');
      final user = DynamicLibrary.open('user32.dll');
      final findWindow = user
          .lookupFunction<
            IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
            int Function(Pointer<Utf16>, Pointer<Utf16>)
          >('FindWindowW');
      final visible = user
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'IsWindowVisible',
          );
      final send = user
          .lookupFunction<
            IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
            int Function(int, int, int, int)
          >('SendMessageW');
      final layered = user
          .lookupFunction<
            Int32 Function(
              IntPtr,
              Pointer<Uint32>,
              Pointer<Uint8>,
              Pointer<Uint32>,
            ),
            int Function(int, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>)
          >('GetLayeredWindowAttributes');
      int window(String className, [String? title]) {
        final cls = className.toNativeUtf16();
        final name = title?.toNativeUtf16();
        try {
          return findWindow(cls, name ?? nullptr);
        } finally {
          calloc.free(cls);
          if (name != null) calloc.free(name);
        }
      }

      Future<void> delay(int ms) => tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Tray visibility regression')),
        ),
      );
      await configureDesktopWindow();
      final mainWindow = WindowManager.instance.getCurrent()!;
      await tray.invokeMethod<void>('configure', {
        'show': 'Show',
        'exit': 'Exit',
        'theme': 'dark',
        'reduceMotion': false,
      });
      await tester.pumpAndSettle();
      final main = window('FLUTTER_RUNNER_WIN32_WINDOW', 'LilygoBox');
      expect(main, isNot(0));
      for (var i = 0; i < 4; i++) {
        if (i == 2) expect(await tray.invokeMethod<bool>('hide'), isTrue);
        // Exercise the same native callback used by Explorer, including while
        // the main window is hidden; do not rely only on menuReady/painted.
        send(main, 0x8000 + 71, 1, 0x0205);
        var ready = false;
        for (var attempt = 0; attempt < 100 && !ready; attempt++) {
          await delay(100);
          ready = await tray.invokeMethod<bool>('menuReady') ?? false;
        }
        expect(ready, isTrue);
        final menu = window('LilygoBoxTrayMenu');
        expect(menu, isNot(0));
        await delay(350);
        expect(visible(menu), isNot(0));
        final alpha = calloc<Uint8>();
        final flags = calloc<Uint32>();
        try {
          expect(layered(menu, nullptr, alpha, flags), isNot(0));
          expect(alpha.value, 255, reason: 'Menu must be opaque after fade-in');
        } finally {
          calloc.free(alpha);
          calloc.free(flags);
        }
        // Explorer can emit these without the user leaving the tray context.
        // The watcher, not an unconditional message handler, decides dismissal.
        send(menu, 0x001c, 0, 0);
        send(menu, 0x0006, 0, 0);
        send(menu, 0x001f, 0, 0);
        await delay(300);
        expect(visible(menu), isNot(0));
        send(menu, 0x0010, 0, 0);
        await delay(100);
        expect(visible(menu), 0);
      }
      mainWindow.show();
      await delay(100);
      await tester.pump();
    },
  );
}
