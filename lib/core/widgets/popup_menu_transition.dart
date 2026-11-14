/*
 * @Description: 统一菜单的淡入和轻微展开动画，支持外部进度及系统减少动画设置。
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
    // 只调整布局高度，不裁剪卡片外侧的圆角阴影。
    final child = AnimatedBuilder(
      animation: progress,
      builder: (context, child) => Align(
        alignment: widget.alignment,
        widthFactor: 1,
        heightFactor: Tween<double>(
          begin: PopupMenuTransition.beginScale,
          end: 1,
        ).evaluate(progress),
        child: child,
      ),
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

/// 菜单内部页面统一淡入淡出，退出页不响应鼠标和键盘操作。
class PopupMenuPageTransition extends StatelessWidget {
  const PopupMenuPageTransition({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : PopupMenuTransition.duration,
    switchInCurve: InteractionDecoration.animationCurve,
    switchOutCurve: InteractionDecoration.animationCurve,
    transitionBuilder: (child, animation) =>
        FadeTransition(opacity: animation, child: child),
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.bottomCenter,
      children: [
        for (final child in previous)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ExcludeFocus(child: ExcludeSemantics(child: child)),
            ),
          ),
        if (current != null) current,
      ],
    ),
    child: child,
  );
}
