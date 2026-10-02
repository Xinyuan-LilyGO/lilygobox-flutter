/*
 * @Description: 提供最小化、最大化和关闭等窗口控制按钮的通用样式。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-02 21:44:28
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../core/widgets/interaction_decoration.dart';

class AppTitleBarControlsButtonTemplate extends StatefulWidget {
  const AppTitleBarControlsButtonTemplate({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.hoverColor,
    required this.backgroundColor,
    this.hoverIconColor,
    required this.iconColor,

    this.iconSize = 20,
    this.iconWeight = 300.0,
    this.rotateAngle = 0.0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color hoverColor;
  final Color backgroundColor;
  final Color? hoverIconColor;
  final Color iconColor;
  final double iconSize;
  final double iconWeight;
  final double rotateAngle;

  @override
  State<AppTitleBarControlsButtonTemplate> createState() =>
      _AppTitleBarControlsButtonTemplateState();
}

class _AppTitleBarControlsButtonTemplateState
    extends State<AppTitleBarControlsButtonTemplate> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hovered = _isHovered && widget.onPressed != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        width: 45,
        height: 30,
        child: InteractionDecoration(
          palette: widget.backgroundColor,
          decoration: BoxDecoration(
            color: hovered ? widget.hoverColor : widget.backgroundColor,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              onTap: widget.onPressed,
              child: Center(
                child: Transform.rotate(
                  angle: widget.rotateAngle * (3.1415926535 / 180),
                  child: Icon(
                    widget.icon,
                    size: widget.iconSize,
                    color: hovered
                        ? widget.hoverIconColor ?? widget.iconColor
                        : widget.iconColor,
                    weight: widget.iconWeight,
                    grade: -25.0,
                    opticalSize: 48.0,
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
