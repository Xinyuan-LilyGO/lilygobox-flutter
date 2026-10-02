/*
 * @Description: 验证发现去重、超时、取消及过期异步结果不会误报连接成功。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 13:35:30
 * @LastEditTime: 2026-10-02 13:35:30
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/devices/domain/discovery_service.dart';
import 'package:lilygobox/features/devices/state/discovery_controller.dart';

const device = DiscoveredDevice(id: 'p4-1', name: 'T-Display-P4');

class TestDiscoveryService extends DeviceDiscoveryService {
  final scans = <StreamController<DiscoveredDevice>>[];
  final connections = <Completer<bool>>[];
  int cancelledScans = 0;
  int cancelledConnections = 0;

  @override
  Stream<DiscoveredDevice> discover() {
    final scan = StreamController<DiscoveredDevice>(
      onCancel: () async {
        cancelledScans++;
      },
    );
    scans.add(scan);
    return scan.stream;
  }

  @override
  Future<bool> connect(DiscoveredDevice device) {
    final result = Completer<bool>();
    connections.add(result);
    return result.future;
  }

  @override
  Future<void> cancelConnection() async => cancelledConnections++;
}

void main() {
  testWidgets(
    'unconfigured discovery reports unavailable without fake devices',
    (tester) async {
      final controller = DiscoveryController(
        service: const UnavailableDeviceDiscoveryService(),
      );
      unawaited(controller.search());
      await tester.pump();
      expect(controller.phase, DiscoveryPhase.unavailable);
      expect(controller.devices, isEmpty);
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'deduplicates stable IDs and cancels the previous scan on retry',
    (tester) async {
      final service = TestDiscoveryService();
      final controller = DiscoveryController(service: service);
      unawaited(controller.search());
      await tester.pump();
      service.scans.last.add(device);
      service.scans.last.add(
        const DiscoveredDevice(id: 'p4-1', name: 'Updated P4'),
      );
      await tester.pump();
      expect(controller.devices.single.name, 'Updated P4');
      unawaited(controller.search());
      await tester.pump();
      expect(service.cancelledScans, 1);
      service.scans.first.add(device);
      await tester.pump();
      expect(controller.devices, isEmpty);
      unawaited(service.scans.last.close());
      await tester.pump();
      expect(controller.phase, DiscoveryPhase.empty);
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets('requires confirmed connection and blocks repeated requests', (
    tester,
  ) async {
    final service = TestDiscoveryService();
    final controller = DiscoveryController(service: service);
    unawaited(controller.search());
    await tester.pump();
    service.scans.last.add(device);
    await tester.pump();
    unawaited(controller.connect(device));
    unawaited(controller.connect(device));
    await tester.pump();
    expect(service.connections, hasLength(1));
    expect(controller.phase, DiscoveryPhase.connecting);
    service.connections.last.complete(false);
    await tester.pump();
    expect(controller.phase, DiscoveryPhase.connectionFailed);
    unawaited(controller.connect(device));
    await tester.pump();
    service.connections.last.complete(true);
    await tester.pump();
    expect(controller.phase, DiscoveryPhase.connected);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('late success after cancellation or disposal is ignored', (
    tester,
  ) async {
    final service = TestDiscoveryService();
    final controller = DiscoveryController(service: service);
    unawaited(controller.search());
    await tester.pump();
    service.scans.last.add(device);
    await tester.pump();
    unawaited(controller.connect(device));
    await tester.pump();
    unawaited(controller.cancelConnection());
    await tester.pump();
    service.connections.first.complete(true);
    await tester.pump();
    expect(controller.phase, DiscoveryPhase.searching);
    expect(controller.selectedDevice, isNull);
    expect(service.cancelledConnections, 1);
    service.scans.last.add(device);
    await tester.pump();
    unawaited(controller.connect(device));
    await tester.pump();
    controller.dispose();
    await tester.pump();
    service.connections.last.complete(true);
    await tester.pump();
    expect(service.cancelledConnections, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scan and connection timeouts release pending work', (
    tester,
  ) async {
    final service = TestDiscoveryService();
    final controller = DiscoveryController(
      service: service,
      searchTimeout: const Duration(seconds: 1),
      connectionTimeout: const Duration(seconds: 1),
    );
    unawaited(controller.search());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.phase, DiscoveryPhase.empty);
    expect(service.cancelledScans, 1);
    unawaited(controller.search());
    await tester.pump();
    service.scans.last.add(device);
    await tester.pump();
    unawaited(controller.connect(device));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.phase, DiscoveryPhase.connectionFailed);
    expect(service.cancelledConnections, 1);
    service.connections.last.complete(true);
    await tester.pump();
    expect(controller.phase, DiscoveryPhase.connectionFailed);
    controller.dispose();
    await tester.pump();
  });
}
