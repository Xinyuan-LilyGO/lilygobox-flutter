/*
 * @Description: 验证悬停提示在页面隐藏后的清理及再次进入时的正常显示。
 * @Author: LILYGO_L
 * @Date: 2026-10-07 18:00:00
 * @LastEditTime: 2026-10-07 18:00:00
 * @License: GPL 3.0
 */
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/widgets/app_tooltip.dart';
import 'package:lilygobox/core/widgets/retained_page_stack.dart';

void main() {
  testWidgets('hidden retained page removes tooltip and can show it again', (
    tester,
  ) async {
    final page = ValueNotifier(0);
    addTearDown(page.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: page,
            builder: (context, active, _) => RetainedPageStack(
              activeKey: active,
              pages: {
                0: Center(
                  child: AppTooltip(
                    message: 'Back hint',
                    verticalOffset: 16,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: GestureDetector(
                        key: const ValueKey('back-button'),
                        onTap: () => page.value = 1,
                        child: const Icon(Icons.arrow_back),
                      ),
                    ),
                  ),
                ),
                1: const Center(child: Text('Home')),
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    final button = find.byKey(const ValueKey('back-button'));
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump(AppTooltip.waitDuration);
    await tester.pumpAndSettle();
    expect(find.text('Back hint'), findsOneWidget);
    page.value = 1;
    await tester.pumpAndSettle();
    expect(find.text('Back hint', skipOffstage: false), findsNothing);
    await mouse.moveTo(Offset.zero);
    page.value = 0;
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump(AppTooltip.waitDuration);
    await tester.pumpAndSettle();
    await mouse.down(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 20));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Back hint', skipOffstage: false), findsNothing);

    await mouse.moveTo(Offset.zero);
    page.value = 0;
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump(AppTooltip.waitDuration);
    await tester.pumpAndSettle();
    expect(find.text('Back hint'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Back hint')).dy -
          tester.getBottomLeft(button).dy,
      greaterThanOrEqualTo(8),
    );
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Back hint'), findsNothing);

    // 隐藏发生在等待显示期间，也不能稍后向新页面弹出提示。
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 200));
    page.value = 1;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Back hint'), findsNothing);
  });
}
