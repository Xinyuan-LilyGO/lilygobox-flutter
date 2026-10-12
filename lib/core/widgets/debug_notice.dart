/*
 * @Description: 统一底部调试提示入口，仅在 debug 模式显示。
 * @Author: LILYGO_L
 * @Date: 2026-10-12 00:00:00
 * @LastEditTime: 2026-10-12 00:00:00
 * @License: GPL 3.0
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 底部弹出提示只用于 debug 调试，release 和 profile 模式禁止显示。
void showDebugNotice(ScaffoldMessengerState messenger, String message) {
  if (!kDebugMode || !messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
