/*
 * @Description: 管理桌面窗口焦点、最大化状态及最小化和关闭操作。
 * @Author: LILYGO_L
 * @Date: 2025-11-05 14:38:38
 * @LastEditTime: 2026-10-03 21:12:12
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面窗口状态和窗口操作入口。
///
/// 这里只处理最大化、焦点、最小化、关闭等系统窗口行为；应用内页面切换放在 AppNavigationProvider。
class WindowProvider with ChangeNotifier, WindowListener {
  bool _isMaximized = false;
  bool _isFocused = true;

  bool get isMaximized => _isMaximized;
  bool get isFocused => _isFocused;

  WindowProvider({this.beforeClose}) {
    if (_desktop) {
      windowManager.addListener(this);
      unawaited(_init());
    }
  }

  final Future<bool> Function()? beforeClose;
  bool _closing = false;
  bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void dispose() {
    if (_desktop) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _init() async {
    await windowManager.setPreventClose(true);
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
  Future<void> close({bool discardUnsaved = false}) async {
    if (_closing) return;
    _closing = true;
    try {
      if (!discardUnsaved && beforeClose != null && !await beforeClose!()) {
        _closing = false;
        return;
      }
      // 保存完成后走系统正常关闭流程，避免直接退出消息循环时窗口
      // 仍停留在屏幕上等待引擎释放；保持关闭标记以忽略二次关闭事件。
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (_) {
      await windowManager.setPreventClose(true);
      _closing = false;
      rethrow;
    }
  }

  @override
  void onWindowClose() => unawaited(close());
}
