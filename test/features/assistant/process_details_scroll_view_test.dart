import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/process_details_scroll_view.dart';

Widget host(
  int count, {
  bool active = true,
  bool reducedMotion = false,
  Widget? nested,
}) => MaterialApp(
  scrollBehavior: const AppScrollBehavior(),
  theme: ThemeData(
    platform: TargetPlatform.windows,
    scrollbarTheme: const ScrollbarThemeData(
      crossAxisMargin: 6,
      thumbVisibility: WidgetStatePropertyAll(true),
    ),
  ),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 180,
          child: ProcessDetailsScrollView(
            active: active,
            child: Column(
              children: [
                if (nested != null) nested,
                for (var i = 0; i < count; i++)
                  SizedBox(height: 24, child: Text('Progress step $i')),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

Finder get details => find.byKey(const ValueKey('ai-process-details-scroll'));
ScrollController controller(WidgetTester tester) =>
    tester.widget<SingleChildScrollView>(details).controller!;

void main() {
  for (final reducedMotion in [false, true]) {
    testWidgets('details follow growth and final status ($reducedMotion)', (
      tester,
    ) async {
      await tester.pumpWidget(host(3, reducedMotion: reducedMotion));
      await tester.pumpAndSettle();
      expect(controller(tester).offset, 0);
      await tester.pumpWidget(host(24, reducedMotion: reducedMotion));
      await tester.pumpAndSettle();
      expect(controller(tester).position.extentAfter, closeTo(0, 1));
      await tester.pumpWidget(host(30, reducedMotion: reducedMotion));
      await tester.pumpAndSettle();
      expect(controller(tester).position.extentAfter, closeTo(0, 1));
      await tester.pumpWidget(
        host(31, active: false, reducedMotion: reducedMotion),
      );
      await tester.pumpAndSettle();
      expect(controller(tester).position.extentAfter, closeTo(0, 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'upward smooth wheel cancels pending following and returning to bottom resumes it',
    (tester) async {
      await tester.pumpWidget(host(24));
      await tester.pumpAndSettle();
      final scroll = controller(tester);
      await tester.pumpWidget(host(32));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: tester.getCenter(details));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(details),
          scrollDelta: const Offset(0, -130),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, greaterThan(100));
      final readingOffset = scroll.offset;
      await tester.pumpWidget(host(40));
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(readingOffset, 1));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(details),
          scrollDelta: const Offset(0, 4000),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, closeTo(0, 1));
      await tester.pumpWidget(host(48));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, closeTo(0, 1));
      await pointer.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dragging the details thumb upwards pauses following', (
    tester,
  ) async {
    await tester.pumpWidget(host(40));
    await tester.pumpAndSettle();
    final scroll = controller(tester);
    final rect = tester.getRect(details);
    await tester.dragFrom(
      Offset(rect.right - 10, rect.bottom - 12),
      const Offset(0, -65),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, greaterThan(100));
    final readingOffset = scroll.offset;
    await tester.pumpWidget(host(48));
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(readingOffset, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested scroll does not pause the details follower', (
    tester,
  ) async {
    final nestedController = ScrollController();
    addTearDown(nestedController.dispose);
    Widget nested() => SizedBox(
      height: 90,
      child: SingleChildScrollView(
        key: const ValueKey('nested-code-scroll'),
        controller: nestedController,
        child: const SizedBox(height: 800, width: 200),
      ),
    );
    await tester.pumpWidget(host(0, nested: nested()));
    await tester.pumpAndSettle();
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final point = tester.getCenter(
      find.byKey(const ValueKey('nested-code-scroll')),
    );
    await pointer.addPointer(location: point);
    nestedController.jumpTo(300);
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, -100)),
    );
    await tester.pumpAndSettle();
    expect(nestedController.offset, lessThan(300));
    await tester.pumpWidget(host(24, nested: nested()));
    await tester.pumpAndSettle();
    expect(controller(tester).position.extentAfter, closeTo(0, 1));
    await pointer.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed history opens at the top and does not start following',
    (tester) async {
      await tester.pumpWidget(host(24, active: false));
      await tester.pumpAndSettle();
      expect(controller(tester).offset, 0);
      await tester.pumpWidget(host(32, active: false));
      await tester.pumpAndSettle();
      expect(controller(tester).offset, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing while following does not leave pending callbacks', (
    tester,
  ) async {
    await tester.pumpWidget(host(24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
