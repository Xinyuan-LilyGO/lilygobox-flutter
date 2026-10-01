/*
 * @Description: 提供带圆形背景及悬停颜色动画的通用图标按钮。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../theme/definition.dart';

class AnimatedCircleIconButton extends StatefulWidget {
  const AnimatedCircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.theme,
    this.size = 33,
    this.iconSize = 19,
    this.duration = const Duration(milliseconds: 150),
  });

  final IconData icon;
  final VoidCallback onPressed;
  final AppTheme theme;
  final double size;
  final double iconSize;
  final Duration duration;

  @override
  State<AnimatedCircleIconButton> createState() =>
      _AnimatedCircleIconButtonState();
}

class _AnimatedCircleIconButtonState extends State<AnimatedCircleIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: widget.duration,
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _isHovered
              ? widget.theme.iconHoverColor
              : widget.theme.iconBackgroundColor,
          shape: BoxShape.circle,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(widget.size / 2),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: widget.theme.iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
