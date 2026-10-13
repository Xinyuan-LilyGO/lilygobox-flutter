/*
 * @Description: 验证设备详情导航、旋转确认、真实会话操作及窄窗口和大字体布局。
 * @Author: LILYGO_L
 * @Date: 2026-10-07 18:00:00
 * @LastEditTime: 2026-10-13 12:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/devices/data/lan_discovery.dart';
import 'package:lilygobox/features/devices/domain/discovery_service.dart';
import 'package:lilygobox/features/devices/domain/device_control.dart';
import 'package:lilygobox/features/devices/presentation/pages/connected_page.dart';
import 'package:lilygobox/features/devices/presentation/widgets/device_detail_navigation.dart';
import 'package:lilygobox/features/devices/presentation/widgets/device_page_frame.dart';
import 'package:lilygobox/features/devices/state/lan_connection.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

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

  Widget app({String language = 'en', double scale = 1}) => MultiProvider(
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
          onBack: navigation.goHome,
          child: const ConnectedDevicePage(deviceId: '001122334455'),
        ),
      ),
    ),
  );

  Future<void> select(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey('device-tab-$tab')));
    await tester.pumpAndSettle();
  }

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
