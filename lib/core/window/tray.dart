/*
 * @Description: 通过 Windows 托盘通道同步菜单配色和语言，接收显示及退出操作。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 00:20:00
 * @LastEditTime: 2026-10-04 00:20:00
 * @License: GPL 3.0
 */

import 'package:flutter/services.dart';

class WindowTray {
  static const channel = MethodChannel('lilygobox/tray');

  WindowTray({
    required Future<void> Function() onShow,
    required Future<void> Function() onExit,
  }) {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'show':
          await onShow();
        case 'exit':
          await onExit();
      }
    });
  }

  Future<bool> configure(Map<String, Object> appearance) async =>
      await channel.invokeMethod<bool>('configure', appearance) ?? false;

  // 原生层再次检查图标是否有效，避免托盘不可用时把窗口隐藏后无法找回。
  Future<bool> hide() async =>
      await channel.invokeMethod<bool>('hide') ?? false;

  void dispose() => channel.setMethodCallHandler(null);
}
