/*
 * @Description: 按 runner 持有的原生句柄绑定桌面窗口，避免依赖活动窗口状态。
 */

import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// 当前 Dart isolate 仅保留一个窗口封装，重启后也遵循此规则。
class DesktopWindowBinding {
  DesktopWindowBinding({
    required this.readNativeHandle,
    required this.wrapNativeHandle,
  });

  final Future<int?> Function() readNativeHandle;
  final Window? Function(int) wrapNativeHandle;
  Window? _window;
  Future<Window>? _initializing;

  Window? get window => _window;

  Future<Window> initialize() {
    if (_window case final window?) return Future.value(window);
    return _initializing ??= _bind();
  }

  Future<Window> _bind() async {
    try {
      final handle = await readNativeHandle();
      if (handle == null || handle == 0) {
        throw StateError('The Windows runner did not provide a window handle');
      }
      final window = wrapNativeHandle(handle);
      if (window == null) {
        throw StateError('Unable to bind the Windows runner window');
      }
      return _window = window;
    } finally {
      _initializing = null;
    }
  }
}

const _layoutChannel = MethodChannel('lilygobox/window_layout');
final _windowsBinding = DesktopWindowBinding(
  readNativeHandle: () => _layoutChannel.invokeMethod<int>('getWindowHandle'),
  wrapNativeHandle: (handle) =>
      Window.createWithNativeWindow(Pointer<Void>.fromAddress(handle)),
);

Future<Window?> initializeDesktopWindow() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    return _windowsBinding.initialize();
  }
  return WindowManager.instance.getCurrent();
}

/// 所有控件都使用 runner 的窗口，即使焦点位于其他窗口。
Window? currentDesktopWindow() =>
    _windowsBinding.window ?? WindowManager.instance.getCurrent();
