/*
 * @Description: 验证设备设置导航携带目标设备，并按设备分派页面及正确返回。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygo_box/app/navigation/provider.dart';
import 'package:lilygo_box/app/shell/pages/page.dart';
import 'package:lilygo_box/app/shell/state/provider.dart';
import 'package:lilygo_box/app/widgets/window_page_stack.dart';
import 'package:lilygo_box/core/layout/split_view_provider.dart';
import 'package:lilygo_box/core/theme/provider.dart';
import 'package:lilygo_box/core/widgets/animated_circle_icon_button.dart';
import 'package:lilygo_box/features/devices/domain/catalog.dart';
import 'package:lilygo_box/features/devices/presentation/widgets/unsupported_settings.dart';
import 'package:lilygo_box/features/devices/state/manager_provider.dart';
import 'package:lilygo_box/features/devices/t_glasses_p4/presentation/pages/settings_page.dart';
import 'package:lilygo_box/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  test('device settings requires a target and notifies on target changes', () {
    final navigation = AppNavigationProvider();
    addTearDown(navigation.dispose);
    var changes = 0;
    navigation.addListener(() => changes++);
    expect(
      () => navigation.setPage(AppPage.deviceSettings),
      throwsArgumentError,
    );
    expect(() => navigation.openDeviceSettings('  '), throwsArgumentError);
    expect(navigation.currentPage, AppPage.home);
    navigation.openDeviceSettings(DeviceCatalog.tGlassesP4Name);
    expect(navigation.settingsDeviceName, DeviceCatalog.tGlassesP4Name);
    navigation.openDeviceSettings(DeviceCatalog.tGlassesP4Name);
    expect(changes, 1);
    navigation.openDeviceSettings('Other device');
    expect(changes, 2);
    expect(navigation.settingsDeviceName, 'Other device');
    navigation.goHome();
    expect(navigation.settingsDeviceName, isNull);
    expect(navigation.currentPage, AppPage.home);
  });

  testWidgets(
    'window routes each device and closes supported and fallback settings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1150, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final navigation = AppNavigationProvider()
        ..openDeviceSettings(DeviceCatalog.tGlassesP4Name);
      final theme = ThemeProvider();
      final shell = AppShellProvider();
      final devices = DeviceManagerProvider();
      final split = SplitViewProvider();
      addTearDown(navigation.dispose);
      addTearDown(theme.dispose);
      addTearDown(shell.dispose);
      addTearDown(devices.dispose);
      addTearDown(split.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: navigation),
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: shell),
            ChangeNotifierProvider.value(value: devices),
            ChangeNotifierProvider.value(value: split),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Column(children: [WindowPageStack()])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DeviceSettingsTGlassesP4), findsOneWidget);
      await tester.tap(find.byType(AnimatedCircleIconButton));
      await tester.pumpAndSettle();
      expect(navigation.currentPage, AppPage.home);
      expect(find.byType(AppShell), findsOneWidget);

      navigation.openDeviceSettings(DeviceCatalog.tGlassesP4Name);
      await tester.pumpAndSettle();
      navigation.openDeviceSettings('Other device');
      await tester.pumpAndSettle();
      expect(find.byType(DeviceSettingsTGlassesP4), findsNothing);
      expect(find.byType(UnsupportedDeviceSettings), findsOneWidget);
      expect(find.text('Other device'), findsOneWidget);
      expect(find.text('此设备暂未提供设置选项。'), findsOneWidget);
      navigation.openDeviceSettings('Another device');
      await tester.pumpAndSettle();
      expect(find.text('Other device'), findsNothing);
      expect(find.text('Another device'), findsOneWidget);
      await tester.tap(find.byType(AnimatedCircleIconButton));
      await tester.pumpAndSettle();
      expect(navigation.currentPage, AppPage.home);
      expect(navigation.settingsDeviceName, isNull);
      expect(find.byType(AppShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
