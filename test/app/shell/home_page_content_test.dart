/*
 * @Description: 验证首页添加入口、设备状态及窄窗口和大字体布局。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 01:00:00
 * @LastEditTime: 2026-10-06 14:02:45
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/pages/home_page_content.dart';
import 'package:lilygobox/app/shell/pages/page.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/shell/widgets/sidebar_navigation_item.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/devices/data/lan_discovery.dart';
import 'package:lilygobox/features/devices/presentation/pages/connected_page.dart';
import 'package:lilygobox/features/devices/presentation/widgets/home_device_card.dart';
import 'package:lilygobox/features/devices/state/lan_connection.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class _Connection extends LanConnection {
  void showStatus(LanDevice target, LanConnectionPhase value) {
    device = target;
    phase = value;
    notifyListeners();
  }
}

const _device = LanDevice(
  id: 'aabbccddeeff',
  name: 'Desk P4',
  address: '192.168.1.8',
  port: 18464,
  model: 'T-Display-P4',
);

void main() {
  late ThemeProvider theme;
  late AppNavigationProvider navigation;
  late DeviceManagerProvider devices;
  late AppShellProvider shell;
  late _Connection connection;

  setUp(() {
    theme = ThemeProvider();
    navigation = AppNavigationProvider();
    devices = DeviceManagerProvider();
    shell = AppShellProvider();
    connection = _Connection();
  });

  tearDown(() {
    theme.dispose();
    navigation.dispose();
    devices.dispose();
    shell.dispose();
    connection.dispose();
  });

  Widget app({
    String locale = 'en',
    double textScale = 1,
    bool withShell = false,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider.value(value: navigation),
      ChangeNotifierProvider.value(value: devices),
      ChangeNotifierProvider.value(value: shell),
      ChangeNotifierProvider<LanConnection>.value(value: connection),
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
      home: Scaffold(
        body: withShell ? const AppShell() : const HomePageContent(),
      ),
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
    expect(find.byType(HomeDeviceCard), findsOneWidget);
    expect(find.text('Add Device'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-add-device')));
    expect(navigation.currentPage, AppPage.addDevice);
    devices.clearDevices();
    await tester.pumpAndSettle();
    expect(find.text('No devices yet'), findsOneWidget);
  });

  testWidgets('cards reflect session status and search by name and model', (
    tester,
  ) async {
    devices.addLanDevice(_device);
    devices.addLanDevice(
      const LanDevice(
        id: '001122334455',
        name: 'Spare P4',
        address: '192.168.1.9',
        port: 18464,
        model: 'T-Display-P4',
      ),
    );
    connection.showStatus(_device, LanConnectionPhase.connected);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(HomeDeviceCard), findsNWidgets(2));
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Desk P4'), findsOneWidget);
    expect(find.text('Spare P4'), findsOneWidget);
    connection.showStatus(_device, LanConnectionPhase.offline);
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsNWidgets(2));
    await tester.enterText(find.byType(TextField), 'missing device');
    await tester.pumpAndSettle();
    expect(find.text('No matching devices'), findsOneWidget);
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'spare');
    await tester.pumpAndSettle();
    expect(find.byType(HomeDeviceCard), findsOneWidget);
    await tester.enterText(find.byType(TextField), 't-display');
    await tester.pumpAndSettle();
    expect(find.byType(HomeDeviceCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'devices open from home, not sidebar; returning retains search and session',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1150, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      devices.addLanDevice(_device);
      connection.showStatus(_device, LanConnectionPhase.connected);
      await tester.pumpWidget(app(withShell: true));
      await tester.pumpAndSettle();
      expect(find.byType(SidebarNavigationItem), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Desk');
      await tester.pumpAndSettle();
      final homeState = tester.state(find.byType(HomePageContent));
      await tester.tap(find.byType(HomeDeviceCard));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectedDevicePage), findsOneWidget);
      expect(
        tester
            .widget<SidebarNavigationItem>(find.byType(SidebarNavigationItem))
            .isSelected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('device-back-home')));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(HomePageContent)), same(homeState));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Desk',
      );
      expect(connection.connected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'device cards and floating add fit narrow windows with large text',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      devices.addLanDevice(
        const LanDevice(
          id: 'aabbccddeeff',
          name:
              'A very long device name that must wrap without overlapping buttons',
          address: '192.168.1.8',
          port: 18464,
          model: 'T-Display-P4',
        ),
      );
      for (final size in [const Size(320, 480), const Size(1000, 260)]) {
        await tester.binding.setSurfaceSize(size);
        for (final mode in ThemeType.values) {
          theme.setTheme(mode);
          for (final locale in ['en', 'zh']) {
            await tester.pumpWidget(app(locale: locale, textScale: 2));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final add = find.byKey(const ValueKey('home-add-device'));
            expect(tester.getSize(add), const Size(48, 48));
            await tester.tap(add);
            expect(navigation.currentPage, AppPage.addDevice);
            navigation.goHome();
          }
        }
      }
    },
  );

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
