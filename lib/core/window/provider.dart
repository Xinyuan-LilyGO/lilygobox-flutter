/*
 * @Description: 管理桌面窗口焦点、最大化状态及最小化和关闭操作。
 * @Author: LILYGO_L
 * @Date: 2025-11-05 14:38:38
 * @LastEditTime: 2026-05-15 10:45:07
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面窗口状态和窗口操作入口。
///
/// 这里只处理最大化、焦点、最小化、关闭等系统窗口行为；应用内页面切换放在 AppNavigationProvider。
class WindowProvider with ChangeNotifier, WindowListener {
  bool _isMaximized = false;
  bool _isFocused = true;

  bool get isMaximized => _isMaximized;
  bool get isFocused => _isFocused;

  WindowProvider() {
    windowManager.addListener(this);
    unawaited(_init());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _init() async {
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
}
