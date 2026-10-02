/*
 * @Description: 验证全局主题同步渐变、连续切换及减少动画设置。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 22:01:29
 * @LastEditTime: 2026-10-02 22:01:29
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/features/settings/presentation/widgets/content_layout.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('background, text and buttons share the same transition frame', (
    tester,
  ) async {
    final theme = ThemeProvider(vsync: tester);
    addTearDown(theme.dispose);
    final dark = theme.themeData;
    final light = theme.allThemes.firstWhere((t) => t.type == ThemeType.light);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: MaterialApp(
          home: Consumer<ThemeProvider>(
            builder: (context, provider, child) {
              final palette = provider.themeData;
              return ColoredBox(
                key: const ValueKey('page'),
                color: palette.primary,
                child: Center(
                  child: MenuItemSurface(
                    theme: palette,
                    onPressed: () {},
                    child: Text(
                      'Theme',
                      style: TextStyle(color: palette.textColorPrimary),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    void expectSynchronized() {
      final palette = theme.themeData;
      expect(
        tester.widget<ColoredBox>(find.byKey(const ValueKey('page'))).color,
        palette.primary,
      );
      expect(
        tester.widget<Text>(find.text('Theme')).style!.color,
        palette.textColorPrimary,
      );
      final decoration = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(MenuItemSurface),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((decoration.decoration as BoxDecoration).color, palette.primary);
    }

    theme.setTheme(ThemeType.light);
    await tester.pump();
    expectSynchronized();
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      theme.themeData.primary,
      Color.lerp(dark.primary, light.primary, .5),
    );
    expect(
      theme.themeData.textColorPrimary,
      Color.lerp(dark.textColorPrimary, light.textColorPrimary, .5),
    );
    expect(
      SettingsColors(theme.themeData).control,
      Color.lerp(
        SettingsColors(dark).control,
        SettingsColors(light).control,
        .5,
      ),
    );
    expectSynchronized();
    await tester.pump(const Duration(milliseconds: 90));
    expect(identical(theme.themeData, light), isTrue);
    expectSynchronized();
    await tester.pump(const Duration(milliseconds: 150));
    expectSynchronized();

    theme.setTheme(ThemeType.dark);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expectSynchronized();
    await tester.pump(const Duration(milliseconds: 90));
    expect(identical(theme.themeData, dark), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('rapid reversal starts at the displayed palette without a jump', (
    tester,
  ) async {
    final theme = ThemeProvider(vsync: tester);
    addTearDown(theme.dispose);
    final dark = theme.themeData;
    theme.setTheme(ThemeType.light);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midway = theme.themeData;
    expect(midway.primary, isNot(dark.primary));
    theme.setTheme(ThemeType.dark);
    expect(identical(theme.themeData, midway), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      theme.themeData.primary,
      Color.lerp(midway.primary, dark.primary, .5),
    );
    await tester.pump(const Duration(milliseconds: 90));
    expect(identical(theme.themeData, dark), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion snaps both active and subsequent transitions', (
    tester,
  ) async {
    final theme = ThemeProvider(vsync: tester);
    addTearDown(theme.dispose);
    final light = theme.allThemes.firstWhere((t) => t.type == ThemeType.light);
    theme.setTheme(ThemeType.light);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    theme.setDisableAnimations(true);
    expect(identical(theme.themeData, light), isTrue);
    theme.setTheme(ThemeType.dark);
    expect(theme.themeData.lightProgress, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(theme.themeData.lightProgress, 0);
    theme.setDisableAnimations(false);
    theme.setTheme(ThemeType.light);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(theme.themeData.lightProgress, closeTo(.5, .001));
    await tester.pumpAndSettle();
  });
}
