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
