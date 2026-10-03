/*
 * @Description: 统一弹出菜单的无边框浮层背景和阴影，区分菜单与底层页面。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 16:15:15
 * @LastEditTime: 2026-10-02 22:01:29
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../theme/definition.dart';

/// 账号菜单与右键菜单共用的浮层卡片。
class PopupMenuSurface extends StatelessWidget {
  const PopupMenuSurface({
    super.key,
    required this.theme,
    required this.child,
    this.padding = const EdgeInsets.all(5),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.backgroundColor,
  });

  final AppTheme theme;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? backgroundColor;

  /// 菜单项使用相同的实色起点，让悬停颜色直接插值，避免透明叠加。
  static Color backgroundColorFor(AppTheme theme) => theme.adaptiveColor(
    dark: Color.lerp(theme.secondary, theme.tertiary, 0.55)!,
    light: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? backgroundColorFor(theme),
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.32 - 0.2 * theme.lightProgress,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}
