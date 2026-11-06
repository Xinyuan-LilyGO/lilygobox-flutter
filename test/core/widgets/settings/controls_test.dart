/*
 * @Description: 验证设置下拉菜单按所在背景取色并保持交互流程。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-11-06 15:23:31
 * @License: GPL 3.0
 */

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/core/widgets/popup_menu_surface.dart';
import 'package:lilygobox/core/widgets/settings/widgets.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

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
  testWidgets('select control uses its hosting surface color', (tester) async {
    final themes = ThemeProvider();
    addTearDown(themes.dispose);
    for (final type in ThemeType.values) {
      themes.setTheme(type);
      final theme = themes.themeData;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingSelect<String>(
              theme: theme,
              value: 'One',
              items: const [DropdownMenuItem(value: 'One', child: Text('One'))],
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(
        background(tester, find.byType(SettingSelect<String>)),
        theme.selectControlColorForSurface(theme.secondary),
      );
    }
  });

  testWidgets('select colors derive from the supplied hosting surface', (
    tester,
  ) async {
    final themes = ThemeProvider();
    addTearDown(themes.dispose);
    final theme = themes.themeData;
    const host = Color(0xFFE0E0E0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColoredBox(
            color: host,
            child: SettingSelect<String>(
              theme: theme,
              surfaceColor: host,
              value: 'One',
              items: const [DropdownMenuItem(value: 'One', child: Text('One'))],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final select = find.byType(SettingSelect<String>);
    expect(
      background(tester, select),
      theme.selectControlColorForSurface(host),
    );

    await tester.tap(select);
    await tester.pumpAndSettle();
    expect(
      background(tester, find.byType(PopupMenuSurface)),
      theme.selectMenuColorForSurface(host),
    );
  });

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
      Color.lerp(
        theme.selectMenuColorForSurface(theme.secondary),
        theme.basePrimary,
        .5,
      ),
    );
    await tester.pumpAndSettle();
    expect(background(tester, option), theme.basePrimary);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      background(tester, option),
      Color.lerp(
        theme.basePrimary,
        theme.selectMenuColorForSurface(theme.secondary),
        .5,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      background(tester, option),
      theme.selectMenuColorForSurface(theme.secondary),
    );

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
    expect(background(tester, selected), theme.basePrimary);
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
        PopupMenuSurface.backgroundColorFor(themes.themeData),
        themes.themeData.basePrimary,
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
