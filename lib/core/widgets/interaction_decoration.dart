/*
 * @Description: 统一交互背景渐变，切换主题时同步更新配色并保留子组件状态。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 22:00:00
 * @LastEditTime: 2026-10-02 22:01:29
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

/// 只为同一配色下的交互做渐变，避免旧主题颜色滞留在新主题页面上。
class InteractionDecoration extends StatefulWidget {
  const InteractionDecoration({
    super.key,
    required this.palette,
    required this.decoration,
    required this.child,
    this.duration = animationDuration,
    this.curve = animationCurve,
  }) : _colorBuilder = null;

  InteractionDecoration.color({
    super.key,
    required this.palette,
    required Color color,
    required Widget Function(BuildContext, Color) builder,
    this.duration = animationDuration,
    this.curve = animationCurve,
  }) : decoration = BoxDecoration(color: color),
       child = const SizedBox.shrink(),
       _colorBuilder = builder;

  final Widget Function(BuildContext, Color)? _colorBuilder;

  static const animationDuration = Duration(milliseconds: 150);
  static const animationCurve = Curves.linear;

  final Object palette;
  final BoxDecoration decoration;
  final Widget child;
  final Duration duration;
  final Curve curve;

  @override
  State<InteractionDecoration> createState() => _InteractionDecorationState();
}

class _InteractionDecorationState extends State<InteractionDecoration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );
  late DecorationTween _decoration = DecorationTween(
    begin: widget.decoration,
    end: widget.decoration,
  );

  Decoration get _current =>
      _decoration.transform(widget.curve.transform(_controller.value));

  @override
  void didUpdateWidget(InteractionDecoration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.palette != widget.palette) {
      // 不重建子树，保留焦点、菜单状态；同时终止旧配色的交互动画。
      _decoration = DecorationTween(
        begin: widget.decoration,
        end: widget.decoration,
      );
      _controller.value = 1;
    } else if (oldWidget.decoration != widget.decoration) {
      _decoration = DecorationTween(begin: _current, end: widget.decoration);
      _controller.duration = widget.duration;
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final decoration = disableAnimations ? widget.decoration : _current;
        if (widget._colorBuilder != null) {
          return widget._colorBuilder!(
            context,
            (decoration as BoxDecoration).color!,
          );
        }
        return DecoratedBox(decoration: decoration, child: child);
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
