/*
 * @Description: 统一悬停提示的显示延迟，复用 Flutter 提示样式与无障碍行为。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 17:16:37
 * @LastEditTime: 2026-10-01 17:19:32
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

/// 共用悬停提示，文案由调用处提供本地化文本。
class AppTooltip extends StatelessWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
    this.verticalOffset,
  });

  static const Duration waitDuration = Duration(milliseconds: 500);

  final String message;
  final Widget child;
  final double? verticalOffset;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: waitDuration,
      verticalOffset: verticalOffset,
      child: child,
    );
  }
}
