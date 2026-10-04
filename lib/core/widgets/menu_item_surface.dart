/*
 * @Description: 统一菜单和设置控件的选中配色、悬停渐变与点击波纹。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-04 13:01:33
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../theme/definition.dart';
import 'interaction_decoration.dart';

/// 设置菜单与侧栏入口共用的交互表面。
///
/// 选中颜色优先于悬停颜色；默认禁止重复选中，下拉项可允许点击收起。
class MenuItemSurface extends StatefulWidget {
  const MenuItemSurface({
    super.key,
    required this.theme,
    required this.onPressed,
    required this.child,
    this.isSelected = false,
    this.disableWhenSelected = true,
    this.backgroundColor,
    this.hoverColor,
    this.foregroundColor,
    this.hoverForegroundColor,
    this.border,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  /// 设置输入控件的配色与边框；交互和颜色过渡仍由同一组件处理。
  factory MenuItemSurface.control({
    Key? key,
    required AppTheme theme,
    required VoidCallback? onPressed,
    required Widget child,
  }) => MenuItemSurface(
    key: key,
    theme: theme,
    onPressed: onPressed,
    backgroundColor: theme.primary.withValues(alpha: 0.74),
    hoverColor: theme.secondaryTextHoverColor,
    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.28)),
    borderRadius: BorderRadius.circular(4),
    child: child,
  );

  static const animationDuration = InteractionDecoration.animationDuration;
  static const animationCurve = InteractionDecoration.animationCurve;

  final AppTheme theme;
  final VoidCallback? onPressed;
  final Widget child;
  final bool isSelected;
  final bool disableWhenSelected;
  final Color? backgroundColor;
  final Color? hoverColor;
  final Color? foregroundColor;
  final Color? hoverForegroundColor;
  final BoxBorder? border;
  final BorderRadius borderRadius;

  @override
  State<MenuItemSurface> createState() => _MenuItemSurfaceState();
}

class _MenuItemSurfaceState extends State<MenuItemSurface> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled =
        widget.onPressed != null &&
        !(widget.isSelected && widget.disableWhenSelected);
    final backgroundColor = widget.isSelected
        ? theme.primaryTextSelectedColor
        : _isHovered && enabled
        ? widget.hoverColor ?? theme.primaryTextHoverColor
        : widget.backgroundColor ?? theme.primary;
    final foregroundColor = _isHovered && enabled && !widget.isSelected
        ? widget.hoverForegroundColor ?? widget.foregroundColor
        : widget.foregroundColor;

    return Semantics(
      selected: widget.isSelected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InteractionDecoration(
          palette: theme,
          duration: MenuItemSurface.animationDuration,
          curve: MenuItemSurface.animationCurve,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: widget.borderRadius,
          ),
          // 边框只绘制，不额外增加控件尺寸或改变下拉菜单的定位。
          child: Container(
            foregroundDecoration: widget.border == null
                ? null
                : BoxDecoration(
                    border: widget.border,
                    borderRadius: widget.borderRadius,
                  ),
            // 墨水层放在渐变背景上方，避免点击波纹被遮挡。
            child: Material(
              type: MaterialType.transparency,
              borderRadius: widget.borderRadius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? widget.onPressed : null,
                mouseCursor: enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                borderRadius: widget.borderRadius,
                hoverColor: Colors.transparent,
                highlightColor: theme.textColorPrimary.withValues(alpha: 0.04),
                splashColor: theme.textColorPrimary.withValues(alpha: 0.12),
                splashFactory: InkRipple.splashFactory,
                child: foregroundColor == null
                    ? widget.child
                    : InteractionDecoration.color(
                        palette: theme,
                        color: foregroundColor,
                        builder: (context, color) => IconTheme.merge(
                          data: IconThemeData(color: color),
                          child: DefaultTextStyle.merge(
                            style: TextStyle(color: color),
                            child: widget.child,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
