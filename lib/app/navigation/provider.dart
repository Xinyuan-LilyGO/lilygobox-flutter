/*
 * @Description: 管理主窗口内的页面导航与弹层切换状态。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
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

  AppPage get currentPage => _currentPage;
  String? get settingsDeviceName => _settingsDeviceName;

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
}
