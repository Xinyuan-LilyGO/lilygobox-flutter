/*
 * @Description: 初始化桌面无边框窗口，配置尺寸、显示状态和焦点。
 */

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/window/desktop_window.dart';

Future<void> configureDesktopWindow() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.windows &&
          defaultTargetPlatform != TargetPlatform.linux &&
          defaultTargetPlatform != TargetPlatform.macOS)) {
    return;
  }
  final window = await initializeDesktopWindow();
  if (window == null) throw StateError('Desktop window is unavailable');
  window.setSize(const Size(1280, 850).toNative(), false);
  window.minimumSize = const Size(500, 400).toNative();
  window.backgroundColor = Colors.transparent.toNative();
  window.isVisibleInTaskbar = true;
  window.titleBarStyle = TitleBarStyle.hidden;
  // 窗口阴影由 AppWindowFrame 绘制，禁用原生阴影，避免新版窗口库重复叠加。
  window.hasShadow = false;
  window.setFrameless(true);
  window.center();
  window.show();
  window.focus();
}
