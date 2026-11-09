/*
 * @Description: 管理主侧栏的显示状态、宽度及导航选中项。
 * @Author: LILYGO_L
 * @Date: 2025-11-05 14:44:59
 * @LastEditTime: 2026-11-09 09:45:46
 */

import 'package:flutter/material.dart';

import '../../../core/storage/preferences.dart';

/// 管理 App Shell 左侧主导航的选中项。
///
/// 顶层页面由 AppNavigationProvider 管理；这里保存导航选择和主侧栏布局。
class AppShellProvider with ChangeNotifier {
  AppShellProvider({AppPreferences? preferences}) : _preferences = preferences {
    _sidebarWidth =
        preferences?.doubleValue(
          'sidebarWidth',
          defaultSidebarWidth,
          minSidebarWidth,
          maxSidebarWidth,
        ) ??
        defaultSidebarWidth;
    _isSidebarVisible = preferences?.boolValue('sidebarVisible', true) ?? true;
  }

  final AppPreferences? _preferences;
  void _saveLayout() {
    _preferences?.setValue('sidebarWidth', _sidebarWidth);
    _preferences?.setValue('sidebarVisible', _isSidebarVisible);
  }

  void resetLayout() {
    _sidebarWidth = defaultSidebarWidth;
    _isSidebarVisible = true;
    _saveLayout();
    notifyListeners();
  }

  static const double defaultSidebarWidth = minSidebarWidth;
  static const double minSidebarWidth = 180;
  static const double maxSidebarWidth = 360;
  static const double sidebarCollapseThreshold = 120;

  double _sidebarWidth = defaultSidebarWidth;
  bool _isSidebarVisible = true;

  double get sidebarWidth => _sidebarWidth;
  bool get isSidebarVisible => _isSidebarVisible;

  void toggleSidebar() {
    _isSidebarVisible = !_isSidebarVisible;
    _saveLayout();
    notifyListeners();
  }

  /// 拖动值可以小于最小展开宽度，用于判断是否已拖到折叠阈值。
  void resizeSidebar(double width, {required double maxWidth}) {
    if (width < sidebarCollapseThreshold) {
      if (_isSidebarVisible) {
        _isSidebarVisible = false;
        _saveLayout();
        notifyListeners();
      }
      return;
    }

    final upperBound = maxWidth.clamp(minSidebarWidth, maxSidebarWidth);
    final nextWidth = width.clamp(minSidebarWidth, upperBound).toDouble();
    if (_isSidebarVisible && nextWidth == _sidebarWidth) return;
    _sidebarWidth = nextWidth;
    _isSidebarVisible = true;
    _saveLayout();
    notifyListeners();
  }

  // 首页使用索引零，后续索引对应已打开的设备详情。
  int _selectedIndex = 0;
  bool _deviceManagementSelected = false;

  int get selectedIndex => _selectedIndex;
  bool get deviceManagementSelected => _deviceManagementSelected;

  /// 更新当前选中的导航项。
  void updateSelectedIndex(int index) {
    _selectedIndex = index;
    _deviceManagementSelected = false;
    notifyListeners();
  }

  void openDeviceManagement() {
    if (_deviceManagementSelected && _selectedIndex == 0) return;
    _selectedIndex = 0;
    _deviceManagementSelected = true;
    notifyListeners();
  }

  void openAssistant() {
    if (!_deviceManagementSelected && _selectedIndex == 0) return;
    _selectedIndex = 0;
    _deviceManagementSelected = false;
    notifyListeners();
  }

  /// 外部流程需要回到主页时使用，例如设备删除或窗口导航重置。
  void resetToHome() {
    _selectedIndex = 0;
    _deviceManagementSelected = false;
    notifyListeners();
  }
}
