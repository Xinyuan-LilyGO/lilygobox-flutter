import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

enum WindowPage { home, settings, addBoard }

class WindowProvider with ChangeNotifier, WindowListener {
  bool _isMaximized = false;
  bool _isFocused = true;

  bool get isMaximized => _isMaximized;
  bool get isFocused => _isFocused;

  // !!! 修改: 默认页面为 home
  WindowPage _currentPage = WindowPage.home;
  WindowPage get currentPage => _currentPage;

  WindowProvider() {
    windowManager.addListener(this);
    _init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _init() async {
    _isMaximized = await windowManager.isMaximized();
    _isFocused = await windowManager.isFocused();
    notifyListeners();
  }

  // 监听窗口最大化事件
  @override
  void onWindowMaximize() {
    _isMaximized = true;
    notifyListeners();
  }

  // 监听窗口取消最大化事件
  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
    notifyListeners();
  }

  // 监听窗口获得焦点事件
  @override
  void onWindowFocus() {
    _isFocused = true;
    notifyListeners();
  }

  // 监听窗口失去焦点事件
  @override
  void onWindowBlur() {
    _isFocused = false;
    notifyListeners();
  }

  // 处理窗口最大化/还原操作
  Future<void> handleMaximizeRestore() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  // 最小化窗口
  Future<void> minimize() async {
    await windowManager.minimize();
  }

  // 关闭窗口
  Future<void> close() async {
    await windowManager.close();
  }

  // !!! 修改: setPage 用于切换页面
  void setPage(WindowPage page) {
    _currentPage = page;
    notifyListeners();
  }
}
