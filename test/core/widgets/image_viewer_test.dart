/*
 * @Description: 验证原图查看入口、遮罩关闭和 Ctrl 滚轮缩放。
 */
import 'package:lilygobox/core/l10n/delegates.dart';

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/context_menu/text_selection_menu.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/image_clipboard_menu.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAYAAACbU/80AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAABFSURBVEhLxcghAQAwDASx+jf9MxB8AyG5u+0vZolZYpaYJWaJWWKWmCVmiVlilpglZolZYpaYJWaJWWKWmCVmiVliVrYH5+n6TNVuN3kAAAAASUVORK5CYII=',
  );
  Widget app({bool reduced = false, bool selectable = false}) =>
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final image = ImageClipboardMenu(
                  bytes: bytes,
                  theme: context.read<ThemeProvider>().themeData,
                  child: const SizedBox(
                    width: 100,
                    height: 80,
                    child: ColoredBox(
                      key: ValueKey('thumbnail'),
                      color: Colors.grey,
                    ),
                  ),
                );
                if (!selectable) return Center(child: image);
                return SelectionArea(
                  contextMenuBuilder: AppTextSelectionMenu.buildRegion,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [image, const Text('Message text')],
                    ),
                  ),
                );
              },
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
    expect(find.text('Save image as'), findsOneWidget);
    await tester.tap(find.text('View original image'));
    await tester.pumpAndSettle();
    expect(viewport, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(viewport, findsNothing);
  });

  testWidgets('a held right click on an image opens only the image menu', (
    tester,
  ) async {
    await tester.pumpWidget(app(selectable: true));
    final text = find.text('Message text');
    final selectAll = find.text('Select all');
    final saveImage = find.text('Save image as');
    await tester.tap(
      text,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(selectAll, findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getTopRight(thumbnail) + const Offset(-10, 12),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(selectAll, findsNothing);
    expect(saveImage, findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selectAll, findsNothing);
    expect(saveImage, findsOneWidget);
    expect(find.text('Copy image'), findsOneWidget);

    await tester.tap(
      text,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(selectAll, findsOneWidget);
    expect(saveImage, findsNothing);
  });
}
