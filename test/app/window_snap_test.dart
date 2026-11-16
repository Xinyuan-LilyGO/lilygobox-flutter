import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/widgets/window_frame.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:window_manager/window_manager.dart';

class _Window implements Window {
  FutureOr<void> Function(WindowEvent)? listener;
  @override
  int addListener(FutureOr<void> Function(WindowEvent) callback) {
    listener = callback;
    return 1;
  }

  @override
  bool removeListener(int id) {
    listener = null;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('snapping removes frame margins and restoring brings them back', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var snapped = false;
    final window = _Window();
    const channel = MethodChannel('lilygobox/window_layout');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'isSnapped');
      return snapped;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppWindowFrame(
          window: window,
          theme: MaterialPalette.create(ThemeType.dark),
          isMaximized: false,
          child: const SizedBox.expand(key: ValueKey('content')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final content = find.byKey(const ValueKey('content'));
    expect(tester.getTopLeft(content), const Offset(10, 10));
    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).clipBehavior,
      Clip.antiAliasWithSaveLayer,
    );

    snapped = true;
    await window.listener!(
      WindowResizedEvent(windowId: 1, newSize: const Size(800, 600).toNative()),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(content), Offset.zero);
    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).clipBehavior,
      Clip.hardEdge,
    );
    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
      BorderRadius.zero,
    );
    snapped = false;
    await window.listener!(
      WindowMovedEvent(windowId: 1, newPosition: Offset.zero.toNative()),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(content), const Offset(10, 10));
    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
      BorderRadius.circular(10),
    );
    // Windows may commit snapping after the last plugin move/resize event.
    // The native layout notification must update corners without another drag.
    Future<void> notifyLayout(bool snapped) async {
      final completed = Completer<void>();
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'lilygobox/window_layout',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('layoutChanged', snapped),
        ),
        (_) => completed.complete(),
      );
      await completed.future;
      await tester.pumpAndSettle();
    }

    await notifyLayout(true);
    expect(tester.getTopLeft(content), Offset.zero);
    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
      BorderRadius.zero,
    );
    await notifyLayout(false);
    expect(tester.getTopLeft(content), const Offset(10, 10));

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
