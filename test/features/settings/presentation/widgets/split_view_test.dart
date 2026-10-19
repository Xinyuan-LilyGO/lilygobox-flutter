/*
 * @Description: 验证设置侧栏拖动、窄屏导航、主题语言切换和确认后仅重置应用偏好。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 19:41:48
 * @LastEditTime: 2026-10-03 16:53:55
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/core/app_info/package_info_provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/account/state/provider.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/features/settings/presentation/pages/page.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppNavigationProvider navigation;
  late DeviceManagerProvider devices;
  late PackageInfoProvider info;
  setUp(() {
    theme = ThemeProvider();
    language = LanguageProvider()..changeLanguage('zh');
    navigation = AppNavigationProvider()..setPage(AppPage.settings);
    devices = DeviceManagerProvider()..addDevice('T-Display-P4');
    info = PackageInfoProvider();
  });
  tearDown(() {
    theme.dispose();
    language.dispose();
    navigation.dispose();
    devices.dispose();
    info.dispose();
  });

  Widget app({double textScale = 1}) => MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => AccountProvider.production(clientId: ''),
      ),
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider.value(value: language),
      ChangeNotifierProvider.value(value: navigation),
      ChangeNotifierProvider.value(value: devices),
      ChangeNotifierProvider.value(value: info),
    ],
    child: Consumer<LanguageProvider>(
      builder: (context, languages, _) => MaterialApp(
        locale: languages.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: SettingsPage()),
      ),
    ),
  );

  testWidgets(
    'settings content stays at the top throughout category fades',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('个人中心').last).dy, lessThan(100));
      await tester.tap(find.byKey(const ValueKey('settings-category-general')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getTopLeft(find.text('通用').last).dy, lessThan(100));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-profile')));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('个人中心').last).dy, lessThan(100));
    },
  );

  testWidgets(
    'sidebar stays visible at drag limits and adapts after resizing window',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('settings-resize-handle'));
      final sidebar = find.byKey(const ValueKey('settings-sidebar'));
      await tester.drag(handle, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 176);
      await tester.drag(handle, const Offset(700, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 300);
      await tester.binding.setSurfaceSize(const Size(610, 500));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 244);
      await tester.tap(find.byKey(const ValueKey('settings-about')));
      await tester.pumpAndSettle();
      expect(find.text('版本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restore requires confirmation and preserves devices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    theme.setTheme(ThemeType.light);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-category-general')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-defaults')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cancel-restore-defaults')));
    await tester.pumpAndSettle();
    expect(theme.currentTheme, ThemeType.light);
    expect(language.locale.languageCode, 'zh');
    await tester.tap(find.byKey(const ValueKey('restore-defaults')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-defaults')));
    await tester.pumpAndSettle();
    expect(theme.currentTheme, ThemeType.dark);
    expect(language.locale.languageCode, 'en');
    expect(devices.addedDevices, ['T-Display-P4']);
    expect(find.text('Restore defaults'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile categories and language controls fit large text in both themes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final mode in ThemeType.values) {
        for (final locale in ['en', 'zh']) {
          await tester.pumpWidget(const SizedBox.shrink());
          theme.setTheme(mode);
          language.changeLanguage(locale);
          await tester.pumpWidget(app(textScale: 2));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('settings-resize-handle')),
            findsNothing,
          );
          await tester.tap(
            find.byKey(const ValueKey('settings-category-appearance')),
          );
          await tester.pumpAndSettle();
          final light = find.byKey(const ValueKey('theme-choice-light'));
          await tester.ensureVisible(light);
          await tester.tap(light);
          await tester.pumpAndSettle();
          expect(theme.currentTheme, ThemeType.light);
          await tester.tap(find.byTooltip(locale == 'en' ? 'Back' : '返回'));
          await tester.pumpAndSettle();
          final languageCategory = find.byKey(
            const ValueKey('settings-category-language'),
          );
          await tester.ensureVisible(languageCategory);
          await tester.tap(languageCategory);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip(locale == 'en' ? 'Back' : '返回'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('settings-category-appearance')),
            findsOneWidget,
          );
        }
      }
    },
  );
  testWidgets(
    'settings opens on profile and account actions do not fake sign-in',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-sign-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-sidebar')), findsOneWidget);
      expect(navigation.currentPage, AppPage.settings);
      await tester.tap(find.byKey(const ValueKey('profile-sign-in')));
      await tester.pumpAndSettle();
      expect(find.text('GitHub 登录尚未配置，请暂时使用本地设备功能。'), findsOneWidget);
      expect(find.text('未登录'), findsWidgets);
      expect(devices.addedDevices, ['T-Display-P4']);
      await tester.tap(find.byKey(const ValueKey('github-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-category-language')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-sign-in')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-sign-in')));
      await tester.pumpAndSettle();
      expect(find.text('GitHub 登录尚未配置，请暂时使用本地设备功能。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile supports mobile return with large text in both languages and themes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final mode in ThemeType.values) {
        for (final locale in ['zh', 'en']) {
          await tester.pumpWidget(const SizedBox.shrink());
          theme.setTheme(mode);
          language.changeLanguage(locale);
          await tester.pumpWidget(app(textScale: 2));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('settings-profile')));
          await tester.pumpAndSettle();
          final register = find.byKey(const ValueKey('profile-sign-in'));
          await tester.ensureVisible(register);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip(locale == 'en' ? 'Back' : '返回'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('settings-profile')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('profile-sign-in')), findsNothing);
          expect(navigation.currentPage, AppPage.settings);
        }
      }
    },
  );
}
