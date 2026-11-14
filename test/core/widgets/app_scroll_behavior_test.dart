/*
 * @Description: 验证全局平滑滚轮、中键连续滚动、嵌套仲裁与退出清理。
 */
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';

/// 模拟鼠标滚轮输入，直接验证全局事件仲裁后的滚动结果。
Future<void> wheel(WidgetTester tester, Offset point, double delta) =>
    tester.sendEventToBinding(
      PointerScrollEvent(
        position: point,
        scrollDelta: Offset(0, delta),
        kind: PointerDeviceKind.mouse,
      ),
    );

void main() {
  group('AppScrollBehavior', () {
    testWidgets('should animate and accumulate wheel input', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: ListView(
            controller: controller,
            children: const [SizedBox(height: 3000)],
          ),
        ),
      );
      await wheel(tester, const Offset(200, 200), 120);
      expect(controller.offset, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(controller.offset, inExclusiveRange(0, 120));
      await wheel(tester, const Offset(200, 200), 120);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(240, .1));
    });

    testWidgets('should scroll the inner list and hand off at its boundary', (
      tester,
    ) async {
      final outer = ScrollController();
      final inner = ScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: ListView(
            controller: outer,
            children: [
              SizedBox(
                height: 200,
                child: ListView(
                  controller: inner,
                  children: const [SizedBox(height: 1000)],
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
      await wheel(tester, const Offset(100, 100), 120);
      await tester.pumpAndSettle();
      expect(inner.offset, closeTo(120, .1));
      expect(outer.offset, 0);
      inner.jumpTo(inner.position.maxScrollExtent);
      await tester.pump();
      await wheel(tester, const Offset(100, 100), 120);
      await tester.pumpAndSettle();
      expect(outer.offset, closeTo(120, .1));
    });

    for (final axis in [Axis.vertical, Axis.horizontal]) {
      for (final reverse in [false, true]) {
        testWidgets(
          'middle click scrolls $axis reverse=$reverse and Escape stops it',
          (tester) async {
            final controller = ScrollController(initialScrollOffset: 500);
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              MaterialApp(
                scrollBehavior: const AppScrollBehavior(),
                home: ListView(
                  controller: controller,
                  scrollDirection: axis,
                  reverse: reverse,
                  children: const [SizedBox(height: 5000, width: 5000)],
                ),
              ),
            );
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
              buttons: kMiddleMouseButton,
            );
            await mouse.addPointer(location: const Offset(200, 200));
            await mouse.down(const Offset(200, 200));
            await mouse.up();
            await tester.pump();
            expect(
              find.byKey(const ValueKey('app-middle-scroll-anchor')),
              findsOneWidget,
            );
            await mouse.moveTo(
              axis == Axis.vertical
                  ? const Offset(200, 206)
                  : const Offset(206, 200),
            );
            await tester.pump(const Duration(milliseconds: 100));
            expect(controller.offset, 500);
            await mouse.moveTo(
              axis == Axis.vertical
                  ? const Offset(200, 270)
                  : const Offset(270, 200),
            );
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(
              controller.offset,
              reverse ? lessThan(500) : greaterThan(500),
            );
            await mouse.moveTo(
              axis == Axis.vertical
                  ? const Offset(200, 130)
                  : const Offset(130, 200),
            );
            final beforeReverse = controller.offset;
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(
              controller.offset,
              reverse ? greaterThan(beforeReverse) : lessThan(beforeReverse),
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('app-middle-scroll-anchor')),
              findsNothing,
            );
            final stopped = controller.offset;
            await tester.pump(const Duration(milliseconds: 100));
            expect(controller.offset, stopped);
            await mouse.removePointer();
          },
        );
      }
    }

    testWidgets(
      'middle click chooses the deepest scrollable and clamps at its boundary',
      (tester) async {
        final outer = ScrollController();
        final inner = ScrollController();
        addTearDown(outer.dispose);
        addTearDown(inner.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: ListView(
              controller: outer,
              children: [
                SizedBox(
                  height: 200,
                  child: ScrollConfiguration(
                    behavior: const AppScrollBehavior(scrollbars: false),
                    child: ListView(
                      controller: inner,
                      children: const [SizedBox(height: 500)],
                    ),
                  ),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        );
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await mouse.addPointer(location: const Offset(100, 80));
        await mouse.down(const Offset(100, 80));
        await mouse.up();
        await tester.pump();
        await mouse.moveTo(const Offset(100, 400));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(inner.offset, inner.position.maxScrollExtent);
        expect(outer.offset, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await mouse.removePointer();
      },
    );

    testWidgets(
      'middle drag stops on release and clicking again exits click mode',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: ListView(
              controller: controller,
              children: const [SizedBox(height: 3000)],
            ),
          ),
        );
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await mouse.addPointer(location: const Offset(200, 200));
        await mouse.down(const Offset(200, 200));
        await tester.pump();
        await mouse.moveTo(const Offset(200, 300));
        await tester.pump(const Duration(milliseconds: 30));
        expect(controller.offset, greaterThan(0));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('app-middle-scroll-anchor')),
          findsNothing,
        );
        await mouse.down(const Offset(200, 200));
        await mouse.up();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('app-middle-scroll-anchor')),
          findsOneWidget,
        );
        await mouse.down(const Offset(200, 200));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('app-middle-scroll-anchor')),
          findsNothing,
        );
        await mouse.removePointer();
      },
    );

    testWidgets(
      'middle mode also works with reduced motion and cleans up on removal',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: ListView(
              controller: controller,
              children: const [SizedBox(height: 3000)],
            ),
          ),
        );
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await mouse.addPointer(location: const Offset(200, 200));
        await mouse.down(const Offset(200, 200));
        await mouse.up();
        await tester.pump();
        await mouse.moveTo(const Offset(200, 300));
        await tester.pump(const Duration(milliseconds: 30));
        expect(controller.offset, greaterThan(0));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('app-middle-scroll-anchor')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await mouse.removePointer();
      },
    );

    testWidgets('short and disabled lists do not enter middle mode', (
      tester,
    ) async {
      for (final physics in [null, const NeverScrollableScrollPhysics()]) {
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: ListView(
              physics: physics,
              children: [SizedBox(height: physics == null ? 20 : 3000)],
            ),
          ),
        );
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await mouse.addPointer(location: const Offset(200, 200));
        await mouse.down(const Offset(200, 200));
        await mouse.up();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('app-middle-scroll-anchor')),
          findsNothing,
        );
        await mouse.removePointer();
      }
    });

    for (final exit in ['wheel', 'click', 'inactive', 'key']) {
      testWidgets(
        'middle mode exits on $exit without triggering the covered controls',
        (tester) async {
          final controller = ScrollController();
          addTearDown(controller.dispose);
          var tapped = false;
          await tester.pumpWidget(
            MaterialApp(
              scrollBehavior: const AppScrollBehavior(),
              home: ListView(
                controller: controller,
                children: [
                  SizedBox(
                    height: 400,
                    child: TextButton(
                      onPressed: () => tapped = true,
                      child: const Text('Covered'),
                    ),
                  ),
                  const SizedBox(height: 3000),
                ],
              ),
            ),
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
            buttons: kMiddleMouseButton,
          );
          await mouse.addPointer(location: const Offset(200, 200));
          await mouse.down(const Offset(200, 200));
          await mouse.up();
          await tester.pump();
          expect(
            find.byKey(const ValueKey('app-middle-scroll-anchor')),
            findsOneWidget,
          );
          if (exit == 'wheel') {
            await wheel(tester, const Offset(200, 200), 120);
          } else if (exit == 'click') {
            await tester.tapAt(const Offset(200, 200));
          } else if (exit == 'inactive') {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
          }
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('app-middle-scroll-anchor')),
            findsNothing,
          );
          expect(tapped, isFalse);
          await mouse.removePointer();
        },
      );
    }

    testWidgets(
      'middle mode accelerates with distance and falls back past non-scrollable children',
      (tester) async {
        final outer = ScrollController();
        addTearDown(outer.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: ListView(
              controller: outer,
              children: [
                SizedBox(
                  height: 200,
                  child: ListView(children: const [SizedBox(height: 20)]),
                ),
                const SizedBox(height: 5000),
              ],
            ),
          ),
        );
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await mouse.addPointer(location: const Offset(100, 100));
        await mouse.down(const Offset(100, 100));
        await mouse.up();
        await tester.pump();
        await mouse.moveTo(const Offset(100, 130));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final nearDistance = outer.offset;
        expect(nearDistance, greaterThan(0));
        await mouse.moveTo(const Offset(100, 200));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(outer.offset - nearDistance, greaterThan(nearDistance * 2));
        final beforeFar = outer.offset;
        await mouse.moveTo(const Offset(100, 400));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        // At 300 px displacement, move well beyond the old 2400 px/s cap.
        expect(outer.offset - beforeFar, greaterThan(1500));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await mouse.removePointer();
      },
    );

    testWidgets(
      'multiline editors inherit middle scrolling without changing their text',
      (tester) async {
        final input = TextEditingController(
          text: List.filled(60, 'Editable line').join('\n'),
        );
        final scroll = ScrollController();
        addTearDown(input.dispose);
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  height: 160,
                  child: TextField(
                    controller: input,
                    scrollController: scroll,
                    maxLines: null,
                    expands: true,
                  ),
                ),
              ),
            ),
          ),
        );
        final original = input.text;
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await mouse.addPointer(location: const Offset(100, 70));
        await mouse.down(const Offset(100, 70));
        await mouse.up();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('app-middle-scroll-anchor')),
          findsOneWidget,
        );
        await mouse.moveTo(const Offset(100, 140));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(scroll.offset, greaterThan(0));
        expect(input.text, original);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await mouse.removePointer();
      },
    );

    testWidgets('should respect reduced motion', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: ListView(
            controller: controller,
            children: const [SizedBox(height: 3000)],
          ),
        ),
      );
      await wheel(tester, const Offset(200, 200), 120);
      expect(controller.offset, 120);
    });
  });
}
