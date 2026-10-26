/*
 * @Description: 统一菜单的淡入和轻微展开动画，支持外部进度及系统减少动画设置。
 * @Author: LILYGO_L
 * @Date: 2026-10-07 00:00:00
 * @LastEditTime: 2026-10-07 00:00:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import 'interaction_decoration.dart';

/// 普通浮层自行播放一次；账号、文本选择和托盘菜单可接入已有动画进度。
class PopupMenuTransition extends StatefulWidget {
  const PopupMenuTransition({
    super.key,
    required this.child,
    this.animation,
    this.alignment = Alignment.topLeft,
    this.fade = true,
    this.fadeKey,
  });

  static const duration = InteractionDecoration.animationDuration;
  static const beginScale = 0.96;
  final Widget child;
  final Animation<double>? animation;
  final Alignment alignment;
  // Flutter 文本选择层和原生托盘宿主已处理透明度，避免重复叠加淡入。
  final bool fade;
  final Key? fadeKey;

  @override
  State<PopupMenuTransition> createState() => _PopupMenuTransitionState();
}

class _PopupMenuTransitionState extends State<PopupMenuTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PopupMenuTransition.duration,
    );
    if (widget.animation == null) _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final progress = MediaQuery.disableAnimationsOf(context)
        ? const AlwaysStoppedAnimation<double>(1)
        : widget.animation ?? _controller;
    final child = SizeTransition(
      axis: Axis.vertical,
      axisAlignment: widget.alignment.y,
      sizeFactor: Tween<double>(
        begin: PopupMenuTransition.beginScale,
        end: 1,
      ).animate(progress),
      child: widget.child,
    );
    return widget.fade
        ? FadeTransition(key: widget.fadeKey, opacity: progress, child: child)
        : child;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
