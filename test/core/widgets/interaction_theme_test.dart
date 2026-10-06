/*
 * @Description: 验证按钮切换主题时立即更新背景，并保留悬停渐变和点击响应。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 22:00:00
 * @LastEditTime: 2026-10-02 21:44:28
 * @License: GPL 3.0
 */

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/widgets/title_bar_control_button.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/animated_circle_icon_button.dart';
import 'package:lilygobox/core/widgets/interaction_decoration.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/core/widgets/title_bar_icon_button.dart';

void main() {
  for (final kind in ['menu', 'toolbar', 'circle', 'window', 'close']) {
    testWidgets('$kind synchronizes theme during idle and hover transitions', (
      tester,
    ) async {
      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      late StateSetter rebuild;
      var taps = 0;
      var disableAnimations = false;
      void onTap() => taps++;
      Color resting(AppTheme theme) =>
          kind == 'circle' ? theme.iconBackgroundColor : theme.primary;
      Color hovered(AppTheme theme) => kind == 'close'
          ? Colors.red.shade600
          : kind == 'circle'
          ? theme.iconHoverColor
          : theme.primaryTextHoverColor;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              final theme = provider.themeData;
              final button = switch (kind) {
                'menu' => MenuItemSurface(
                  theme: theme,
                  onPressed: onTap,
                  child: const SizedBox(width: 100, height: 30),
                ),
                'toolbar' => TitleBarIconButton(
                  theme: theme,
                  onPressed: onTap,
                  icon: Icons.settings,
                  isFocused: true,
                ),
                'circle' => AnimatedCircleIconButton(
                  theme: theme,
                  onPressed: onTap,
                  icon: Icons.settings,
                ),
                _ => AppTitleBarControlsButtonTemplate(
                  theme: theme,
                  icon: Icons.close,
                  onPressed: onTap,
                  hoverColor: hovered(theme),
                  iconColor: theme.iconColor,
                  hoverIconColor: kind == 'close' ? Colors.white : null,
                ),
              };
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: disableAnimations),
                child: ColoredBox(
                  color: theme.primary,
                  child: Center(child: button),
                ),
              );
            },
          ),
        ),
      );

      final surface = find.byType(InteractionDecoration).first;
      Color background() =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: surface,
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color!;

      // 第一帧就应使用新主题，而不是等动画完成后才正确。
      for (final type in [ThemeType.light, ThemeType.dark]) {
        rebuild(() => provider.setTheme(type));
        await tester.pump();
        expect(background(), resting(provider.themeData));
      }

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(surface));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(
        background(),
        Color.lerp(
          resting(provider.themeData),
          hovered(provider.themeData),
          .5,
        ),
      );
      // 悬停渐变中切换主题，不得继续播放旧配色。
      rebuild(() => provider.setTheme(ThemeType.light));
      await tester.pump();
      expect(background(), hovered(provider.themeData));
      await tester.pump(const Duration(milliseconds: 30));
      expect(background(), hovered(provider.themeData));
      if (kind == 'close') {
        expect(
          IconTheme.of(tester.element(find.byType(Icon))).color,
          Colors.white,
        );
      }

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(
        background(),
        Color.lerp(
          hovered(provider.themeData),
          resting(provider.themeData),
          .5,
        ),
      );
      rebuild(() => provider.setTheme(ThemeType.dark));
      await tester.pump();
      expect(background(), resting(provider.themeData));

      rebuild(() => disableAnimations = true);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(surface));
      await tester.pump();
      expect(background(), hovered(provider.themeData));
      await tester.tap(surface);
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
