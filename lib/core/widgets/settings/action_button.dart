/*
 * @Description: 提供沿用设置控件配色和交互动画的文字操作按钮。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-03 18:10:36
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../theme/definition.dart';
import '../action_button.dart';

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
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    width: double.infinity,
    child: AppActionButton(
      theme: theme,
      label: label,
      onPressed: onPressed,
      fontSize: 13,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
