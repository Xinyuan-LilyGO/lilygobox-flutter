/*
 * @Description: 验证透明图标按钮在明暗主题下的悬停渐变不会闪色。
 */

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/interaction_decoration.dart';
import 'package:lilygobox/core/widgets/title_bar_icon_button.dart';

void main() {
  for (final type in [ThemeType.light, ThemeType.dark]) {
    testWidgets('transparent copy hover fades without a dark flash: $type', (
      tester,
    ) async {
      final provider = ThemeProvider()..setTheme(type);
      addTearDown(provider.dispose);
      final theme = provider.themeData;
      final hover = theme.primaryTextHoverColor;
      await tester.pumpWidget(
        MaterialApp(
          home: ColoredBox(
            color: theme.secondary,
            child: Center(
              child: TitleBarIconButton(
                onPressed: () {},
                isFocused: true,
                theme: theme,
                icon: Icons.copy,
                backgroundColor: Colors.transparent,
                hoverColor: hover,
                surfaceColor: theme.secondary,
              ),
            ),
          ),
        ),
      );
      final surface = find.byType(InteractionDecoration);
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
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      expect(background().a, 0);
      await mouse.moveTo(tester.getCenter(surface));
      await tester.pump();
      for (var i = 1; i <= 6; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        expect(background().a, closeTo(hover.a * i / 6, .00001));
        expect(background().r, closeTo(hover.r, .00001));
        expect(background().g, closeTo(hover.g, .00001));
        expect(background().b, closeTo(hover.b, .00001));
      }
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      for (var i = 1; i <= 6; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        expect(background().a, closeTo(hover.a * (1 - i / 6), .00001));
        expect(background().r, closeTo(hover.r, .00001));
        expect(background().g, closeTo(hover.g, .00001));
        expect(background().b, closeTo(hover.b, .00001));
      }
    });
  }
}
