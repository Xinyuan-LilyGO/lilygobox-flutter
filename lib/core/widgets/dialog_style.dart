/*
 * @Description: 统一标准提示框及嵌入式批准面板的文字、背景和普通按钮配色。
 * @Author: LILYGO_L
 * @Date: 2026-11-12 16:11:34
 * @LastEditTime: 2026-11-12 16:11:34
 */

import 'package:flutter/material.dart';

import '../theme/definition.dart';
import '../theme/material_palette.dart';

/// 弹窗和嵌入式提示共用的视觉规格，以编辑服务提示框为基准。
abstract final class AppDialogStyle {
  static const borderRadius = BorderRadius.all(Radius.circular(12));
  static const contentPadding = EdgeInsets.all(24);
  static const actionFontSize = 12.0;

  static Color backgroundColor(AppTheme theme) =>
      theme.materialColors.surfaceContainerHigh;

  static TextStyle titleStyle(AppTheme theme) => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.normal,
    color: theme.textColorPrimary,
  );

  static TextStyle fieldTitleStyle(AppTheme theme) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: theme.textColorSecondary,
  );

  static TextStyle descriptionStyle(AppTheme theme) =>
      TextStyle(fontSize: 11, height: 1.4, color: theme.textColorTertiary);

  /// 浅色表面沿用添加文件夹按钮的 6% 混色，深色保留现有层级。
  static Color neutralButtonColor(AppTheme theme, Color surface) =>
      theme.adaptiveColor(
        dark: theme.settingsControlBackgroundColor,
        light: Color.lerp(surface, theme.textColorPrimary, .06)!,
      );
}

/// 让嵌入式提示与真正的对话框共用普通按钮的背景和交互规则。
class AppDialogScope extends InheritedWidget {
  const AppDialogScope({
    super.key,
    required this.surfaceColor,
    required super.child,
  });

  final Color surfaceColor;

  static AppDialogScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDialogScope>();

  @override
  bool updateShouldNotify(AppDialogScope oldWidget) =>
      surfaceColor != oldWidget.surfaceColor;
}
