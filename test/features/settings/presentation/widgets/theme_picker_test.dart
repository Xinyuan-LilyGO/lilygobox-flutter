/*
 * @Description: 验证主题卡片切换、重复选中限制及窄窗口布局。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-02 19:41:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/settings/widgets.dart';
import 'package:lilygobox/features/settings/presentation/widgets/personalization_content.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'theme cards switch immediately without per-setting reset at narrow width',
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

      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
