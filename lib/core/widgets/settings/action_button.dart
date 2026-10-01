/*
 * @Description: 提供沿用设置控件配色和交互动画的文字操作按钮。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../theme/definition.dart';
import '../menu_item_surface.dart';

class SettingActionButton extends StatelessWidget {
  const SettingActionButton({
    super.key,
    required this.theme,
    required this.label,
    required this.onPressed,
  });

  final AppTheme theme;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MenuItemSurface.control(
      theme: theme,
      onPressed: onPressed,
      child: Container(
        height: 32.0,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.textColorPrimary,
            fontSize: 13.0,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
