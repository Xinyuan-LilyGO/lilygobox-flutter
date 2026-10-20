import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/widgets/window_frame.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  testWidgets('snapping removes frame margins and restoring brings them back', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var snapped = false;
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
          theme: MaterialPalette.create(ThemeType.dark),
          isMaximized: false,
          child: const SizedBox.expand(key: ValueKey('content')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final content = find.byKey(const ValueKey('content'));
    expect(tester.getTopLeft(content), const Offset(10, 10));
    final listener =
        tester.state(find.byType(AppWindowFrame)) as WindowListener;
    snapped = true;
    listener.onWindowResized();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(content), Offset.zero);
    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
      BorderRadius.zero,
    );
    snapped = false;
    listener.onWindowMoved();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(content), const Offset(10, 10));
    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
      BorderRadius.circular(10),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
