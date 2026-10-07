/*
 * @Description: 管理主窗口内的页面导航与弹层切换状态。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-03 20:29:43
 * @License: GPL 3.0
 */

import 'package:flutter/foundation.dart';

/// 应用主窗口内的顶层页面。
///
/// 这里只描述“当前显示哪个页面/弹层”，不处理系统窗口最大化、最小化等桌面窗口状态。
enum AppPage { home, settings, addDevice, deviceSettings }

/// 管理主窗口内的页面切换状态。
///
/// 这个 Provider 与 WindowProvider 分离：页面导航属于应用 UI，窗口状态属于桌面壳层。
class AppNavigationProvider with ChangeNotifier {
  AppPage _currentPage = AppPage.home;
  String? _settingsDeviceName;
  AppPage _contentPage = AppPage.home;
  final List<(AppPage, String?)> _history = [];
  String? _addedDeviceId;
  String? get addedDeviceId => _addedDeviceId;

  AppPage get currentPage => _currentPage;
  String? get settingsDeviceName => _settingsDeviceName;
  AppPage get contentPage => _contentPage;

  /// 切换到指定页面；重复设置同一页面时不通知，减少无意义重建。
  void setPage(AppPage page, {String? deviceName}) {
    if (page == AppPage.deviceSettings &&
        (deviceName == null || deviceName.trim().isEmpty)) {
      throw ArgumentError.value(deviceName, 'deviceName', '设备设置需要指定设备');
    }
    final nextDeviceName = page == AppPage.deviceSettings ? deviceName : null;
    if (_currentPage == page && _settingsDeviceName == nextDeviceName) {
      return;
    }

    if (page == AppPage.home || page == AppPage.addDevice) {
      _addedDeviceId = null;
      _contentPage = page;
      _history.clear();
    } else if (_currentPage != page) {
      _history.add((_currentPage, _settingsDeviceName));
    }
    _currentPage = page;
    _settingsDeviceName = nextDeviceName;
    notifyListeners();
  }

  /// 打开指定设备的设置，允许在设置页面内切换目标设备。
  void openDeviceSettings(String deviceName) {
    setPage(AppPage.deviceSettings, deviceName: deviceName);
  }

  void goHome() {
    setPage(AppPage.home);
  }

  /// 保留本轮添加成功的设备标识，由完成页展示结果，用户决定何时返回。
  void reportDeviceAdded(String id) {
    if (_contentPage != AppPage.addDevice || _addedDeviceId == id) return;
    _addedDeviceId = id;
    notifyListeners();
  }

  /// 关闭覆盖页时返回进入前的页面，保留添加设备和设备详情状态。
  void closeSettings() {
    if (_currentPage != AppPage.settings &&
        _currentPage != AppPage.deviceSettings) {
      return;
    }
    final previous = _history.isEmpty
        ? (_contentPage, null)
        : _history.removeLast();
    _currentPage = previous.$1;
    _settingsDeviceName = previous.$2;
    notifyListeners();
  }
}
