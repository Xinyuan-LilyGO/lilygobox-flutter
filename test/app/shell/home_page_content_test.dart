/*
 * @Description: 验证首页添加入口、设备状态及窄窗口和大字体布局。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 01:00:00
 * @LastEditTime: 2026-10-02 01:00:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/pages/home_page_content.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  late ThemeProvider theme;
  late AppNavigationProvider navigation;
  late DeviceManagerProvider devices;

  setUp(() {
    theme = ThemeProvider();
    navigation = AppNavigationProvider();
    devices = DeviceManagerProvider();
  });

  tearDown(() {
    theme.dispose();
    navigation.dispose();
    devices.dispose();
  });

  Widget app({String locale = 'en', double textScale = 1}) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider.value(value: navigation),
      ChangeNotifierProvider.value(value: devices),
    ],
    child: MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(body: HomePageContent()),
    ),
  );

  testWidgets('empty state opens existing add flow and updates after adding', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('No devices yet'), findsOneWidget);
    await tester.tap(find.text('Add Device'));
    await tester.pumpAndSettle();
    expect(navigation.currentPage, AppPage.addDevice);
    devices.addDevice('T-Display-P4');
    navigation.goHome();
    await tester.pumpAndSettle();
    expect(find.text('No devices yet'), findsNothing);
    expect(find.text('Your devices are ready'), findsOneWidget);
    devices.clearDevices();
    await tester.pumpAndSettle();
    expect(find.text('No devices yet'), findsOneWidget);
  });

  testWidgets('both languages and themes fit narrow windows with large text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(320, 480), const Size(1000, 260)]) {
      await tester.binding.setSurfaceSize(size);
      for (final mode in ThemeType.values) {
        theme.setTheme(mode);
        for (final locale in ['en', 'zh']) {
          await tester.pumpWidget(app(locale: locale, textScale: 2));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final button = find.text(locale == 'en' ? 'Add Device' : '添加设备');
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.tap(button);
          expect(navigation.currentPage, AppPage.addDevice);
          expect(tester.takeException(), isNull);
          navigation.goHome();
        }
      }
    }
  });
}
