/*
 * @Description: 验证设备设置导航携带目标设备，并按设备分派页面及正确返回。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 17:29:40
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/pages/page.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/widgets/window_page_stack.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/animated_circle_icon_button.dart';
import 'package:lilygobox/features/devices/presentation/widgets/unsupported_settings.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
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
    navigation.openDeviceSettings('Device A');
    expect(navigation.settingsDeviceName, 'Device A');
    navigation.openDeviceSettings('Device A');
    expect(changes, 1);
    navigation.openDeviceSettings('Other device');
    expect(changes, 2);
    expect(navigation.settingsDeviceName, 'Other device');
    navigation.goHome();
    expect(navigation.settingsDeviceName, isNull);
    expect(navigation.currentPage, AppPage.home);
  });

  testWidgets('window routes arbitrary device settings to the fallback page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1150, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final navigation = AppNavigationProvider()..openDeviceSettings('Device A');
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
    expect(find.byType(UnsupportedDeviceSettings), findsOneWidget);
    expect(find.text('Device A'), findsOneWidget);
    await tester.tap(find.byType(AnimatedCircleIconButton));
    await tester.pumpAndSettle();
    expect(navigation.currentPage, AppPage.home);
    expect(find.byType(AppShell), findsOneWidget);

    navigation.openDeviceSettings('Device A');
    await tester.pumpAndSettle();
    navigation.openDeviceSettings('Other device');
    await tester.pumpAndSettle();
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
  });
}
