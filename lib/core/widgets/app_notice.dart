/*
 * @Description: 统一应用底部操作提示入口。
 * @Author: LILYGO_L
 * @Date: 2026-10-12 00:00:00
 * @LastEditTime: 2026-11-09 09:45:46
 */

import 'package:flutter/material.dart';

/// 显示操作结果提示，适用于所有构建模式。
void showAppNotice(ScaffoldMessengerState messenger, String message) {
  if (!messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
