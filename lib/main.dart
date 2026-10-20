/*
 * @Description: 应用启动入口，初始化 Flutter 绑定、桌面窗口和全局状态。
 * @Author: LILYGO_L
 * @Date: 2025-10-17 22:29:20
 * @LastEditTime: 2026-10-03 20:29:43
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app/bootstrap/startup.dart';
import 'app/bootstrap/window_bootstrap.dart';
import 'app/tray/menu_app.dart';
import 'core/storage/preferences.dart';

// 托盘只启动共用菜单，不重复初始化设备、账号、配置或主窗口。
@pragma('vm:entry-point')
void trayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrayMenuApp());
}

void main() async {
  debugPaintSizeEnabled = false; // 部件边界调试

  // 确保 Flutter 绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();
  await configureDesktopWindow();
  final preferences = await AppPreferences.load();

  // 启动Flutter应用
  runApp(AppStartup(preferences: preferences));
}
