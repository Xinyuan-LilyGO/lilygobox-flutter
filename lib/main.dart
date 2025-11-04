/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-10-17 22:29:20
 * @LastEditTime: 2025-11-04 16:09:16
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import 'theme.dart';
import 'window.dart';
import 'language.dart';
import 'package_info.dart';

void main() async {
  debugPaintSizeEnabled = false; // 部件边界调试

  // 确保 Flutter 绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();
  // 确保 windowManager 已初始化
  await windowManager.ensureInitialized();

  // 定义窗口选项
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1150, 800), // 初始窗口大小
    backgroundColor: Colors.transparent, // 设置背景透明
    skipTaskbar: false, // 不在任务栏中隐藏
    titleBarStyle: TitleBarStyle.hidden, // 关键：隐藏原生标题栏，以便使用自定义标题栏
    center: true, // 窗口居中显示
  );

  // 等待窗口准备好显示
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // 最小尺寸限制
    await windowManager.setMinimumSize(Size(500, 400));
    // 设置窗口无边框
    await windowManager.setAsFrameless();
    // 添加窗口阴影
    // await windowManager.setHasShadow(true);
    // 显示窗口
    await windowManager.show();
    // 窗口获得焦点
    await windowManager.focus();
  });

  // 启动Flutter应用
  runApp(
    // 使用 MultiProvider 包装应用
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => WindowProvider()), // 添加窗口状态管理
        ChangeNotifierProvider(create: (_) => LanguageProvider()), // 添加语言管理
        ChangeNotifierProvider(create: (_) => PackageInfoProvider()), // 添加包信息管理
      ],
      child: const MainApp(),
    ),
  );
}
