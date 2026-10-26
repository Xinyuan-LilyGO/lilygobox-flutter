/*
 * @Description: 管理桌面窗口状态、托盘后台运行及保存配置后的完整退出。
 * @Author: LILYGO_L
 * @Date: 2025-11-05 14:38:38
 * @LastEditTime: 2026-10-04 00:20:00
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'tray.dart';

/// 桌面窗口状态和窗口操作入口。
///
/// 这里只处理最大化、焦点、最小化、关闭等系统窗口行为；应用内页面切换放在 AppNavigationProvider。
class WindowProvider with ChangeNotifier, WindowListener {
  bool _isMaximized = false;
  bool _isFocused = true;

  bool get isMaximized => _isMaximized;
  bool get isFocused => _isFocused;

  WindowProvider({this.beforeClose}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _tray = WindowTray(onShow: show, onExit: exit);
    }
    if (_desktop) {
      windowManager.addListener(this);
      unawaited(_init());
    }
  }

  final Future<bool> Function()? beforeClose;
  bool _closing = false;
  WindowTray? _tray;
  bool _hiding = false;
  bool _disposed = false;
  Map<String, Object>? _trayAppearance;

  Future<void> configureTray(Map<String, Object> appearance) async {
    if (_tray == null || mapEquals(_trayAppearance, appearance)) return;
    try {
      if (await _tray!.configure(appearance)) _trayAppearance = appearance;
    } catch (error) {
      debugPrint('Tray configuration failed: $error');
    }
  }

  bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void dispose() {
    _disposed = true;
    _tray?.dispose();
    if (_desktop) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _init() async {
    await windowManager.setPreventClose(true);
    _isMaximized = await windowManager.isMaximized();
    _isFocused = await windowManager.isFocused();
    // 启动窗口由原生首帧和启动页共同显示，初始化查询可能发生在窗口
    // 尚未完成激活时。主动聚焦并同步状态，避免启动后一直显示失焦样式。
    if (!_isFocused && !_disposed) {
      await windowManager.focus();
      _isFocused = true;
    }
    if (!_disposed) notifyListeners();
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

  // Windows 关闭只隐藏窗口，保留页面、设备任务和登录状态。
  Future<void> close({bool discardUnsaved = false}) async {
    if (discardUnsaved || _tray == null) {
      await exit(discardUnsaved: discardUnsaved);
      return;
    }
    if (_closing || _hiding) return;
    _hiding = true;
    try {
      if (!await _tray!.hide()) await minimize();
    } catch (error) {
      debugPrint('Tray unavailable, minimizing instead: $error');
      await minimize();
    } finally {
      _hiding = false;
    }
  }

  Future<void> show() async {
    if (_closing || _disposed) return;
    await windowManager.show();
    await windowManager.focus();
  }

  // 仅显式退出才等待配置保存，并进入原有系统关闭流程。
  Future<void> exit({bool discardUnsaved = false}) async {
    if (_closing) return;
    _closing = true;
    try {
      if (!discardUnsaved && beforeClose != null && !await beforeClose!()) {
        _closing = false;
        await show();
        return;
      }
      // 保存完成后走系统正常关闭流程，避免直接退出消息循环时窗口
      // 仍停留在屏幕上等待引擎释放；保持关闭标记以忽略二次关闭事件。
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (_) {
      await windowManager.setPreventClose(true);
      _closing = false;
      await show();
      rethrow;
    }
  }

  @override
  void onWindowClose() => unawaited(close());
}
