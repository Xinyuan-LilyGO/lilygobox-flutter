/*
 * @Description: 提供最小化、最大化和关闭等窗口控制按钮的通用样式。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

// 更新窗口控制按钮组件，添加基于AnimatedContainer的颜色渐变动画
class AppTitleBarControlsButtonTemplate extends StatefulWidget {
  const AppTitleBarControlsButtonTemplate({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.hoverColor,
    required this.iconColor,

    this.iconSize = 20,
    this.iconWeight = 300.0,
    this.rotateAngle = 0.0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color hoverColor;
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        width: 45,
        height: 30,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
              color: _isHovered ? widget.hoverColor : Colors.transparent,
              child: Center(
                child: Transform.rotate(
                  angle: widget.rotateAngle * (3.1415926535 / 180),
                  child: Icon(
                    widget.icon,
                    size: widget.iconSize,
                    color: widget.iconColor,
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
