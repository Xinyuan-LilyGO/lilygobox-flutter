/*
 * @Description: 保存并共享首页与设备页的左右分栏宽度。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/foundation.dart';

/// 保存全局分栏宽度。
///
/// 主页和设备页共享同一个宽度状态，用户拖动任一分栏后，其他同类页面会保持一致体验。
class SplitViewProvider with ChangeNotifier {
  static const double defaultSplitWidth = 300.0;

  double _splitWidth = defaultSplitWidth;

  double get splitWidth => _splitWidth;

  /// 更新左侧分栏宽度；宽度不变时跳过通知，避免不必要的重建。
  void updateSplitWidth(double newWidth) {
    if (_splitWidth == newWidth) {
      return;
    }

    _splitWidth = newWidth;
    notifyListeners();
  }

  void resetSplitWidth() {
    updateSplitWidth(defaultSplitWidth);
  }
}
