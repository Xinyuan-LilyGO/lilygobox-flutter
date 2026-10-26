/*
 * @Description: 管理主侧栏的显示状态、宽度及导航选中项。
 * @Author: LILYGO_L
 * @Date: 2025-11-05 14:44:59
 * @LastEditTime: 2026-10-03 20:29:43
 * @License: GPL 3.0
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

  double _sidebarWidth = defaultSidebarWidth;
  bool _isSidebarVisible = true;

  double get sidebarWidth => _sidebarWidth;
  bool get isSidebarVisible => _isSidebarVisible;

  void toggleSidebar() {
    _isSidebarVisible = !_isSidebarVisible;
    _saveLayout();
    notifyListeners();
  }

  /// 通过拖动只调整侧栏宽度，折叠状态由标题栏的显式按钮控制。
  void resizeSidebar(double width, {required double maxWidth}) {
    final upperBound = maxWidth.clamp(minSidebarWidth, maxSidebarWidth);
    final nextWidth = width.clamp(minSidebarWidth, upperBound).toDouble();
    if (_isSidebarVisible && nextWidth == _sidebarWidth) return;
    _sidebarWidth = nextWidth;
    _isSidebarVisible = true;
    _saveLayout();
    notifyListeners();
  }

  // 主页使用索引零，后续索引对应已添加设备列表。
  int _selectedIndex = 0;

  int get selectedIndex => _selectedIndex;

  /// 更新当前选中的导航项。
  void updateSelectedIndex(int index) {
    _selectedIndex = index;
    notifyListeners();
  }

  /// 外部流程需要回到主页时使用，例如设备删除或窗口导航重置。
  void resetToHome() {
    _selectedIndex = 0;
    notifyListeners();
  }
}
