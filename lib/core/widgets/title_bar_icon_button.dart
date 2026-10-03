/*
 * @Description: 统一标题栏圆形图标按钮的尺寸、悬停动画和点击反馈。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-03 23:56:45
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../theme/definition.dart';
import 'interaction_decoration.dart';
import 'menu_item_surface.dart';

/// 标题栏的共用圆形图标按钮，统一尺寸、悬停过渡、波纹和窗口失焦配色。
class TitleBarIconButton extends StatefulWidget {
  const TitleBarIconButton({
    super.key,
    required this.onPressed,
    required this.isFocused,
    required this.theme,
    required this.icon,
    this.size = 24,
    this.iconSize = 16,
  });

  final VoidCallback? onPressed;
  final bool isFocused;
  final AppTheme theme;
  final IconData icon;
  final double size;
  final double iconSize;

  @override
  State<TitleBarIconButton> createState() => _TitleBarIconButtonState();
}

class _TitleBarIconButtonState extends State<TitleBarIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = widget.onPressed != null),
      onExit: (_) => setState(() => _isHovered = false),
      child: InteractionDecoration(
        palette: widget.theme,
        duration: MenuItemSurface.animationDuration,
        curve: MenuItemSurface.animationCurve,
        decoration: BoxDecoration(
          color: _isHovered && widget.onPressed != null
              ? widget.theme.primaryTextHoverColor
              : widget.theme.primary,
          shape: BoxShape.circle,
        ),
        // 墨水层位于背景上方，点击波纹不会被悬停背景遮挡。
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onPressed,
              splashFactory: InkRipple.splashFactory,
              customBorder: const CircleBorder(),
              hoverColor: Colors.transparent,
              highlightColor: widget.theme.textColorPrimary.withValues(
                alpha: 0.04,
              ),
              splashColor: widget.theme.textColorPrimary.withValues(
                alpha: 0.12,
              ),
              child: Center(
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: widget.isFocused
                      ? widget.theme.iconColor
                      : widget.theme.inactiveIconColor,
                  fill: 1,
                  weight: 400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
