/*
 * @Description: 统一下拉菜单和步进控件的背景、圆角与边框装饰。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../theme/definition.dart';

BoxDecoration settingsControlDecoration(
  AppTheme theme, {
  Color? color,
  bool opaque = false,
}) {
  return BoxDecoration(
    color:
        color ??
        (opaque ? theme.primary : theme.primary.withValues(alpha: 0.74)),
    borderRadius: BorderRadius.circular(4.0),
    border: Border.all(color: theme.dividerColor),
  );
}
