/*
 * @Description: 统一紫色与灰色文字操作按钮，沿用主页配色、悬停渐变及点击波纹。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 18:10:36
 * @LastEditTime: 2026-10-20 14:48:39
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../theme/definition.dart';
import '../theme/material_palette.dart';
import 'menu_item_surface.dart';

/// 各页面通过 primary 选择紫色或灰色，配色与交互统一由此处管理。
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.theme,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
    this.settingBackground = false,
    this.backgroundColor,
    this.hoverColor,
    this.surfaceColor,
    this.icon,
    this.iconSize = 20,
    this.iconSpacing = 8,
    double? fontSize,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
  }) : fontSize = fontSize ?? (primary || destructive ? 14 : 12),
       padding =
           padding ??
           (primary || destructive
               ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
               : const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
       borderRadius =
           borderRadius ??
           (primary || destructive
               ? const BorderRadius.all(Radius.circular(10))
               : const BorderRadius.all(Radius.circular(8)));

  /// 设置页普通操作统一沿用恢复默认设置按钮的配色和交互。
  factory AppActionButton.settings({
    Key? key,
    required AppTheme theme,
    required String label,
    required VoidCallback? onPressed,
  }) => AppActionButton(
    key: key,
    theme: theme,
    label: label,
    onPressed: onPressed,
  );

  final AppTheme theme;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// 危险操作使用红色底色，继续复用统一的悬停和点击动画。
  final bool destructive;

  /// 提示框次要操作沿用适合弹窗背景的原有底色。
  final bool settingBackground;

  final Color? backgroundColor;
  final Color? hoverColor;
  final Color? surfaceColor;
  final IconData? icon;
  final double iconSize;
  final double iconSpacing;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    // 灰色操作统一沿用恢复默认设置按钮，紫色保留主要操作配色。
    final filled = primary || destructive;
    final inDialog = context.findAncestorWidgetOfExactType<Dialog>() != null;
    final background =
        backgroundColor ??
        (destructive
            ? theme.materialColors.error
            : primary
            ? theme.basePrimary
            : settingBackground
            ? Color.alphaBlend(
                theme.secondary.withValues(alpha: .9),
                theme.primary,
              )
            : theme.adaptiveColor(
                dark: theme.secondaryTextBackgroundColor,
                light: theme.secondaryTextHoverColor,
              ));
    final foreground = destructive
        ? theme.materialColors.onError
        : primary
        ? theme.materialColors.onPrimary
        : theme.textColorSecondary;
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
        color: foreground,
      ),
    );

    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: MenuItemSurface(
        theme: theme,
        onPressed: onPressed,
        backgroundColor: background,
        surfaceColor: surfaceColor,
        hoverColor:
            hoverColor ??
            (inDialog
                ? Color.alphaBlend(
                    (filled ? foreground : theme.textColorPrimary).withValues(
                      alpha: filled ? .1 : .06,
                    ),
                    background,
                  )
                : !filled
                ? theme.secondaryTextHoverColorAlt
                : Color.alphaBlend(
                    foreground.withValues(alpha: 0.1),
                    background,
                  )),
        borderRadius: borderRadius,
        child: Padding(
          padding: padding,
          child: icon == null
              ? Center(widthFactor: 1, heightFactor: 1, child: text)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: iconSize, color: foreground),
                    if (label.isNotEmpty) ...[
                      SizedBox(width: iconSpacing),
                      Flexible(child: text),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
