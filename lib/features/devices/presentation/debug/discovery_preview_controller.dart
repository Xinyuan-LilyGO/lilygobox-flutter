/*
 * @Description: 仅在调试模式模拟添加设备状态，不调用硬件服务或写入设备列表。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 14:19:09
 * @LastEditTime: 2026-10-02 14:19:09
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/discovery_service.dart';
import '../../state/discovery_controller.dart';

class DiscoveryPreviewController extends DiscoveryController {
  DiscoveryPreviewController()
    : super(service: const UnavailableDeviceDiscoveryService()) {
    if (!kDebugMode) throw StateError('Device preview requires debug mode.');
  }

  static const previewDevice = DiscoveredDevice(
    id: 'debug-preview-p4',
    name: 'T-Display-P4',
  );

  Timer? _transition;

  @override
  List<DiscoveredDevice> get devices =>
      phase == DiscoveryPhase.found ? const [previewDevice] : const [];

  // 菜单直接选中的状态保持不变，方便观察排版、主题与悬停动画。
  void showPhase(DiscoveryPhase next) {
    _transition?.cancel();
    _transition = null;
    phase = next;
    selectedDevice = switch (next) {
      DiscoveryPhase.connecting ||
      DiscoveryPhase.connected ||
      DiscoveryPhase.connectionFailed => previewDevice,
      _ => null,
    };
    notifyListeners();
  }

  @override
  Future<void> search() async {
    showPhase(DiscoveryPhase.searching);
    _transition = Timer(const Duration(milliseconds: 1200), () {
      showPhase(DiscoveryPhase.found);
    });
  }

  @override
  Future<void> connect(DiscoveredDevice device) async {
    if (device.id != previewDevice.id || phase == DiscoveryPhase.connecting) {
      return;
    }
    showPhase(DiscoveryPhase.connecting);
    _transition = Timer(const Duration(milliseconds: 1600), () {
      showPhase(DiscoveryPhase.connected);
    });
  }

  @override
  Future<void> cancelConnection() async => showPhase(DiscoveryPhase.found);

  @override
  void dispose() {
    _transition?.cancel();
    super.dispose();
  }
}
