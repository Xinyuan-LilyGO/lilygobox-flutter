import 'dart:ffi';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/bootstrap/window_bootstrap.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('modal owner deactivation does not paint the system caption', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ColoredBox(color: Color(0xff6a35c1))),
    );
    await configureDesktopWindow();
    await tester.pumpAndSettle();
    final user = DynamicLibrary.open('user32.dll');
    final hwnd = user.lookupFunction<IntPtr Function(), int Function()>(
      'GetActiveWindow',
    )();
    expect(hwnd, isNot(0));
    final enable = user
        .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
          'EnableWindow',
        );
    final send = user
        .lookupFunction<
          IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
          int Function(int, int, int, int)
        >('SendMessageW');
    final getDc = user
        .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
          'GetWindowDC',
        );
    final release = user
        .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
          'ReleaseDC',
        );
    final pixel = DynamicLibrary.open('gdi32.dll')
        .lookupFunction<
          Uint32 Function(IntPtr, Int32, Int32),
          int Function(int, int, int)
        >('GetPixel');
    List<int> topEdge() {
      final dc = getDc(hwnd);
      try {
        return [for (var x = 40; x < 220; x += 10) pixel(dc, x, 12)];
      } finally {
        release(hwnd, dc);
      }
    }

    final before = topEdge();
    expect(before, everyElement(0x00c1356a));
    try {
      enable(hwnd, 0);
      send(
        hwnd,
        0x0086,
        0,
        0,
      ); // WM_NCACTIVATE, as for an owned system modal dialog.
      expect(
        topEdge(),
        before,
        reason:
            'Windows must not paint a classic caption over the custom frame',
      );
    } finally {
      enable(hwnd, 1);
      send(hwnd, 0x0086, 1, 0);
    }
    expect(topEdge(), before);
    for (final showDialog in <Future<Object?> Function()>[
      () => getSaveLocation(suggestedName: 'modal-frame-regression.txt'),
      openFile,
      getDirectoryPath,
    ]) {
      final inspection = Isolate.run(() => inspectFileDialog(hwnd));
      final result = await tester.runAsync(showDialog);
      expect(result, isNull);
      final modal = await inspection;
      expect(modal['dialog'], isTrue);
      expect(modal['enabled'], 0);
      expect(modal['pixels'], before);
      await tester.pumpAndSettle();
      expect(topEdge(), before);
    }
  });
}

Future<Map<String, Object>> inspectFileDialog(int hwnd) async {
  final user = DynamicLibrary.open('user32.dll');
  final popup = user
      .lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>(
        'GetWindow',
      );
  final enabled = user
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'IsWindowEnabled',
      );
  final post = user
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
        int Function(int, int, int, int)
      >('PostMessageW');
  final getDc = user.lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
    'GetWindowDC',
  );
  final release = user
      .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
        'ReleaseDC',
      );
  final pixel = DynamicLibrary.open('gdi32.dll')
      .lookupFunction<
        Uint32 Function(IntPtr, Int32, Int32),
        int Function(int, int, int)
      >('GetPixel');
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final dialog = popup(hwnd, 6);
    if (dialog == 0 || dialog == hwnd || enabled(hwnd) != 0) continue;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final dc = getDc(hwnd);
    final pixels = [for (var x = 40; x < 220; x += 10) pixel(dc, x, 12)];
    release(hwnd, dc);
    final state = enabled(hwnd);
    post(dialog, 0x0010, 0, 0);
    return {'dialog': true, 'enabled': state, 'pixels': pixels};
  }
  return {'dialog': false};
}
