/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-05 14:44:59
 * @LastEditTime: 2025-11-17 11:27:17
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';

class HomePageProvider with ChangeNotifier {
  double _splitWidth = 300.0; // 默认宽度

  double get splitWidth => _splitWidth;

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
}
