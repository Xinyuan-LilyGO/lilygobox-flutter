/*
 * @Description: 验证设备详情导航、旋转确认、真实会话操作及窄窗口和大字体布局。
 * @Author: LILYGO_L
 * @Date: 2026-10-07 18:00:00
 * @LastEditTime: 2026-10-13 12:00:00
 * @License: GPL 3.0
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/features/devices/data/lan_discovery.dart';
import 'package:lilygobox/features/devices/data/firmware_update_service.dart';
import 'package:lilygobox/features/devices/domain/discovery_service.dart';
import 'package:lilygobox/features/devices/domain/device_control.dart';
import 'package:lilygobox/features/devices/presentation/pages/connected_page.dart';
import 'package:lilygobox/features/devices/presentation/widgets/device_detail_navigation.dart';
import 'package:lilygobox/features/devices/presentation/widgets/device_page_frame.dart';
import 'package:lilygobox/features/devices/state/lan_connection.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:lilygobox/features/devices/presentation/widgets/device_name_dialog.dart';

const _device = LanDevice(
  id: '001122334455',
  name: 'Desk P4',
  address: '192.0.2.1',
  port: 18464,
  model: 'T-Display-P4',
);

class _Session extends LanConnection {
  int disconnects = 0;
  int connections = 0;
  DeviceControlState? snapshot;
  final controls = <(DeviceControlField, Object)>[];
  Completer<FirmwareRelease?>? updateCheck;
  int updateChecks = 0;
  String? checkError;

  @override
  Future<FirmwareRelease?> checkFirmwareUpdate() async {
    updateChecks++;
    firmwareUpdateChecking = true;
    firmwareUpdateError = null;
    notifyListeners();
    firmwareRelease = await updateCheck!.future;
    firmwareUpdateError = checkError;
    firmwareUpdateChecking = false;
    notifyListeners();
    return firmwareRelease;
  }

  @override
  DeviceControlState? controlStateFor(String id) =>
      device?.id == id ? snapshot : null;

  @override
  bool controlsReadyFor(String id) =>
      connected && device?.id == id && snapshot?.ready == true;

  @override
  void setControl(DeviceControlField field, Object value) {
    controls.add((field, value));
  }

  void publish(LanConnectionPhase next) {
    phase = next;
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    publish(LanConnectionPhase.offline);
  }

  @override
  Future<bool> connect(DiscoveredDevice target) async {
    connections++;
    device = target as LanDevice;
    publish(LanConnectionPhase.connected);
    return true;
  }
}

void main() {
  late ThemeProvider theme;
  late DeviceManagerProvider devices;
  late AppNavigationProvider navigation;
  late _Session session;

  setUp(() {
    theme = ThemeProvider()..setTheme(ThemeType.light);
    devices = DeviceManagerProvider()..addLanDevice(_device);
    navigation = AppNavigationProvider();
    session = _Session()
      ..device = _device
      ..phase = LanConnectionPhase.connected
      ..firmware = '1.1.2'
      ..uptimeMs = 64000;
  });

  tearDown(() {
    theme.dispose();
    devices.dispose();
    navigation.dispose();
    session.dispose();
  });

  Widget app({
    String language = 'en',
    double scale = 1,
    ValueNotifier<bool>? nestedView,
    ValueNotifier<DevicePageTitle?>? pageTitle,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider.value(value: devices),
      ChangeNotifierProvider.value(value: navigation),
      ChangeNotifierProvider<LanConnection>.value(value: session),
    ],
    child: MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: theme.themeData.secondary,
        body: DevicePageFrame(
          active: true,
          pageTitle: pageTitle,
          onBack: navigation.goHome,
          child: ConnectedDevicePage(
            deviceId: '001122334455',
            pageTitle: pageTitle,
            nestedView: nestedView,
          ),
        ),
      ),
    ),
  );

  Future<void> select(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey('device-tab-$tab')));
    await tester.pumpAndSettle();
  }

  Future<void> openUpdateCheck(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-card-information')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Symbols.refresh));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'manual update check uses theme gray and reports latest in dialog',
    (tester) async {
      session.updateCheck = Completer<FirmwareRelease?>();
      await openUpdateCheck(tester);
      final button = tester.widget<MenuItemSurface>(
        find.ancestor(
          of: find.byIcon(Symbols.refresh),
          matching: find.byType(MenuItemSurface),
        ),
      );
      expect(
        button.backgroundColor,
        Color.alphaBlend(
          theme.themeData.secondary.withValues(alpha: .6),
          theme.themeData.primary,
        ),
      );
      expect(button.foregroundColor, theme.themeData.iconColor);
      expect(find.text('正在检查更新…'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      session.updateCheck!.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('当前已是最新版本'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('检查更新'), findsOneWidget);
      expect(find.byIcon(Symbols.download), findsNothing);
    },
  );

  testWidgets(
    'manual update check shows release in same dialog and blue download',
    (tester) async {
      session.updateCheck = Completer<FirmwareRelease?>();
      await openUpdateCheck(tester);
      final route = ModalRoute.of(tester.element(find.byType(AlertDialog)));
      session.updateCheck!.complete(
        FirmwareRelease(
          version: '1.1.3',
          mainVersion: '1.1.3',
          mainUrl: Uri.https('example.com', '/main'),
          mainSize: 3,
          mainSha256: 'hash',
          wirelessVersion: '2.12.3',
          wirelessUrl: Uri.https('example.com', '/wireless'),
          wirelessSize: 3,
          wirelessSha256: 'hash',
          notes: const ['改进设备连接'],
        ),
      );
      session.wirelessFirmware = '2.12.3';
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(AlertDialog))),
        same(route),
      );
      expect(find.text('发现固件更新'), findsOneWidget);
      expect(find.textContaining('v1.1.2  →  v1.1.3'), findsOneWidget);
      expect(find.textContaining('改进设备连接'), findsOneWidget);
      expect(find.textContaining('无线固件版本\n'), findsNothing);
      expect(find.text('有新版本'), findsOneWidget);
      final button = tester.widget<MenuItemSurface>(
        find.ancestor(
          of: find.byIcon(Symbols.download),
          matching: find.byType(MenuItemSurface),
        ),
      );
      expect(button.backgroundColor, const Color(0xFF4B9AF5));
      expect(button.onPressed, isNull);
      expect(button.foregroundColor, Colors.white);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byIcon(Symbols.download), findsOneWidget);
    },
  );

  testWidgets('manual update check reports failure and can retry', (
    tester,
  ) async {
    session.updateCheck = Completer<FirmwareRelease?>();
    await openUpdateCheck(tester);
    session.checkError = 'network failure';
    session.updateCheck!.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('检查更新失败'), findsOneWidget);
    expect(find.text('当前已是最新版本'), findsNothing);
    session.checkError = null;
    session.updateCheck = Completer<FirmwareRelease?>();
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(find.text('正在检查更新…'), findsOneWidget);
    session.updateCheck!.complete(null);
    await tester.pumpAndSettle();
    expect(session.updateChecks, 2);
    expect(find.text('当前已是最新版本'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('manual update check reuses running check and dismisses safely', (
    tester,
  ) async {
    session.updateCheck = Completer<FirmwareRelease?>();
    final pending = session.checkFirmwareUpdate();
    await openUpdateCheck(tester);
    expect(session.updateChecks, 1);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    session.updateCheck!.complete(null);
    await pending;
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual update check rejects result after device disconnects', (
    tester,
  ) async {
    session.updateCheck = Completer<FirmwareRelease?>();
    await openUpdateCheck(tester);
    session.publish(LanConnectionPhase.offline);
    await tester.pumpAndSettle();
    expect(find.textContaining('设备已断开或已切换'), findsOneWidget);
    session.updateCheck!.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('当前已是最新版本'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('retained device titles update when language changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final title = ValueNotifier<DevicePageTitle?>(null);
    final nested = ValueNotifier(false);
    addTearDown(title.dispose);
    addTearDown(nested.dispose);
    await tester.pumpWidget(app(pageTitle: title, nestedView: nested));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-card-information')));
    await tester.pumpAndSettle();
    expect(title.value, DevicePageTitle.information);
    for (final language in ['zh', 'en', 'zh']) {
      await tester.pumpWidget(
        app(language: language, pageTitle: title, nestedView: nested),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ConnectedDevicePage)),
      );
      expect(
        find.descendant(
          of: find.byType(ValueListenableBuilder<DevicePageTitle?>),
          matching: find.text(l10n.deviceInfoTab),
        ),
        findsOneWidget,
      );
      expect(
        find.text(language == 'zh' ? 'Device information' : '设备信息'),
        findsNothing,
      );
    }
    expect(title.value, DevicePageTitle.information);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'connection endpoints are filled and name editing is capability gated',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      session.snapshot = DeviceControlState.parse({
        'ready': true,
        'capabilities': {
          'screen': true,
          'audio': false,
          'haptic': false,
          'identity': true,
        },
        'screenEnabled': true,
        'soundEnabled': true,
        'hapticEnabled': true,
        'brightness': 75,
        'rotation': 90,
        'volume': 65,
        'hapticStrength': 60,
        'deviceName': 'Desk P4',
        'battery': {'available': false},
      });
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('device-card-information')));
      await tester.pumpAndSettle();
      final connectionEntry = find.text('Device connection');
      final deviceName = find.text('Desk P4').first;
      expect(
        tester.getTopLeft(connectionEntry).dx,
        lessThan(tester.getSize(find.byType(ConnectedDevicePage)).width / 2),
      );
      expect(
        tester.getTopLeft(connectionEntry).dy,
        greaterThan(tester.getBottomLeft(deviceName).dy),
      );
      await tester.tap(find.byKey(const ValueKey('device-name-edit')));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceNameDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      session.publish(LanConnectionPhase.offline);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('device-name-edit')), findsNothing);
      final disabledCards = find.ancestor(
        of: find.text('Desk P4'),
        matching: find.byType(Opacity),
      );
      expect(disabledCards, findsNWidgets(2));
      expect(
        tester
            .widgetList<Opacity>(disabledCards)
            .every((widget) => widget.opacity == .4),
        isTrue,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ConnectedDevicePage)),
      )!;
      await tester.tap(find.text(l10n.deviceInformationConnection));
      await tester.pumpAndSettle();
      for (final symbol in [Symbols.laptop, Symbols.desktop_windows]) {
        expect(tester.widget<Icon>(find.byIcon(symbol)).fill, 1);
      }

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rotation requires confirmation and ignores a disconnected session',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      session.snapshot = DeviceControlState.parse({
        'ready': true,
        'capabilities': {'screen': true, 'audio': false, 'haptic': false},
        'screenEnabled': true,
        'brightness': 75,
        'rotation': 0,
        'soundEnabled': true,
        'volume': 65,
        'hapticEnabled': false,
        'hapticStrength': 60,
        'battery': {'available': false},
      });
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('90°'));
      await tester.pumpAndSettle();
      expect(find.text('Change display orientation?'), findsOneWidget);
      expect(session.controls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('cancel-device-rotation')));
      await tester.pumpAndSettle();
      expect(session.controls, isEmpty);
      await tester.tap(find.text('90°'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-device-rotation')));
      await tester.pumpAndSettle();
      expect(session.controls, [(DeviceControlField.rotation, 90)]);
      await tester.tap(find.text('180°'));
      await tester.pumpAndSettle();
      session.publish(LanConnectionPhase.offline);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-device-rotation')));
      await tester.pumpAndSettle();
      expect(session.controls, [(DeviceControlField.rotation, 90)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tabs show live information and preserve the connection', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Screen controls'), findsOneWidget);
    await select(tester, 'info');
    expect(find.text('1.1.2'), findsOneWidget);
    expect(find.text('00:11:22:33:44:55'), findsOneWidget);
    expect(find.text('64 s'), findsOneWidget);
    session.uptimeMs = 69000;
    session.publish(LanConnectionPhase.connected);
    await tester.pumpAndSettle();
    expect(find.text('69 s'), findsOneWidget);
    expect(
      tester
          .widget<DeviceDetailNavigation>(find.byType(DeviceDetailNavigation))
          .selected,
      DeviceDetailTab.info,
    );
    await select(tester, 'connection');
    expect(find.text('192.0.2.1'), findsOneWidget);
    expect(find.text('Connection help'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('device-help-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-device-help')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Refer to the instructions'), findsOneWidget);
    final panel = tester.getRect(
      find.byKey(const ValueKey('device-help-panel')),
    );
    expect(panel.width, 400);
    expect(panel.right, 784);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('device-help-panel')), findsNothing);
    await select(tester, 'control');
    await select(tester, 'connection');
    expect(find.text('Connection help'), findsNothing);
    expect(session.disconnects, 0);
    expect(session.connections, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation hint is only shown while awaiting approval', (
    tester,
  ) async {
    session.publish(LanConnectionPhase.connecting);
    await tester.pumpWidget(app(language: 'zh'));
    await tester.pumpAndSettle();
    expect(find.text('正在建立连接，请稍候。'), findsOneWidget);
    expect(find.text('请在设备上允许本次连接。'), findsNothing);
    await select(tester, 'connection');
    expect(find.text('正在建立连接，请稍候。'), findsOneWidget);
    session.publish(LanConnectionPhase.awaitingApproval);
    await tester.pumpAndSettle();
    expect(find.text('请在设备上允许本次连接。'), findsOneWidget);
    session.publish(LanConnectionPhase.connected);
    await tester.pumpAndSettle();
    expect(find.text('请在设备上允许本次连接。'), findsNothing);
    expect(find.text('已连接到设备，设备信息会自动刷新。'), findsOneWidget);
  });

  testWidgets('disconnect and reconnect operate on the selected device', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await select(tester, 'connection');
    await tester.ensureVisible(find.text('Disconnect'));
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(session.disconnects, 0);
    await tester.tap(find.byKey(const ValueKey('cancel-device-disconnect')));
    await tester.pumpAndSettle();
    expect(session.connected, isTrue);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-device-disconnect')));
    await tester.pumpAndSettle();
    expect(session.disconnects, 1);
    expect(find.text('192.0.2.1'), findsNothing);
    expect(find.text('Search again'), findsNothing);
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(session.connections, 1);
    expect(session.connected, isTrue);
    await select(tester, 'info');
    session.publish(LanConnectionPhase.offline);
    await tester.pumpAndSettle();
    expect(find.text('1.1.2'), findsNothing);
    expect(find.text('64 s'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disconnect confirmation does not disconnect a different device',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await select(tester, 'connection');
      await tester.ensureVisible(find.text('Disconnect'));
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      session.device = const LanDevice(
        id: 'aabbccddeeff',
        name: 'Other P4',
        address: '192.0.2.2',
        port: 18464,
        model: 'T-Display-P4',
      );
      session.publish(LanConnectionPhase.connected);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-device-disconnect')));
      await tester.pumpAndSettle();
      expect(session.disconnects, 0);
      expect(session.connected, isTrue);
    },
  );

  testWidgets(
    'bottom navigation remains visible with long names and large text',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      session.device = const LanDevice(
        id: '001122334455',
        name: '桌面终端 · A device with a very long name for a narrow window',
        address: '192.0.2.1',
        port: 18464,
        model: 'T-Display-P4',
      );
      for (final type in ThemeType.values) {
        theme.setTheme(type);
        for (final language in ['zh', 'en']) {
          await tester.binding.setSurfaceSize(const Size(360, 640));
          await tester.pumpWidget(app(language: language, scale: 1.6));
          await tester.pumpAndSettle();
          for (final tab in ['control', 'connection', 'info']) {
            await select(tester, tab);
            final before = tester.getRect(find.byType(DeviceDetailNavigation));
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, -900),
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(find.byType(DeviceDetailNavigation)), before);
            expect(before.bottom, lessThanOrEqualTo(640));
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );
}
