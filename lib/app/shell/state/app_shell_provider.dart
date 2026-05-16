/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-05 14:44:59
 * @LastEditTime: 2025-11-20 10:04:54
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

/// 管理 App Shell 左侧主导航的选中项。
///
/// 顶层页面由 AppNavigationProvider 管理；这里仅保存主页和已添加设备之间的选择状态。
class AppShellProvider with ChangeNotifier {
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
