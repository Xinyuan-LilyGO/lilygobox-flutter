/*
 * @Description: 管理桌面窗口状态、托盘后台运行及保存配置后的完整退出。
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_window.dart';
import 'tray.dart';

/// 桌面窗口状态和窗口操作入口。
///
/// 这里只处理最大化、焦点、最小化、关闭等系统窗口行为；应用内页面切换放在 AppNavigationProvider。
class WindowProvider with ChangeNotifier {
  Window? _window;
  ListenerId? _listener;
  bool _isMaximized = false;
  bool _isFocused = true;

  bool get isMaximized => _isMaximized;
  bool get isFocused => _isFocused;

  WindowProvider({this.beforeClose, Window? window})
    : _useNativeMaximize =
          window == null &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.windows {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _tray = WindowTray(onShow: show, onExit: exit);
    }
    if (_desktop) {
      _window = window ?? currentDesktopWindow();
      _listener = _window?.addListener(_onWindowEvent);
      unawaited(_init());
    }
  }

  final Future<bool> Function()? beforeClose;
  final bool _useNativeMaximize;
  static const _layoutChannel = MethodChannel('lilygobox/window_layout');
  bool _closing = false;
  bool _nativeCloseAllowed = false;
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
    if (_listener case final listener?) _window?.removeListener(listener);
    super.dispose();
  }

  Future<void> _init() async {
    _isMaximized = _window?.isMaximized ?? false;
    _isFocused = _window?.isFocused ?? true;
    if (!_disposed) notifyListeners();
  }

  void _onWindowEvent(WindowEvent event) {
    switch (event) {
      case WindowMaximizedEvent():
        _isMaximized = true;
      case WindowRestoredEvent():
        _isMaximized = false;
      case WindowFocusedEvent():
        _isFocused = true;
      case WindowBlurredEvent():
        _isFocused = false;
      case WindowCloseRequestedEvent():
        if (!_nativeCloseAllowed) {
          event.request.cancel();
          if (!_closing) unawaited(close());
        }
      default:
        return;
    }
    if (!_disposed) notifyListeners();
  }

  // 处理窗口最大化/还原操作
  Future<void> handleMaximizeRestore() async {
    final window = _window;
    if (_disposed || window == null) return;
    if (_useNativeMaximize) {
      try {
        await _layoutChannel.invokeMethod<void>('toggleMaximize');
        return;
      } on MissingPluginException {
        // 其他宿主和测试运行器继续使用跨平台窗口 API。
      }
    }
    // 原生状态同步改变，而 nativeapi 会稍后发送事件。
    // 查询实际状态，避免连续点击重复执行同一操作。
    if (window.isMaximized) {
      window.unmaximize();
    } else {
      window.maximize();
    }
  }

  // 最小化窗口
  Future<void> minimize() async {
    _window?.minimize();
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
    if (_window?.isMinimized == true) _window?.restore();
    _window?.show();
    _window?.focus();
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
      _nativeCloseAllowed = true;
      if (_window?.close() == false) {
        throw StateError('Window close was cancelled');
      }
    } catch (_) {
      _nativeCloseAllowed = false;
      _closing = false;
      await show();
      rethrow;
    }
  }
}
