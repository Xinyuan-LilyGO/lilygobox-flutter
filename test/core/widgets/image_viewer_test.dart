/*
 * @Description: 验证原图查看入口、遮罩关闭和 Ctrl 滚轮缩放。
 * @Author: LILYGO_L
 * @Date: 2026-11-10 19:46:57
 * @LastEditTime: 2026-11-10 19:48:38
 */
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/image_clipboard_menu.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

void main() {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAYAAACbU/80AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAABFSURBVEhLxcghAQAwDASx+jf9MxB8AyG5u+0vZolZYpaYJWaJWWKWmCVmiVlilpglZolZYpaYJWaJWWKWmCVmiVliVrYH5+n6TNVuN3kAAAAASUVORK5CYII=',
  );
  Widget app({bool reduced = false}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ImageClipboardMenu(
              bytes: bytes,
              theme: ThemeProvider().themeData,
              child: const SizedBox(
                width: 100,
                height: 80,
                child: ColoredBox(
                  key: ValueKey('thumbnail'),
                  color: Colors.grey,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final viewport = find.byKey(const ValueKey('image-viewer-viewport'));
  final thumbnail = find.byKey(const ValueKey('thumbnail'));
  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(
      () => precacheImage(MemoryImage(bytes), tester.element(thumbnail)),
    );
    await tester.tap(thumbnail);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(thumbnail);
    await tester.pumpAndSettle();
    expect(viewport, findsOneWidget);
  }

  testWidgets(
    'double click opens original; image stays open; outside and close dismiss',
    (tester) async {
      await tester.pumpWidget(app());
      await open(tester);
      await tester.tapAt(tester.getCenter(viewport));
      await tester.pumpAndSettle();
      expect(viewport, findsOneWidget);
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();
      expect(viewport, findsNothing);
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('image-viewer-close')));
      await tester.pumpAndSettle();
      expect(viewport, findsNothing);
    },
  );

  testWidgets(
    'Ctrl wheel zooms with bounds; plain wheel does not zoom; Escape closes',
    (tester) async {
      await tester.pumpWidget(app());
      await open(tester);
      final transform = tester
          .widget<InteractiveViewer>(viewport)
          .transformationController!;
      Future<void> wheel(double delta) async {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(viewport),
            scrollDelta: Offset(0, delta),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pump();
      }

      await wheel(-200);
      expect(transform.value.getMaxScaleOnAxis(), 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await wheel(-200);
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
      await wheel(-10000);
      expect(transform.value.getMaxScaleOnAxis(), closeTo(8, .001));
      await wheel(10000);
      expect(transform.value.getMaxScaleOnAxis(), closeTo(.25, .001));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(viewport, findsNothing);
    },
  );

  testWidgets('right click menu opens original with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(app(reduced: true));
    await tester.tap(thumbnail, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View original image'));
    await tester.pumpAndSettle();
    expect(viewport, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(viewport, findsNothing);
  });
}
