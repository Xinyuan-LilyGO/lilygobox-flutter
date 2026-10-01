/*
 * @Description: 统一标题栏圆形图标按钮的尺寸、悬停动画和点击反馈。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 16:54:38
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../theme/definition.dart';
import 'menu_item_surface.dart';

/// 标题栏的共用圆形图标按钮，统一尺寸、悬停过渡、波纹和窗口失焦配色。
class TitleBarIconButton extends StatefulWidget {
  const TitleBarIconButton({
    super.key,
    required this.onPressed,
    required this.isFocused,
    required this.theme,
    required this.icon,
  });

  final VoidCallback onPressed;
  final bool isFocused;
  final AppTheme theme;
  final IconData icon;

  @override
  State<TitleBarIconButton> createState() => _TitleBarIconButtonState();
}

class _TitleBarIconButtonState extends State<TitleBarIconButton> {
  static const double _diameter = 24;
  static const double _iconSize = 16;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        width: _diameter,
        height: _diameter,
        duration: MenuItemSurface.animationDuration,
        curve: MenuItemSurface.animationCurve,
        decoration: BoxDecoration(
          color: _isHovered
              ? widget.theme.primaryTextHoverColor
              : widget.theme.primary,
          shape: BoxShape.circle,
        ),
        // 墨水层位于背景上方，点击波纹不会被悬停背景遮挡。
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
            splashColor: widget.theme.textColorPrimary.withValues(alpha: 0.12),
            child: Center(
              child: Icon(
                widget.icon,
                size: _iconSize,
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
    );
  }
}
