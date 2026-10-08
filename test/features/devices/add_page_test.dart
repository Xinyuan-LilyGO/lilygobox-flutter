/*
 * @Description: 验证整页添加导航、真实结果驱动的连接界面及响应式布局。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 13:35:30
 * @LastEditTime: 2026-10-04 20:58:06
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/device_connection_coordinator.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/shell/widgets/sidebar_account_button.dart';
import 'package:lilygobox/app/widgets/window_page_stack.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/devices/data/lan_discovery.dart';
import 'package:lilygobox/features/devices/domain/discovery_service.dart';
import 'package:lilygobox/features/devices/presentation/pages/add_page.dart';
import 'package:lilygobox/features/devices/presentation/widgets/home_device_card.dart';
import 'package:lilygobox/features/devices/state/lan_connection.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'discovery_test.dart' show TestDiscoveryService, device;

class _Session extends LanConnection {
  final discoveryService = TestDiscoveryService();

  @override
  Stream<LanDevice> discover() => discoveryService.discover().cast<LanDevice>();

  @override
  Future<bool> connect(DiscoveredDevice target) async {
    publish(target as LanDevice, LanConnectionPhase.connecting);
    final result = await discoveryService.connect(target);
    publish(
      target,
      result ? LanConnectionPhase.connected : LanConnectionPhase.failed,
    );
    return result;
  }

  void publish(LanDevice target, LanConnectionPhase next) {
    this.device = target;
    phase = next;
    notifyListeners();
  }
}

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

  testWidgets(
    'saved offline devices are excluded by ID and saved-list changes refresh results',
    (tester) async {
      const saved = LanDevice(
        id: '001122334455',
        name: 'Saved P4',
        address: '192.168.1.8',
        port: 18464,
        model: 'T-Display-P4',
      );
      const renamed = LanDevice(
        id: '001122334455',
        name: 'Renamed P4',
        address: '192.168.1.20',
        port: 18464,
        model: 'T-Display-P4',
      );
      const other = LanDevice(
        id: 'aabbccddeeff',
        name: 'Saved P4',
        address: '192.168.1.9',
        port: 18464,
        model: 'T-Display-P4',
      );
      devices.addLanDevice(saved);
      final service = TestDiscoveryService();
      await tester.pumpWidget(
        app(page: AddDevicePage(discoveryService: service)),
      );
      await tester.pump();
      service.scans.last.add(renamed);
      await tester.pump();
      expect(find.text('Renamed P4'), findsNothing);
      service.scans.last.add(other);
      await service.scans.last.close();
      await tester.pumpAndSettle();
      expect(find.text('Saved P4'), findsOneWidget);
      devices.addLanDevice(other);
      await tester.pumpAndSettle();
      expect(find.text('Saved P4'), findsNothing);
      expect(find.text('暂未发现设备'), findsOneWidget);
      devices.removeDevice(saved.id);
      await tester.tap(find.text('重新查找'));
      await tester.pump();
      service.scans.last.add(renamed);
      await tester.pump();
      expect(find.text('Renamed P4'), findsOneWidget);
      expect(service.connections, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same-name devices show MAC through discovery and connection', (
    tester,
  ) async {
    const first = LanDevice(
      id: '001122334455',
      name: 'T-Display-P4',
      address: '192.168.1.8',
      port: 18464,
      model: 'T-Display-P4',
    );
    const second = LanDevice(
      id: 'aabbccddeeff',
      name: 'T-Display-P4',
      address: '192.168.1.9',
      port: 18464,
      model: 'T-Display-P4',
    );
    final service = TestDiscoveryService();
    await tester.pumpWidget(
      app(page: AddDevicePage(discoveryService: service)),
    );
    await tester.pump();
    service.scans.last.add(first);
    service.scans.last.add(second);
    await service.scans.last.close();
    await tester.pumpAndSettle();
    expect(find.text('T-Display-P4'), findsNWidgets(2));
    expect(find.text('MAC 00:11:22:33:44:55'), findsOneWidget);
    await tester.tap(find.text('MAC AA:BB:CC:DD:EE:FF'));
    await tester.pump();
    expect(find.text('正在连接设备…'), findsOneWidget);
    expect(find.text('MAC AA:BB:CC:DD:EE:FF'), findsOneWidget);
    expect(find.text('MAC 00:11:22:33:44:55'), findsNothing);
    service.connections.single.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('连接完成'), findsOneWidget);
    expect(find.text('MAC AA:BB:CC:DD:EE:FF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'connection before add-page initialization shows completion without losing ready',
    (tester) async {
      const target = LanDevice(
        id: '001122334455',
        name: 'T-Display-P4',
        address: '192.168.1.8',
        port: 18464,
        model: 'T-Display-P4',
      );
      final session = _Session();
      addTearDown(session.dispose);
      final coordinator = DeviceConnectionCoordinator(
        connection: session,
        devices: devices,
        navigation: navigation,
      );
      addTearDown(coordinator.dispose);
      // 模拟导航已进入添加流程，但添加页尚未构建就收到 ready。
      navigation.setPage(AppPage.addDevice);
      session.publish(target, LanConnectionPhase.connected);
      await tester.pumpWidget(
        ChangeNotifierProvider<LanConnection>.value(
          value: session,
          child: app(),
        ),
      );
      await tester.pumpAndSettle();
      expect(navigation.currentPage, AppPage.addDevice);
      expect(find.text('连接完成'), findsOneWidget);
      expect(find.text('IP 地址: 192.168.1.8'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('返回主页'));
      await tester.pumpAndSettle();
      expect(navigation.currentPage, AppPage.home);
      expect(find.byType(HomeDeviceCard), findsOneWidget);
      expect(devices.addedDevices, [target.id]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'connection beneath settings preserves the completion result when settings closes',
    () {
      const target = LanDevice(
        id: '001122334455',
        name: 'T-Display-P4',
        address: '192.168.1.8',
        port: 18464,
        model: 'T-Display-P4',
      );
      final session = _Session();
      final coordinator = DeviceConnectionCoordinator(
        connection: session,
        devices: devices,
        navigation: navigation,
      );
      navigation.setPage(AppPage.addDevice);
      navigation.setPage(AppPage.settings);
      session.publish(target, LanConnectionPhase.connected);
      expect(navigation.currentPage, AppPage.settings);
      expect(navigation.contentPage, AppPage.addDevice);
      navigation.closeSettings();
      expect(navigation.currentPage, AppPage.addDevice);
      expect(navigation.addedDeviceId, target.id);
      expect(devices.addedDevices, [target.id]);
      coordinator.dispose();
      session.dispose();
    },
  );

  testWidgets(
    'manual approval shows device details until the user returns home',
    (tester) async {
      const target = LanDevice(
        id: '001122334455',
        name: 'T-Display-P4',
        address: '192.168.1.8',
        port: 18464,
        model: 'T-Display-P4',
      );
      final session = _Session();
      addTearDown(session.dispose);
      final coordinator = DeviceConnectionCoordinator(
        connection: session,
        devices: devices,
        navigation: navigation,
      );
      addTearDown(coordinator.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<LanConnection>.value(
          value: session,
          child: app(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加设备'));
      await tester.pump();
      session.discoveryService.scans.single.add(target);
      await session.discoveryService.scans.single.close();
      await tester.pumpAndSettle();
      await tester.tap(find.text('T-Display-P4'));
      await tester.pump();
      expect(find.text('正在连接设备…'), findsOneWidget);
      expect(find.text('正在建立连接，请稍候。'), findsOneWidget);
      expect(find.text('请在设备上允许本次连接。'), findsNothing);
      session.publish(target, LanConnectionPhase.awaitingApproval);
      await tester.pump();
      expect(find.text('请在设备上允许本次连接。'), findsOneWidget);
      expect(find.text('正在建立连接，请稍候。'), findsNothing);
      session.publish(target, LanConnectionPhase.connecting);
      await tester.pump();
      expect(find.text('正在建立连接，请稍候。'), findsOneWidget);
      expect(find.text('请在设备上允许本次连接。'), findsNothing);
      expect(devices.addedDevices, isEmpty);
      session.discoveryService.connections.single.complete(true);
      await tester.pumpAndSettle();
      expect(navigation.currentPage, AppPage.addDevice);
      expect(find.text('连接完成'), findsOneWidget);
      expect(find.text('设备型号: T-Display-P4'), findsOneWidget);
      expect(find.text('IP 地址: 192.168.1.8'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('返回主页'));
      await tester.pumpAndSettle();
      expect(navigation.currentPage, AppPage.home);
      expect(find.byType(AddDevicePage), findsNothing);
      expect(find.byType(HomeDeviceCard), findsOneWidget);
      expect(find.text('在线'), findsOneWidget);
      expect(session.connected, isTrue);
      expect(devices.addedDevices, [target.id]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('background connection replaces the empty discovery page', (
    tester,
  ) async {
    const target = LanDevice(
      id: '001122334455',
      name: 'T-Display-P4',
      address: '192.168.1.8',
      port: 18464,
      model: 'T-Display-P4',
    );
    final session = _Session();
    addTearDown(session.dispose);
    final coordinator = DeviceConnectionCoordinator(
      connection: session,
      devices: devices,
      navigation: navigation,
    );
    addTearDown(coordinator.dispose);
    navigation.setPage(AppPage.addDevice);
    await tester.pumpWidget(
      ChangeNotifierProvider<LanConnection>.value(value: session, child: app()),
    );
    await tester.pump();
    await session.discoveryService.scans.single.close();
    await tester.pumpAndSettle();
    expect(find.text('暂未发现设备'), findsOneWidget);

    session.publish(target, LanConnectionPhase.awaitingApproval);
    await tester.pump();
    expect(find.text('连接完成'), findsNothing);
    session.publish(target, LanConnectionPhase.connected);
    await tester.pumpAndSettle();
    expect(find.text('连接完成'), findsOneWidget);
    expect(find.text('暂未发现设备'), findsNothing);
    expect(find.text('MAC 00:11:22:33:44:55'), findsOneWidget);
    expect(navigation.currentPage, AppPage.addDevice);
    // 旧搜索超时和心跳不能把完成界面改回空列表。
    await tester.pump(const Duration(seconds: 15));
    session.publish(target, LanConnectionPhase.connected);
    await tester.pumpAndSettle();
    expect(find.text('连接完成'), findsOneWidget);
    session.publish(target, LanConnectionPhase.offline);
    await tester.pumpAndSettle();
    expect(find.text('重新连接'), findsOneWidget);
    session.publish(target, LanConnectionPhase.connected);
    await tester.pumpAndSettle();
    expect(find.text('连接完成'), findsOneWidget);
    expect(devices.addedDevices, [target.id]);
    await tester.tap(find.text('返回主页'));
    await tester.pumpAndSettle();
    expect(navigation.currentPage, AppPage.home);
    expect(find.text('在线'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'an existing connection does not interrupt adding another device',
    (tester) async {
      const target = LanDevice(
        id: '001122334455',
        name: 'T-Display-P4',
        address: '192.168.1.8',
        port: 18464,
        model: 'T-Display-P4',
      );
      final session = _Session();
      addTearDown(session.dispose);
      session.publish(target, LanConnectionPhase.connected);
      devices.addLanDevice(target);
      final coordinator = DeviceConnectionCoordinator(
        connection: session,
        devices: devices,
        navigation: navigation,
      );
      addTearDown(coordinator.dispose);
      navigation.setPage(AppPage.addDevice);
      await tester.pumpWidget(
        app(page: AddDevicePage(discoveryService: session)),
      );
      await tester.pump();
      await session.discoveryService.scans.single.close();
      await tester.pumpAndSettle();
      // 心跳也会触发会话通知，不能因此把旧设备当作本轮连接成功。
      session.publish(target, LanConnectionPhase.connected);
      await tester.pumpAndSettle();
      expect(find.text('连接完成'), findsNothing);
      expect(find.text('暂未发现设备'), findsOneWidget);
      expect(navigation.currentPage, AppPage.addDevice);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'confirmed connection saves immediately and returns home only on request',
    (tester) async {
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
      expect(find.text('连接完成'), findsOneWidget);
      expect(devices.addedDevices, ['T-Display-P4']);
      expect(navigation.currentPage, AppPage.addDevice);
      await tester.tap(find.text('返回主页'));
      await tester.pumpAndSettle();
      expect(shell.selectedIndex, 0);
      expect(navigation.currentPage, AppPage.home);
      expect(tester.takeException(), isNull);
    },
  );

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
          expect(
            find.text(locale == 'zh' ? '连接帮助' : 'Connection help'),
            findsNothing,
          );
          await tester.tap(find.byKey(const ValueKey('device-help-menu')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('open-device-help')));
          await tester.pumpAndSettle();
          final panel = tester.getRect(
            find.byKey(const ValueKey('device-help-panel')),
          );
          expect(panel.width, 296);
          expect(panel.bottom, 468);
          await tester.tap(find.byKey(const ValueKey('close-device-help')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('device-help-panel')), findsNothing);
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
}
