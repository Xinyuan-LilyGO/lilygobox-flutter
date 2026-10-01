/*
 * @Description: 验证主题卡片切换、重复选中限制、重置及窄窗口布局。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygo_box/core/theme/provider.dart';
import 'package:lilygo_box/core/widgets/settings/widgets.dart';
import 'package:lilygo_box/features/settings/presentation/widgets/personalization_content.dart';
import 'package:lilygo_box/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'theme cards switch immediately and retain reset at narrow width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final themes = ThemeProvider();
      addTearDown(themes.dispose);
      var changes = 0;
      themes.addListener(() => changes++);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: themes,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer<ThemeProvider>(
                builder: (context, provider, child) =>
                    PersonalizationContent(theme: provider.themeData),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SettingSelect<ThemeType>), findsNothing);
      expect(find.text('浅色'), findsOneWidget);
      expect(find.text('深色'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final light = find.byKey(const ValueKey('theme-choice-light'));
      final dark = find.byKey(const ValueKey('theme-choice-dark'));
      await tester.tap(light);
      await tester.pumpAndSettle();
      expect(themes.currentTheme, ThemeType.light);
      expect(changes, 1);
      await tester.tap(light);
      await tester.pumpAndSettle();
      expect(changes, 1);
      await tester.tap(dark);
      await tester.pumpAndSettle();
      expect(themes.currentTheme, ThemeType.dark);

      await tester.tap(light);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重置此选项栏'));
      await tester.pumpAndSettle();
      expect(themes.currentTheme, ThemeType.dark);
      expect(tester.takeException(), isNull);
    },
  );
}
