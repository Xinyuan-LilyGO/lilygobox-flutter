/*
 * @Description: 初始化桌面无边框窗口，配置尺寸、显示状态和焦点。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> configureDesktopWindow() async {
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1150, 800),
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
