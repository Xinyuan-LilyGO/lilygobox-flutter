/*
 * @Description: 同步应用级设备连接，保存设备资料并记录本轮添加结果。
 * @Author: LILYGO_L
 * @Date: 2026-10-07 00:00:00
 * @LastEditTime: 2026-10-07 00:00:00
 * @License: GPL 3.0
 */

import '../features/devices/state/lan_connection.dart';
import '../features/devices/state/manager_provider.dart';
import 'navigation/provider.dart';

class DeviceConnectionCoordinator {
  DeviceConnectionCoordinator({
    required this.connection,
    required this.devices,
    required this.navigation,
  }) {
    _connectedDeviceId = connection.connected ? connection.device?.id : null;
    connection.addListener(_connectionChanged);
  }

  final LanConnection connection;
  final DeviceManagerProvider devices;
  final AppNavigationProvider navigation;
  String? _connectedDeviceId;

  // 记录本轮成功结果，页面尚未构建时也不会漏掉；旧连接心跳不算新添加。
  void _connectionChanged() {
    final device = connection.connected ? connection.device : null;
    final newlyConnected = device != null && device.id != _connectedDeviceId;
    _connectedDeviceId = device?.id;
    if (device == null) return;
    devices.addLanDevice(device);
    if (newlyConnected && navigation.contentPage == AppPage.addDevice) {
      navigation.reportDeviceAdded(device.id);
    }
  }

  void dispose() {
    connection.removeListener(_connectionChanged);
  }
}
