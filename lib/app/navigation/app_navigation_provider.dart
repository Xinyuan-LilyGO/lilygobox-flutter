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

  AppPage get currentPage => _currentPage;

  /// 切换到指定页面；重复设置同一页面时不通知，减少无意义重建。
  void setPage(AppPage page) {
    if (_currentPage == page) {
      return;
    }

    _currentPage = page;
    notifyListeners();
  }

  void goHome() {
    setPage(AppPage.home);
  }
}
