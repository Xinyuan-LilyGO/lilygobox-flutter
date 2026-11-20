/*
 * @Description: 验证全局平滑滚轮、嵌套仲裁与其他鼠标操作。
 */
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:material_ui/material_ui.dart';

/// 模拟鼠标滚轮输入，直接验证全局事件仲裁后的滚动结果。
Future<void> wheel(
  WidgetTester tester,
  Offset point,
  double delta, {
  Duration timeStamp = Duration.zero,
}) => tester.sendEventToBinding(
  PointerScrollEvent(
    timeStamp: timeStamp,
    position: point,
    scrollDelta: Offset(0, delta),
    kind: PointerDeviceKind.mouse,
  ),
);

void main() {
  group('WheelScrollAcceleration', () {
    test('input intervals map linearly to the multiplier with a 3x cap', () {
      final acceleration = WheelScrollAcceleration();
      var time = const Duration(seconds: 1);
      double sample(int milliseconds) {
        time += Duration(milliseconds: milliseconds);
        return acceleration.apply(const Offset(0, 120), time).dy / 120;
      }

      expect(sample(0), 1);
      for (final (interval, multiplier) in [
        (100, 1.0),
        (75, 5 / 3),
        (50, 7 / 3),
        (25, 3.0),
        (10, 3.0),
      ]) {
        expect(sample(interval), closeTo(multiplier, .0001));
      }
      expect(sample(100), 1);
    });

    test('speed changes take effect immediately without a ramp or history', () {
      final acceleration = WheelScrollAcceleration();
      for (var index = 0; index <= 6; index++) {
        acceleration.apply(
          const Offset(0, 120),
          Duration(milliseconds: 1000 + index * 25),
        );
      }
      final multiplier =
          acceleration
              .apply(const Offset(0, 120), const Duration(milliseconds: 1225))
              .dy /
          120;
      expect(multiplier, closeTo(5 / 3, .0001));
      expect(
        acceleration
            .apply(const Offset(0, 120), const Duration(milliseconds: 1250))
            .dy,
        360,
      );
    });

    for (final resetCase in ['reverse', 'axis', 'pause', 'activity', 'reset']) {
      test('$resetCase clears accumulated acceleration', () {
        final acceleration = WheelScrollAcceleration();
        for (var index = 0; index <= 6; index++) {
          acceleration.apply(
            const Offset(0, 120),
            Duration(milliseconds: 1000 + index * 25),
          );
        }
        if (resetCase == 'reset') acceleration.reset();
        final delta = switch (resetCase) {
          'reverse' => const Offset(0, -120),
          'axis' => const Offset(120, 0),
          _ => const Offset(0, 120),
        };
        expect(
          acceleration.apply(
            delta,
            Duration(milliseconds: resetCase == 'pause' ? 1400 : 1175),
            continuing: resetCase != 'activity',
          ),
          delta,
        );
      });
    }
  });

  group('AppScrollBehavior', () {
    testWidgets('multiline input respects explicit scrollbar suppression', (
      tester,
    ) async {
      final scroll = ScrollController();
      final input = TextEditingController(
        text: List.generate(30, (index) => 'Line $index').join('\n'),
      );
      addTearDown(scroll.dispose);
      addTearDown(input.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: Scrollbar(
              key: const ValueKey('manual-input-scrollbar'),
              controller: scroll,
              child: ScrollConfiguration(
                behavior: const AppScrollBehavior(scrollbars: false),
                child: TextField(
                  controller: input,
                  scrollController: scroll,
                  maxLines: 3,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.jumpTo(0);
      await wheel(tester, tester.getCenter(find.byType(TextField)), 60);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets(
      'copied menu behavior preserves wheel acceleration and options',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final behavior = const AppScrollBehavior()
            .copyWith(
              scrollbars: false,
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              pointerAxisModifiers: {LogicalKeyboardKey.altLeft},
              platform: TargetPlatform.windows,
            )
            .copyWith(overscroll: false);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: behavior,
            home: ListView(
              controller: controller,
              children: const [SizedBox(height: 10000)],
            ),
          ),
        );
        final context = tester.element(find.byType(ListView));
        expect(
          behavior.getScrollPhysics(context),
          isA<ClampingScrollPhysics>(),
        );
        expect(
          behavior.getKeyboardDismissBehavior(context),
          ScrollViewKeyboardDismissBehavior.onDrag,
        );
        expect(behavior.pointerAxisModifiers, {LogicalKeyboardKey.altLeft});
        expect(behavior.shouldNotify(behavior.copyWith()), isFalse);
        expect(
          behavior.shouldNotify(behavior.copyWith(scrollbars: true)),
          isTrue,
        );
        expect(find.byType(Scrollbar), findsNothing);
        for (var eventIndex = 0; eventIndex < 2; eventIndex++) {
          await wheel(
            tester,
            const Offset(200, 200),
            120,
            timeStamp: Duration(milliseconds: 1000 + eventIndex * 25),
          );
        }
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(480, .1));
      },
    );

    for (final direction in [1, -1]) {
      for (final (interval, distance) in [
        (250, 360),
        (100, 360),
        (75, 520),
        (50, 680),
        (25, 840),
        (10, 840),
        (0, 360),
      ]) {
        testWidgets(
          'wheel direction=$direction interval=${interval}ms scales distance with input speed',
          (tester) async {
            final controller = ScrollController(initialScrollOffset: 5000);
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              MaterialApp(
                scrollBehavior: const AppScrollBehavior(),
                home: ListView(
                  controller: controller,
                  children: const [SizedBox(height: 20000)],
                ),
              ),
            );
            for (var eventIndex = 0; eventIndex < 3; eventIndex++) {
              await wheel(
                tester,
                const Offset(200, 200),
                120.0 * direction,
                timeStamp: Duration(milliseconds: 1000 + eventIndex * interval),
              );
              await tester.pump();
              await tester.pump(Duration(milliseconds: interval));
            }
            await tester.pumpAndSettle();
            expect(controller.offset, closeTo(5000 + direction * distance, .1));
          },
        );
      }
    }

    testWidgets('wheel multiplier follows acceleration and deceleration', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: ListView(
            controller: controller,
            children: const [SizedBox(height: 10000)],
          ),
        ),
      );
      var eventTime = 1000;
      for (final interval in [0, 50, 25, 75]) {
        await tester.pump(Duration(milliseconds: interval));
        eventTime += interval;
        await wheel(
          tester,
          const Offset(200, 200),
          120,
          timeStamp: Duration(milliseconds: eventTime),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(960, .1));
    });

    testWidgets(
      'rapid wheel acceleration resets on reversal and after a pause',
      (tester) async {
        final controller = ScrollController(initialScrollOffset: 1000);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: ListView(
              controller: controller,
              children: const [SizedBox(height: 10000)],
            ),
          ),
        );
        for (var eventIndex = 0; eventIndex < 2; eventIndex++) {
          await wheel(
            tester,
            const Offset(200, 200),
            120,
            timeStamp: Duration(milliseconds: 1000 + eventIndex * 50),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }
        final beforeReverse = controller.offset;
        await wheel(
          tester,
          const Offset(200, 200),
          -120,
          timeStamp: const Duration(milliseconds: 1100),
        );
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(beforeReverse - 120, .1));
        final beforePause = controller.offset;
        await wheel(
          tester,
          const Offset(200, 200),
          -120,
          timeStamp: const Duration(milliseconds: 1500),
        );
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(beforePause - 120, .1));
      },
    );

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

    testWidgets('a wheel notch after a pause responds on the next frame', (
      tester,
    ) async {
      final controller = ScrollController(initialScrollOffset: 1000);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: ListView(
            controller: controller,
            children: const [SizedBox(height: 4000)],
          ),
        ),
      );
      const point = Offset(200, 200);
      const frame = Duration(milliseconds: 16);
      for (final delta in [100.0, -100.0]) {
        final start = controller.offset;
        await wheel(
          tester,
          point,
          delta,
          timeStamp: const Duration(seconds: 1),
        );
        await tester.pump();
        await tester.pump(frame);
        final firstFrame = (controller.offset - start).abs();
        await tester.pump(const Duration(milliseconds: 129));
        final beforeNext = controller.offset;
        await wheel(
          tester,
          point,
          delta,
          timeStamp: const Duration(milliseconds: 1145),
        );
        await tester.pump(frame);
        expect(
          (controller.offset - beforeNext).abs(),
          greaterThanOrEqualTo(firstFrame - .01),
        );
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(start + 2 * delta, .01));
      }
    });

    testWidgets(
      'continuous wheel input advances during every frame without restarting the activity',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        var starts = 0;
        var ends = 0;
        var intentions = 0;
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: NotificationListener<AppUserScrollNotification>(
              onNotification: (_) {
                intentions++;
                return false;
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) starts++;
                  if (notification is ScrollEndNotification) ends++;
                  return false;
                },
                child: ListView(
                  controller: controller,
                  children: const [SizedBox(height: 10000)],
                ),
              ),
            ),
          ),
        );
        var previous = 0.0;
        for (var i = 0; i < 8; i++) {
          await wheel(tester, const Offset(200, 200), 120);
          await tester.pump(const Duration(milliseconds: 16));
          if (i > 0) expect(controller.offset, greaterThan(previous));
          previous = controller.offset;
        }
        expect(controller.offset, greaterThan(120));
        expect(controller.offset, lessThan(960));
        expect(starts, 1);
        expect(ends, 0);
        expect(intentions, 8);
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(960, .1));
        expect(starts, 1);
        expect(ends, 1);
      },
    );

    testWidgets(
      'rapid multi-event bursts advance each frame and preserve all distance',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: ListView(
              controller: controller,
              children: const [SizedBox(height: 40000)],
            ),
          ),
        );
        var previous = 0.0;
        for (var frame = 0; frame < 32; frame++) {
          // Four wheel events arrive before the next rendered frame.
          for (var event = 0; event < 4; event++) {
            await wheel(tester, const Offset(200, 200), 120);
          }
          await tester.pump(const Duration(milliseconds: 16));
          if (frame > 0) expect(controller.offset, greaterThan(previous));
          previous = controller.offset;
        }
        expect(controller.offset, lessThan(15360));
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(15360, .1));
        await wheel(tester, const Offset(200, 200), -120);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.offset, lessThan(15360));
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(15240, .1));
      },
    );

    testWidgets(
      'same-frame wheel bursts accumulate and reverse without a forward tail',
      (tester) async {
        final controller = ScrollController(initialScrollOffset: 600);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: ListView(
              controller: controller,
              children: const [SizedBox(height: 10000)],
            ),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await wheel(tester, const Offset(200, 200), 120);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        final beforeReverse = controller.offset;
        expect(beforeReverse, greaterThan(600));
        await wheel(tester, const Offset(200, 200), -120);
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.offset, lessThan(beforeReverse));
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(beforeReverse - 120, .1));
        for (var i = 0; i < 5; i++) {
          await wheel(tester, const Offset(200, 200), 120);
        }
        final beforeBurst = controller.offset;
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(beforeBurst + 600, .1));
      },
    );

    testWidgets('external scrolling cancels a pending wheel target', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: ListView(
            controller: controller,
            children: const [SizedBox(height: 10000)],
          ),
        ),
      );
      await wheel(tester, const Offset(200, 200), 960);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      controller.jumpTo(300);
      await wheel(tester, const Offset(200, 200), 120);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(420, .1));
    });

    testWidgets(
      'replacing a wheel region keeps the new gesture on its reused position',
      (tester) async {
        final controller = ScrollController();
        final parent = ValueNotifier(false);
        addTearDown(controller.dispose);
        addTearDown(parent.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: Stack(
              fit: StackFit.expand,
              children: [
                ListView(
                  controller: controller,
                  children: const [SizedBox(height: 10000)],
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: parent,
                  builder: (context, value, _) => KeyedSubtree(
                    key: ValueKey(value),
                    child: const AppScrollBehavior(scrollbars: false)
                        .buildScrollbar(
                          context,
                          const SizedBox.expand(),
                          ScrollableDetails.vertical(controller: controller),
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
        const point = Offset(200, 200);
        await wheel(tester, point, 300);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        final original = controller.position;
        late double expectedOffset;
        tester.binding.addPostFrameCallback((_) {
          expectedOffset = controller.offset + 120;
          tester.binding.handlePointerEvent(
            const PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position: point,
              scrollDelta: Offset(0, 120),
            ),
          );
        });
        parent.value = true;
        await tester.pump();
        expect(controller.position, same(original));
        expect(controller.position.isScrollingNotifier.value, isTrue);
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(expectedOffset, .01));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'wheel target remains bounded when content shrinks during animation',
      (tester) async {
        final controller = ScrollController();
        final extent = ValueNotifier<double>(10000);
        addTearDown(controller.dispose);
        addTearDown(extent.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: ValueListenableBuilder<double>(
              valueListenable: extent,
              builder: (_, height, child) => ListView(
                controller: controller,
                children: [SizedBox(height: height)],
              ),
            ),
          ),
        );
        await wheel(tester, const Offset(200, 200), 3000);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        extent.value = 800;
        await tester.pumpAndSettle();
        expect(
          controller.offset,
          inInclusiveRange(
            controller.position.minScrollExtent,
            controller.position.maxScrollExtent,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

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

    for (final drag in [false, true]) {
      testWidgets(
        'middle mouse ${drag ? 'drag' : 'click'} does not capture list input',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          var clicks = 0;
          await tester.pumpWidget(
            MaterialApp(
              scrollBehavior: const AppScrollBehavior(),
              home: Scaffold(
                body: ListView(
                  controller: scroll,
                  children: [
                    SizedBox(
                      height: 100,
                      child: TextButton(
                        onPressed: () => clicks++,
                        child: const Text('Action'),
                      ),
                    ),
                    const SizedBox(height: 4000),
                  ],
                ),
              ),
            ),
          );
          const start = Offset(100, 200);
          const end = Offset(100, 450);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
            buttons: kMiddleMouseButton,
          );
          await mouse.addPointer(location: start);
          await mouse.down(start);
          await tester.pump();
          if (drag) {
            await mouse.moveTo(end);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(scroll.offset, 0);
          }
          await mouse.up();
          if (!drag) await mouse.moveTo(end);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(scroll.offset, 0);

          await tester.tap(find.text('Action'), kind: PointerDeviceKind.mouse);
          expect(clicks, 1);
          await mouse.removePointer();
          await wheel(tester, end, 120);
          await tester.pumpAndSettle();
          expect(scroll.offset, closeTo(120, .01));
        },
      );
    }

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
