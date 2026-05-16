/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-17 13:58:44
 * @LastEditTime: 2025-11-20 10:01:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

class DeviceManagerProvider extends ChangeNotifier {
  final List<String> _addedDevices = [];
  
  List<String> get addedDevices => List.unmodifiable(_addedDevices);
  
  void addDevice(String deviceName) {
    _addedDevices.add(deviceName);
    notifyListeners();
  }
  
  void removeDevice(String deviceName) {
    _addedDevices.remove(deviceName);
    notifyListeners();
  }
  
  void clearDevices() {
    _addedDevices.clear();
    notifyListeners();
  }
}
