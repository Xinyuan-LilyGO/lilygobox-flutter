/*
 * @Description: 验证整页添加导航、真实结果驱动的连接界面及响应式布局。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 13:35:30
 * @LastEditTime: 2026-10-02 13:35:30
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/shell/widgets/sidebar_account_button.dart';
import 'package:lilygobox/app/widgets/window_page_stack.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/devices/presentation/pages/add_page.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'discovery_test.dart' show TestDiscoveryService, device;

void main() {
  late ThemeProvider theme;
  late AppNavigationProvider navigation;
  late AppShellProvider shell;
  late DeviceManagerProvider devices;

  setUp(() {
    theme = ThemeProvider();
    navigation = AppNavigationProvider();
    shell = AppShellProvider();
    devices = DeviceManagerProvider();
  });

  tearDown(() {
    theme.dispose();
    navigation.dispose();
    shell.dispose();
    devices.dispose();
  });

  Widget app({Widget? page, String locale = 'zh', double textScale = 1}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: navigation),
          ChangeNotifierProvider.value(value: shell),
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
          home: Scaffold(
            body: page ?? const Column(children: [WindowPageStack()]),
          ),
        ),
      );

  testWidgets(
    'add page stays inside shell and supports sidebar, Escape and back',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加设备'));
      await tester.pumpAndSettle();
      expect(find.byType(AddDevicePage), findsOneWidget);
      expect(find.byType(SidebarAccountButton), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(WindowPageStack),
          matching: find.byType(ModalBarrier),
        ),
        findsNothing,
      );
      expect(find.text('自动发现暂不可用'), findsOneWidget);
      expect(find.text('USB'), findsNothing);
      expect(devices.addedDevices, isEmpty);
      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      expect(navigation.currentPage, AppPage.home);
      await tester.tap(find.text('添加设备'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(navigation.currentPage, AppPage.home);
      await tester.tap(find.text('添加设备'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(navigation.currentPage, AppPage.home);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('device is added and opened only after confirmed connection', (
    tester,
  ) async {
    final service = TestDiscoveryService();
    navigation.setPage(AppPage.addDevice);
    await tester.pumpWidget(
      app(page: AddDevicePage(discoveryService: service)),
    );
    await tester.pump();
    service.scans.last.add(device);
    await tester.pump();
    await tester.tap(find.text('T-Display-P4'));
    await tester.pump();
    expect(find.text('正在连接设备…'), findsOneWidget);
    expect(devices.addedDevices, isEmpty);
    service.connections.single.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('设备已连接'), findsOneWidget);
    await tester.tap(find.text('打开设备'));
    await tester.pumpAndSettle();
    expect(devices.addedDevices, ['T-Display-P4']);
    expect(shell.selectedIndex, 1);
    expect(navigation.currentPage, AppPage.home);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unavailable and help fit both themes, languages and large text',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(320, 480));
      for (final mode in ThemeType.values) {
        theme.setTheme(mode);
        for (final locale in ['zh', 'en']) {
          await tester.pumpWidget(
            app(
              page: AddDevicePage(key: UniqueKey()),
              locale: locale,
              textScale: 2,
            ),
          );
          await tester.pumpAndSettle();
          final help = find.text(locale == 'zh' ? '查看连接帮助' : 'Connection help');
          await tester.ensureVisible(help);
          await tester.pumpAndSettle();
          await tester.tap(help);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('discovered device and connection failure fit narrow pages', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 480));
    for (final locale in ['zh', 'en']) {
      final service = TestDiscoveryService();
      await tester.pumpWidget(
        app(
          page: AddDevicePage(key: UniqueKey(), discoveryService: service),
          locale: locale,
          textScale: 2,
        ),
      );
      await tester.pump();
      service.scans.last.add(device);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('T-Display-P4'));
      await tester.pump();
      await tester.tap(find.text('T-Display-P4'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      service.connections.last.complete(false);
      await tester.pumpAndSettle();
      final retry = find.text(locale == 'zh' ? '重新连接' : 'Try again');
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      expect(retry, findsOneWidget);
      expect(devices.addedDevices, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  Future<void> preview(WidgetTester tester, String phase) async {
    await tester.tap(find.byKey(const ValueKey('discovery-preview-menu')));
    await tester.pump(const Duration(milliseconds: 250));
    final option = find.byKey(ValueKey('preview-$phase'));
    await tester.ensureVisible(option);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(option);
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('debug preview selects every state without adding real devices', (
    tester,
  ) async {
    navigation.setPage(AppPage.addDevice);
    devices.addDevice('Existing device');
    await tester.pumpWidget(app(page: const AddDevicePage()));
    await tester.pumpAndSettle();
    for (final entry in {
      'searching': '正在查找设备…',
      'found': 'T-Display-P4',
      'empty': '暂未发现设备',
      'connecting': '正在连接设备…',
      'connectionFailed': '未能连接设备',
      'connected': '设备已连接',
      'failed': '暂时无法查找设备',
      'unavailable': '自动发现暂不可用',
    }.entries) {
      await preview(tester, entry.key);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('预览模式 · 模拟数据'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await preview(tester, 'connected');
    await tester.tap(find.text('打开设备'));
    await tester.pump();
    expect(devices.addedDevices, ['Existing device']);
    expect(shell.selectedIndex, 0);
    expect(navigation.currentPage, AppPage.addDevice);
    expect(find.text('这是状态预览，不会添加设备或打开真实设备页面。'), findsOneWidget);
    await preview(tester, 'exit');
    await tester.pumpAndSettle();
    expect(find.text('预览模式 · 模拟数据'), findsNothing);
    expect(find.text('自动发现暂不可用'), findsOneWidget);
    expect(find.text('T-Display-P4'), findsNothing);
  });

  testWidgets(
    'preview retry and connect animate locally and cancel on mode switch',
    (tester) async {
      final service = TestDiscoveryService();
      await tester.pumpWidget(
        app(page: AddDevicePage(discoveryService: service)),
      );
      await tester.pump();
      await preview(tester, 'empty');
      expect(service.cancelledScans, 1);
      await tester.tap(find.text('重新查找'));
      await tester.pump();
      expect(find.text('正在查找设备…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.tap(find.text('T-Display-P4'));
      await tester.pump();
      expect(find.text('正在连接设备…'), findsOneWidget);
      await tester.tap(find.text('取消连接'));
      await tester.pump();
      expect(find.text('T-Display-P4'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('设备已连接'), findsNothing);
      await tester.tap(find.text('T-Display-P4'));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      expect(find.text('设备已连接'), findsOneWidget);
      expect(service.connections, isEmpty);
      expect(devices.addedDevices, isEmpty);
      await preview(tester, 'found');
      await tester.tap(find.text('T-Display-P4'));
      await tester.pump();
      await preview(tester, 'exit');
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('设备已连接'), findsNothing);
      expect(service.scans, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(service.cancelledScans, 2);
    },
  );

  testWidgets('preview menu scrolls on narrow pages with large text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 480));
    for (final locale in ['zh', 'en']) {
      await tester.pumpWidget(
        app(
          page: AddDevicePage(key: UniqueKey()),
          locale: locale,
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await preview(tester, 'connected');
      expect(
        find.text(locale == 'zh' ? '设备已连接' : 'Device connected'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await preview(tester, 'exit');
      await tester.pumpAndSettle();
      expect(
        find.text(locale == 'zh' ? '自动发现暂不可用' : 'Device discovery unavailable'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
