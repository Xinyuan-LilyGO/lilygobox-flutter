/*
 * @Description: 验证共用菜单表面的悬停渐变、选中禁用和点击波纹。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 17:29:40
 * @License: GPL 3.0
 */

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/context_menu/right_click_menu.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/core/widgets/popup_menu_transition.dart';

void main() {
  testWidgets(
    'right-click menu opens once in 150ms and respects reduced motion',
    (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      final controller = RightClickMenuController();
      late StateSetter rebuild;
      var reducedMotion = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reducedMotion),
                child: Scaffold(
                  body: Center(
                    child: RightClickMenuBuilder.buildMenuAnchor(
                      context: context,
                      controller: controller,
                      menuItems: [
                        RightClickMenuItem(
                          label: 'Copy',
                          onTap: controller.close,
                        ),
                      ],
                      theme: theme.themeData,
                      onSecondaryTap: () {},
                      child: const SizedBox(
                        width: 150,
                        height: 120,
                        child: Text('Target'),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      double opacity() => tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(PopupMenuTransition),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;
      for (var i = 0; i < 2; i++) {
        final press = await tester.startGesture(
          tester.getCenter(find.text('Target')),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(PopupMenuTransition), findsNothing);
        await press.up();
        await tester.pump();
        expect(opacity(), 0);
        await tester.pump(const Duration(milliseconds: 75));
        expect(opacity(), closeTo(.5, .01));
        await tester.pump(const Duration(milliseconds: 75));
        expect(opacity(), 1);
        rebuild(() {});
        await tester.pump();
        expect(opacity(), 1);
        // 再次按下右键立即关闭旧菜单，持续按住不显示，松手才从新位置淡入。
        final target = tester.getRect(find.text('Target'));
        for (final point in [
          target.topLeft + const Offset(3, 3),
          target.bottomLeft + const Offset(3, -3),
        ]) {
          final nextPress = await tester.startGesture(
            point,
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await tester.pump();
          expect(find.byType(PopupMenuTransition), findsNothing);
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(PopupMenuTransition), findsNothing);
          await nextPress.up();
          await tester.pump();
          expect(opacity(), 0);
          await tester.pump(const Duration(milliseconds: 75));
          expect(opacity(), closeTo(.5, .01));
          await tester.pump(const Duration(milliseconds: 75));
          expect(opacity(), 1);
        }
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuTransition), findsNothing);
      }
      rebuild(() => reducedMotion = true);
      await tester.pump();
      await tester.tap(find.text('Target'), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(opacity(), 1);
      controller.close();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapid menu hover does not repaint the panel background', (
    tester,
  ) async {
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    var panelPaints = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: _PaintProbe(
              onPaint: () => panelPaints++,
              child: RightClickMenuBuilder.buildMenuPanel(
                theme: theme.themeData,
                menuItems: [
                  for (final label in ['Cut', 'Copy', 'Paste', 'Select all'])
                    RightClickMenuItem(label: label, onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final items = find.byType(MenuItemSurface);
    final initialPaints = panelPaints;
    final rects = [for (var i = 0; i < 4; i++) tester.getRect(items.at(i))];
    for (var i = 0; i < 32; i++) {
      await mouse.moveTo(rects[i % 2 == 0 ? 0 : 3].center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        panelPaints,
        initialPaints,
        reason:
            'Hover should repaint the item, not the menu background and shadow',
      );
      for (var j = 0; j < 4; j++) {
        expect(tester.getRect(items.at(j)), rects[j]);
      }
    }
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(panelPaints, initialPaints);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover fades both ways and selection blocks repeated clicks', (
    tester,
  ) async {
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    var selected = false;
    var taps = 0;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Center(
                child: MenuItemSurface(
                  theme: theme.themeData,
                  isSelected: selected,
                  onPressed: () {
                    taps++;
                    setState(() => selected = true);
                  },
                  child: const SizedBox(width: 200, height: 40),
                ),
              );
            },
          ),
        ),
      ),
    );

    Color background() {
      final decoration = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(MenuItemSurface),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (decoration.decoration as BoxDecoration).color!;
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final item = find.byType(MenuItemSurface);
    await mouse.moveTo(tester.getCenter(item));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      background(),
      Color.lerp(
        theme.themeData.primary,
        theme.themeData.primaryTextHoverColor,
        .5,
      ),
    );
    await tester.pumpAndSettle();
    expect(background(), theme.themeData.primaryTextHoverColor);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      background(),
      Color.lerp(
        theme.themeData.primaryTextHoverColor,
        theme.themeData.primary,
        .5,
      ),
    );
    await tester.pumpAndSettle();
    expect(background(), theme.themeData.primary);

    await mouse.moveTo(tester.getCenter(item));
    await tester.pumpAndSettle();
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(background(), theme.themeData.primaryTextSelectedColor);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(taps, 1);

    rebuild(() => selected = false);
    await tester.pumpAndSettle();
    expect(background(), theme.themeData.primaryTextHoverColor);
    rebuild(() => theme.setTheme(ThemeType.light));
    await tester.pumpAndSettle();
    expect(background(), theme.themeData.primaryTextHoverColor);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(background(), theme.themeData.primary);
  });

  testWidgets('a press paints a ripple above the menu background', (
    tester,
  ) async {
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MenuItemSurface(
            theme: theme.themeData,
            onPressed: () {},
            child: const SizedBox(width: 200, height: 40),
          ),
        ),
      ),
    );
    final press = await tester.startGesture(
      tester.getCenter(find.byType(MenuItemSurface)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.renderObject(find.byType(Material)),
      paints..circle(
        color: theme.themeData.textColorPrimary.withValues(alpha: 0.12),
      ),
    );
    await press.up();
    await tester.pumpAndSettle();
    expect(tester.renderObject(find.byType(Material)), isNot(paints..circle()));
  });
}

// 统计菜单外层的实际绘制次数，验证悬停动画不会使静态背景重复绘制。
class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({required this.onPaint, required super.child});
  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintProbeRender(onPaint);
}

class _PaintProbeRender extends RenderProxyBox {
  _PaintProbeRender(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}
