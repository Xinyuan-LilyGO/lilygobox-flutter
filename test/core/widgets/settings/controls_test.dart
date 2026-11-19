/*
 * @Description: 验证设置下拉控件取色并保持交互流程。
 */

import 'package:lilygobox/core/l10n/delegates.dart';

import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';
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
  test('popup surfaces mirror light and dark contrast and interpolate', () {
    final dark = MaterialPalette.create(ThemeType.dark);
    final light = MaterialPalette.create(ThemeType.light);
    expect(dark.popupSurfaceColor, const Color(0xFF191919));
    expect(light.popupSurfaceColor, Colors.white);
    expect(
      dark.popupSurfaceColor.computeLuminance(),
      lessThan(dark.secondary.computeLuminance()),
    );
    expect(
      dark.primaryTextHoverColor.computeLuminance(),
      greaterThan(dark.popupSurfaceColor.computeLuminance()),
    );
    expect(
      AppTheme.lerp(dark, light, .5).popupSurfaceColor,
      Color.lerp(dark.popupSurfaceColor, light.popupSurfaceColor, .5),
    );
  });

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

  testWidgets('dropdown panel keeps its theme popup surface', (tester) async {
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
      theme.popupSurfaceColor,
    );
  });

  testWidgets(
    'a long dropdown opens inside the viewport and its thumb reaches the last option',
    (tester) async {
      final themes = ThemeProvider();
      addTearDown(themes.dispose);
      int? chosen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: TargetPlatform.windows,
            scrollbarTheme: const ScrollbarThemeData(
              crossAxisMargin: 6,
              mainAxisMargin: 6,
            ),
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 300,
                child: SettingSelect<int>(
                  theme: themes.themeData,
                  value: 0,
                  items: List.generate(
                    10000,
                    (index) => DropdownMenuItem(
                      value: index,
                      child: Text('Agent $index'),
                    ),
                  ),
                  onChanged: (value) => chosen = value,
                ),
              ),
            ),
          ),
        ),
      );
      final trigger = find.byType(SettingSelect<int>);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final panel = find.byType(PopupMenuSurface);
      final bounds = tester.getRect(panel);
      expect(bounds.top, greaterThanOrEqualTo(PopupMenuSurface.verticalInset));
      expect(bounds.height, PopupMenuSurface.listMaxHeight);
      expect(bounds.bottom, lessThan(tester.getTopLeft(trigger).dy));
      final bars = find.descendant(of: panel, matching: find.byType(Scrollbar));
      expect(bars, findsOneWidget);
      expect(find.byType(MenuItemSurface).evaluate().length, lessThan(50));
      final first = find.ancestor(
        of: find.text('Agent 1'),
        matching: find.byType(MenuItemSurface),
      );
      expect(
        bounds.right - tester.getRect(first).right,
        greaterThanOrEqualTo(20),
      );
      final scroll = tester.widget<Scrollbar>(bars).controller!;
      scroll.jumpTo(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final thumb = await tester.startGesture(
        Offset(bounds.right - 8, bounds.top + 15),
        kind: PointerDeviceKind.mouse,
      );
      await thumb.moveTo(Offset(bounds.right - 8, bounds.bottom - 3));
      await thumb.up();
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, closeTo(0, .01));
      await tester.tap(find.text('Agent 9999'));
      await tester.pumpAndSettle();
      expect(chosen, 9999);
      expect(panel, findsNothing);
      await tester.binding.setSurfaceSize(const Size(500, 210));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpAndSettle();
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final compact = tester.getRect(panel);
      expect(compact.top, closeTo(PopupMenuSurface.verticalInset, .01));
      expect(compact.height, lessThan(bounds.height));
      expect(tester.takeException(), isNull);
    },
  );

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
      Color.lerp(theme.popupSurfaceColor, theme.basePrimary, .5),
    );
    await tester.pumpAndSettle();
    expect(background(tester, option), theme.basePrimary);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      background(tester, option),
      Color.lerp(theme.basePrimary, theme.popupSurfaceColor, .5),
    );
    await tester.pumpAndSettle();
    expect(background(tester, option), theme.popupSurfaceColor);

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
        localizationsDelegates: appLocalizationDelegates,
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
    final label = AppLocalizations.of(tester.element(find.byType(SettingsRow)))
        .resetThisSetting;
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
