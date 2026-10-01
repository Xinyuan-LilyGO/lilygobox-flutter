/*
 * @Description: 提供数值设置的增减按钮及数值显示。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../theme/definition.dart';
import '../menu_item_surface.dart';
import 'decoration.dart';

class SettingStepper extends StatelessWidget {
  const SettingStepper({
    super.key,
    required this.theme,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  final AppTheme theme;
  final int value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.0,
      decoration: settingsControlDecoration(theme),
      child: Row(
        children: [
          _SettingStepperButton(
            theme: theme,
            icon: Icons.remove_rounded,
            onPressed: onDecrement,
          ),
          Expanded(
            child: Center(
              child: Text(
                '$value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.textColorPrimary,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          _SettingStepperButton(
            theme: theme,
            icon: Icons.add_rounded,
            onPressed: onIncrement,
          ),
        ],
      ),
    );
  }
}

class _SettingStepperButton extends StatelessWidget {
  const _SettingStepperButton({
    required this.theme,
    required this.icon,
    required this.onPressed,
  });

  final AppTheme theme;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MenuItemSurface(
      theme: theme,
      onPressed: onPressed,
      backgroundColor: Colors.transparent,
      hoverColor: theme.secondaryTextHoverColor,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 32.0,
        height: 32.0,
        child: Icon(icon, color: theme.textColorPrimary, size: 16.0),
      ),
    );
  }
}
