/*
 * @Description: 窗口控制按钮复用公共交互表面，统一悬停渐变、按下高亮和点击波纹。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-02 21:44:28
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../core/theme/definition.dart';
import '../../core/widgets/menu_item_surface.dart';

class AppTitleBarControlsButtonTemplate extends StatelessWidget {
  const AppTitleBarControlsButtonTemplate({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.theme,
    this.hoverColor,
    this.hoverIconColor,
    required this.iconColor,

    this.iconSize = 20,
    this.iconWeight = 300.0,
    this.rotateAngle = 0.0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final AppTheme theme;
  final Color? hoverColor;
  final Color? hoverIconColor;
  final Color iconColor;
  final double iconSize;
  final double iconWeight;
  final double rotateAngle;

  @override
  Widget build(BuildContext context) {
    return MenuItemSurface(
      theme: theme,
      onPressed: onPressed,
      hoverColor: hoverColor ?? theme.primaryTextHoverColor,
      foregroundColor: iconColor,
      hoverForegroundColor: hoverIconColor,
      borderRadius: BorderRadius.zero,
      child: SizedBox(
        width: 45,
        height: 30,
        child: Center(
          child: Transform.rotate(
            angle: rotateAngle * (3.1415926535 / 180),
            child: Icon(
              icon,
              size: iconSize,
              weight: iconWeight,
              grade: -25.0,
              opticalSize: 48.0,
            ),
          ),
        ),
      ),
    );
  }
}
