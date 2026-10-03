/*
 * @Description: 绘制窗口圆角与阴影，将页面及弹层统一裁剪在窗口内部。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-03 23:41:53
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../core/theme/definition.dart';

class AppWindowFrame extends StatelessWidget {
  const AppWindowFrame({
    super.key,
    required this.theme,
    required this.isMaximized,
    required this.child,
  });

  final AppTheme theme;
  final bool isMaximized;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: isMaximized ? EdgeInsets.zero : const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.primary,
        borderRadius: isMaximized
            ? BorderRadius.zero
            : BorderRadius.circular(10),
        boxShadow: isMaximized ? [] : _buildBoxShadow(),
      ),
      child: ClipRRect(
        borderRadius: isMaximized
            ? BorderRadius.zero
            : BorderRadius.circular(10),
        child: child,
      ),
    );
  }

  List<BoxShadow> _buildBoxShadow() {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.3),
        blurRadius: 5,
        spreadRadius: -1,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.3),
        blurRadius: 4,
        spreadRadius: -2,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 3,
        spreadRadius: -3,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 2,
        spreadRadius: -4,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.1),
        blurRadius: 1,
        spreadRadius: -5,
      ),
    ];
  }
}
