/*
 * @Description: 统一紫色与灰色文字操作按钮，沿用主页配色、悬停渐变及点击波纹。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 18:10:36
 * @LastEditTime: 2026-10-03 18:10:36
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
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  final AppTheme theme;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// 危险操作使用红色底色，继续复用统一的悬停和点击动画。
  final bool destructive;

  /// 在设置弹窗中沿用未选中设置项底色，保留灰色悬停对比。
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
    // 灰色沿用取消连接的默认底色，紫色沿用主页添加设备按钮。
    final filled = primary || destructive;
    // 提示框恢复柔和的悬停反馈，颜色按实际按钮底色混合。
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
            : Color.alphaBlend(
                theme.textColorPrimary.withValues(alpha: 0.06),
                theme.secondary,
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
                : filled
                ? Color.alphaBlend(
                    foreground.withValues(alpha: 0.1),
                    background,
                  )
                : theme.secondaryTextHoverColor),
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
