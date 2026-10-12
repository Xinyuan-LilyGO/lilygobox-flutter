/*
 * @Description: 初始化桌面无边框窗口，配置尺寸、显示状态和焦点。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-12 00:00:00
 * @License: GPL 3.0
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> configureDesktopWindow() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.windows &&
          defaultTargetPlatform != TargetPlatform.linux &&
          defaultTargetPlatform != TargetPlatform.macOS)) {
    return;
  }
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 850),
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    center: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setMinimumSize(const Size(500, 400));
    await windowManager.setAsFrameless();
    await windowManager.show();
    await windowManager.focus();
  });
}
