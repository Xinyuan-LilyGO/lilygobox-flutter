/*
 * @Description: 验证设备身份变化后的重新配对使用公共确认弹窗，取消时保留授权。
 * @Author: LILYGO_L
 * @Date: 2026-10-06 16:00:00
 * @LastEditTime: 2026-10-06 16:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/devices/data/lan_discovery.dart';
import 'package:lilygobox/features/devices/domain/discovery_service.dart';
import 'package:lilygobox/features/devices/presentation/pages/connected_page.dart';
import 'package:lilygobox/features/devices/state/lan_connection.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class _Connection extends LanConnection {
  int resets = 0;
  int connections = 0;
  @override
  Future<bool> resetDeviceTrust(String id) async {
    resets++;
    identityChanged = false;
    return true;
  }

  @override
  Future<bool> connect(DiscoveredDevice target) async {
    connections++;
    return false;
  }
}

void main() {
  testWidgets(
    'certificate change needs confirmation before resetting and reconnecting',
    (tester) async {
      const device = LanDevice(
        id: '001122334455',
        name: 'Desk P4',
        address: '192.0.2.1',
        port: 18464,
        model: 'T-Display-P4',
      );
      final theme = ThemeProvider();
      final devices = DeviceManagerProvider()..addLanDevice(device);
      final connection = _Connection()
        ..device = device
        ..phase = LanConnectionPhase.failed
        ..identityChanged = true;
      addTearDown(theme.dispose);
      addTearDown(devices.dispose);
      addTearDown(connection.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: devices),
            ChangeNotifierProvider<LanConnection>.value(value: connection),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ConnectedDevicePage(deviceId: '001122334455')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('设备身份已变化'), findsOneWidget);
      await tester.tap(find.text('重新配对'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancel-device-repair')));
      await tester.pumpAndSettle();
      expect(connection.resets, 0);
      expect(connection.connections, 0);
      await tester.tap(find.text('重新配对'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-device-repair')));
      await tester.pumpAndSettle();
      expect(connection.resets, 1);
      expect(connection.connections, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
