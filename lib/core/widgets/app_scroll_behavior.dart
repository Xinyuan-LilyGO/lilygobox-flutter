/*
 * @Description: 全局鼠标滚轮平滑滚动，保留嵌套滚动、触控板和减少动画偏好。
 * @Author: LILYGO_L
 * @Date: 2026-10-12 00:00:00
 * @LastEditTime: 2026-10-12 00:00:00
 * @License: GPL 3.0
 */
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final controller = details.controller;
    if (controller == null || MediaQuery.disableAnimationsOf(context)) {
      return super.buildScrollbar(context, child, details);
    }
    return super.buildScrollbar(
      context,
      _WheelRegion(
        controller: controller,
        direction: details.direction,
        child: child,
      ),
      details,
    );
  }
}

class _WheelRegion extends StatefulWidget {
  const _WheelRegion({
    required this.controller,
    required this.direction,
    required this.child,
  });
  final ScrollController controller;
  final AxisDirection direction;
  final Widget child;

  @override
  State<_WheelRegion> createState() => _WheelRegionState();
}

class _WheelRegionState extends State<_WheelRegion> {
  double? _target;
  ScrollPosition? _position;

  /// 按实际轴向及 Shift 修饰键换算滚轮位移。
  double _delta(PointerScrollEvent event) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final swap =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final horizontal = axisDirectionToAxis(widget.direction) == Axis.horizontal;
    final delta = horizontal != swap
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    return axisDirectionIsReversed(widget.direction) ? -delta : delta;
  }

  /// 仅接管能产生位移的鼠标滚轮，让嵌套控件在边界处交给外层。
  bool accepts(PointerScrollEvent event) {
    if (!mounted ||
        event.kind != PointerDeviceKind.mouse ||
        !widget.controller.hasClients ||
        widget.controller.positions.length != 1) {
      return false;
    }
    final position = widget.controller.position;
    if (!position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return false;
    }
    final delta = _delta(event);
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    return delta != 0 && target != position.pixels;
  }

  /// 连续滚轮累计到同一目标，反向滚动立即从当前位置响应。
  void scroll(PointerSignalEvent signal) {
    final event = signal as PointerScrollEvent;
    if (!accepts(event)) return;
    final position = widget.controller.position;
    final delta = _delta(event);
    if (_position != position ||
        !position.isScrollingNotifier.value ||
        (_target != null && (_target! - position.pixels) * delta < 0)) {
      _target = position.pixels;
    }
    _position = position;
    final target = (_target! + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _target = target;
    unawaited(
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      _WheelHitRegion(state: this, child: widget.child);
}

class _WheelHitRegion extends SingleChildRenderObjectWidget {
  const _WheelHitRegion({required this.state, required super.child});
  final _WheelRegionState state;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _WheelRenderRegion(state);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _WheelRenderRegion renderObject,
  ) {
    renderObject.state = state;
  }
}

class _WheelRenderRegion extends RenderProxyBox {
  _WheelRenderRegion(this.state);
  _WheelRegionState state;
  List<_WheelRenderRegion> _regions = [];

  /// 在原生滚轮处理前参与事件仲裁，优先选择实际命中的最深层滚动区域。
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    hitTestChildren(result, position: position);
    _regions = result.path
        .map((entry) => entry.target)
        .whereType<_WheelRenderRegion>()
        .toList()
        .reversed
        .toList();
    return true;
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is! PointerScrollEvent) return;
    for (final region in _regions) {
      if (region.state.accepts(event)) {
        GestureBinding.instance.pointerSignalResolver.register(
          event,
          region.state.scroll,
        );
        return;
      }
    }
  }
}
