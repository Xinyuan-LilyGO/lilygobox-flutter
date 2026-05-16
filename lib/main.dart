/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-10-17 22:29:20
 * @LastEditTime: 2025-11-20 10:03:58
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app/app_providers.dart';
import 'app/bootstrap/window_bootstrap.dart';
import 'app/lilygo_box_app.dart';

void main() async {
  debugPaintSizeEnabled = false; // 部件边界调试

  // 确保 Flutter 绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();
  await configureDesktopWindow();

  // 启动Flutter应用
  runApp(const AppProviders(child: LilygoBoxApp()));
}
