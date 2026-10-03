/*
 * @Description: 管理已添加设备列表及设备的添加、删除和清空操作。
 * @Author: LILYGO_L
 * @Date: 2025-11-17 13:58:44
 * @LastEditTime: 2026-10-03 20:29:43
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../../core/storage/preferences.dart';

class DeviceManagerProvider extends ChangeNotifier {
  DeviceManagerProvider({AppPreferences? preferences})
    : _preferences = preferences,
      _addedDevices = preferences?.stringList('devices') ?? [];

  final AppPreferences? _preferences;
  final List<String> _addedDevices;

  List<String> get addedDevices => List.unmodifiable(_addedDevices);

  void addDevice(String deviceName) {
    if (deviceName.trim().isEmpty || _addedDevices.contains(deviceName)) return;
    _addedDevices.add(deviceName);
    _preferences?.setValue('devices', _addedDevices);
    notifyListeners();
  }

  void removeDevice(String deviceName) {
    _addedDevices.remove(deviceName);
    _preferences?.setValue('devices', _addedDevices);
    notifyListeners();
  }

  void clearDevices() {
    _addedDevices.clear();
    _preferences?.setValue('devices', _addedDevices);
    notifyListeners();
  }
}
