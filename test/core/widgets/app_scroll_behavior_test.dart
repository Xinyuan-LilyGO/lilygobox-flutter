/*
 * @Description: 验证全局滚轮平滑动画、嵌套滚动与减少动画偏好。
 * @Author: LILYGO_L
 * @Date: 2026-10-12 00:00:00
 * @LastEditTime: 2026-10-12 00:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
