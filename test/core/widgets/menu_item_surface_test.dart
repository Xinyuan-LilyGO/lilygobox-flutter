/*
 * @Description: 验证共用菜单表面的悬停渐变、选中禁用和点击波纹。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 17:29:40
 * @License: GPL 3.0
 */

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';

void main() {
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
