/*
 * @Description: 统一下拉菜单和步进控件的背景、圆角与边框装饰。
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
