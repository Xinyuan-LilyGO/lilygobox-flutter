/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-05 14:44:59
 * @LastEditTime: 2025-11-20 10:04:54
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';

class HomePageProvider with ChangeNotifier {
  double _splitWidth = 300.0; // 默认宽度
  int _selectedIndex =
      0; // 0: home, 1-10: devices, -1: add button (never selected)

  double get splitWidth => _splitWidth;
  int get selectedIndex => _selectedIndex;

  // 更新分页宽度
  void updateSplitWidth(double newWidth) {
    _splitWidth = newWidth;
    notifyListeners();
  }

  // 重置为默认宽度
  void resetSplitWidth() {
    _splitWidth = 300.0;
    notifyListeners();
  }

  // 更新选中索引
  void updateSelectedIndex(int index) {
    _selectedIndex = index;
    notifyListeners();
  }

  // 重置选中索引到主页
  void resetToHome() {
    _selectedIndex = 0;
    notifyListeners();
  }
}
