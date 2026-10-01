/*
 * @Description: 验证设置下拉菜单和重置菜单的颜色渐变及交互流程。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygo_box/core/theme/provider.dart';
import 'package:lilygo_box/core/widgets/menu_item_surface.dart';
import 'package:lilygo_box/core/widgets/settings/widgets.dart';
import 'package:lilygo_box/generated/l10n/app_localizations.dart';

Color background(WidgetTester tester, Finder surface) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: surface,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color != null,
          ),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('dropdown fades both ways and still selects and dismisses', (
    tester,
  ) async {
    final themes = ThemeProvider();
    addTearDown(themes.dispose);
    final theme = themes.themeData;
    var value = 'One';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Center(
              child: SizedBox(
                width: 240,
                child: SettingSelect<String>(
                  theme: theme,
                  value: value,
                  items: const [
                    DropdownMenuItem(value: 'One', child: Text('One')),
                    DropdownMenuItem(value: 'Two', child: Text('Two')),
                  ],
                  onChanged: (next) => setState(() => value = next!),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final select = find.byType(SettingSelect<String>);
    expect(tester.getSize(select).height, 32);
    await tester.tap(select);
    await tester.pumpAndSettle();
    final option = find.ancestor(
      of: find.text('Two'),
      matching: find.byType(MenuItemSurface),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(option));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      background(tester, option),
      Color.lerp(theme.primary, theme.primaryTextHoverColor, .5),
    );
    await tester.pumpAndSettle();
    expect(background(tester, option), theme.primaryTextHoverColor);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      background(tester, option),
      Color.lerp(theme.primaryTextHoverColor, theme.primary, .5),
    );
    await tester.pumpAndSettle();
    expect(background(tester, option), theme.primary);

    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(value, 'Two');
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('One'), findsNothing);
    await tester.tap(select);
    await tester.pumpAndSettle();
    final selected = find.ancestor(
      of: find.text('Two').last,
      matching: find.byType(MenuItemSurface),
    );
    await mouse.moveTo(tester.getCenter(selected));
    await tester.pumpAndSettle();
    expect(background(tester, selected), theme.primaryTextSelectedColor);
    await tester.tap(selected);
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsOneWidget);
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('One'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset menu fades and calls its action once', (tester) async {
    final themes = ThemeProvider();
    addTearDown(themes.dispose);
    var resets = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SettingsRow(
            theme: themes.themeData,
            title: 'Setting',
            description: 'Description',
            control: const Text('Value'),
            onReset: () => resets++,
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    final label = AppLocalizations.of(
      tester.element(find.byType(SettingsRow)),
    ).resetThisSetting;
    final reset = find.ancestor(
      of: find.text(label),
      matching: find.byType(MenuItemSurface),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(reset));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      background(tester, reset),
      Color.lerp(
        themes.themeData.primary,
        themes.themeData.primaryTextHoverColor,
        .5,
      ),
    );
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(find.text(label), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
