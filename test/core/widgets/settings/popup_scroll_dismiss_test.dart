import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/theme/definition.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/popup_menu_surface.dart';
import 'package:lilygobox/core/widgets/settings/more_button.dart';
import 'package:lilygobox/core/widgets/settings/select.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final theme = MaterialPalette.create(ThemeType.light);

  Widget app(Widget child) => MaterialApp(
    scrollBehavior: const AppScrollBehavior(),
    locale: const Locale('en'),
    localizationsDelegates: appLocalizationDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets(
    'either ancestor scroll closes select without changing its value',
    (tester) async {
      final outer = ScrollController();
      final inner = ScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      var changes = 0;
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            controller: outer,
            child: Column(
              children: [
                SizedBox(
                  height: 280,
                  child: SingleChildScrollView(
                    controller: inner,
                    child: Column(
                      children: [
                        const SizedBox(height: 60),
                        SizedBox(
                          width: 240,
                          child: SettingSelect<int>(
                            theme: theme,
                            value: 0,
                            items: const [
                              DropdownMenuItem(
                                value: 0,
                                child: Text('Selected'),
                              ),
                              DropdownMenuItem(
                                value: 1,
                                child: Text('Alternative'),
                              ),
                            ],
                            onChanged: (_) => changes++,
                          ),
                        ),
                        const SizedBox(height: 600),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      );
      for (final controller in [inner, outer]) {
        await tester.tap(find.byType(SettingSelect<int>));
        await tester.pumpAndSettle();
        expect(find.text('Alternative'), findsOneWidget);
        controller.jumpTo(20);
        await tester.pumpAndSettle();
        expect(find.text('Alternative'), findsNothing);
        expect(changes, 0);
        expect(find.text('Selected'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('smooth wheel on hosting list closes its open select', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        ListView(
          controller: controller,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 30, 400, 0),
              child: SettingSelect<int>(
                theme: theme,
                value: 0,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Selected')),
                  DropdownMenuItem(value: 1, child: Text('Alternative')),
                ],
                onChanged: (_) {},
              ),
            ),
            const SizedBox(height: 1500),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(SettingSelect<int>));
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(700, 300),
        scrollDelta: Offset(0, 100),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(find.text('Alternative'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling inside popup content keeps the popup usable', (
    tester,
  ) async {
    final inner = ScrollController();
    addTearDown(inner.dispose);
    var value = 0;
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: SizedBox(
            height: 1000,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 240,
                child: SettingSelect<int>(
                  theme: theme,
                  value: value,
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('Selected')),
                    DropdownMenuItem(
                      value: 1,
                      child: SizedBox(
                        height: 24,
                        child: SingleChildScrollView(
                          controller: inner,
                          child: const Column(
                            children: [
                              Text('Scrollable option'),
                              SizedBox(height: 200),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (next) => value = next!,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(SettingSelect<int>));
    await tester.pumpAndSettle();
    inner.jumpTo(20);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuSurface), findsOneWidget);
    expect(value, 0);
    await tester.tap(find.text('Selected').last);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuSurface), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling a settings row dismisses its more menu', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        ListView(
          controller: controller,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SettingMoreButton(theme: theme, onReset: () {}),
            ),
            const SizedBox(height: 1500),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(SettingMoreButton));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuSurface), findsOneWidget);
    controller.jumpTo(30);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuSurface), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
