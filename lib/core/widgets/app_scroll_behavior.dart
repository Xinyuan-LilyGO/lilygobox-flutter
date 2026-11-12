/*
 * @Description: 全局平滑滚轮与鼠标中键连续滚动，保留嵌套仲裁和减少动画偏好。
 * @Author: LILYGO_L
 * @Date: 2026-10-12 00:00:00
 * @LastEditTime: 2026-11-12 11:40:05
 */
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// 公共滚动在启动位移动画前通知用户意图，便于聊天取消底部跟随。
class AppUserScrollNotification extends Notification {
  const AppUserScrollNotification({
    required this.position,
    required this.delta,
  });

  final ScrollPosition position;
  final double delta;
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior({this.scrollbars = true});

  /// 滚动条外缘到所属承载区边缘的统一距离；已有外层留白时须扣除。
  static const scrollbarEdgeInset = 6.0;

  /// 自绘滚动条时只关闭装饰，保留平滑滚轮与嵌套事件仲裁。
  /// 不使用 copyWith(scrollbars: false)，它会跳过整个 buildScrollbar。
  final bool scrollbars;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final controller = details.controller;
    final content = controller != null
        ? _WheelRegion(
            controller: controller,
            direction: details.direction,
            smoothWheel: !MediaQuery.disableAnimationsOf(context),
            child: child,
          )
        : child;
    return scrollbars
        ? super.buildScrollbar(context, content, details)
        : content;
  }
}

class _WheelRegion extends StatefulWidget {
  const _WheelRegion({
    required this.controller,
    required this.direction,
    required this.smoothWheel,
    required this.child,
  });
  final ScrollController controller;
  final AxisDirection direction;
  final bool smoothWheel;
  final Widget child;

  @override
  State<_WheelRegion> createState() => _WheelRegionState();
}

class _WheelRegionState extends State<_WheelRegion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static _WheelRegionState? _activeAutoScroll;
  static PointerEvent? _lastMiddleDown;
  static const _deadZone = 12.0;
  late final Ticker _autoTicker;
  OverlayEntry? _autoOverlay;
  ScrollPosition? _autoPosition;
  Offset _autoAnchor = Offset.zero;
  Offset _autoPointer = Offset.zero;
  Duration _lastTick = Duration.zero;
  PointerEvent? _activationEvent;

  @override
  void initState() {
    super.initState();
    _autoTicker = createTicker(_autoScrollTick);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.of(context)) _stopAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _WheelRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.direction != widget.direction) {
      _stopAutoScroll();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopAutoScroll();
  }

  @override
  void deactivate() {
    _stopAutoScroll();
    super.deactivate();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _autoTicker.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get canAutoScroll {
    if (!mounted ||
        !widget.controller.hasClients ||
        widget.controller.positions.length != 1) {
      return false;
    }
    final position = widget.controller.position;
    return position.hasContentDimensions &&
        position.maxScrollExtent > position.minScrollExtent &&
        position.physics.shouldAcceptUserOffset(position);
  }

  void _startAutoScroll(PointerDownEvent event) {
    if (!canAutoScroll) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _activeAutoScroll?._stopAutoScroll();
    _activeAutoScroll = this;
    _autoPosition = widget.controller.position;
    // 结束滚轮或回到底部的旧动画，避免与逐帧位移争用滚动位置。
    _autoPosition!.jumpTo(_autoPosition!.pixels);
    _target = null;
    _activationEvent = event.original ?? event;
    _autoAnchor = _autoPointer = event.position;
    _lastTick = Duration.zero;
    _autoOverlay = OverlayEntry(
      builder: (context) {
        final box = overlay.context.findRenderObject() as RenderBox;
        final anchor = box.globalToLocal(_autoAnchor);
        final colors = Theme.of(context).colorScheme;
        return Positioned.fill(
          child: ExcludeSemantics(
            child: MouseRegion(
              cursor: axisDirectionToAxis(widget.direction) == Axis.vertical
                  ? SystemMouseCursors.resizeUpDown
                  : SystemMouseCursors.resizeLeftRight,
              onExit: (_) => _stopAutoScroll(),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: [
                    Positioned(
                      left: anchor.dx - 14,
                      top: anchor.dy - 14,
                      child: DecoratedBox(
                        key: const ValueKey('app-middle-scroll-anchor'),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.outline),
                        ),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: RotatedBox(
                            quarterTurns:
                                axisDirectionToAxis(widget.direction) ==
                                    Axis.vertical
                                ? 0
                                : 1,
                            child: Icon(
                              Icons.unfold_more_rounded,
                              size: 20,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    GestureBinding.instance.pointerRouter.addGlobalRoute(_autoPointerEvent);
    HardwareKeyboard.instance.addHandler(_autoKeyEvent);
    overlay.insert(_autoOverlay!);
    _autoTicker.start();
  }

  bool _autoKeyEvent(KeyEvent event) {
    _stopAutoScroll();
    // Esc 专用于退出；其余按键仍交给原来的输入框及快捷键。
    return event.logicalKey == LogicalKeyboardKey.escape;
  }

  void _autoPointerEvent(PointerEvent event) {
    if (identical(event.original ?? event, _activationEvent)) return;
    if (event is PointerDownEvent ||
        event is PointerScrollEvent ||
        event is PointerCancelEvent) {
      _stopAutoScroll();
    } else if (event is PointerHoverEvent || event is PointerMoveEvent) {
      _autoPointer = event.position;
    } else if (event is PointerUpEvent &&
        (_autoPointer - _autoAnchor).distance > _deadZone) {
      // 短按松开后继续；按住中键移动则在松开时退出。
      _stopAutoScroll();
    }
  }

  void _autoScrollTick(Duration elapsed) {
    final position = _autoPosition;
    if (!canAutoScroll ||
        position == null ||
        !widget.controller.positions.contains(position)) {
      _stopAutoScroll();
      return;
    }
    final seconds =
        ((elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond)
            .clamp(0.0, .05);
    _lastTick = elapsed;
    final displacement = _autoPointer - _autoAnchor;
    final distance = axisDirectionToAxis(widget.direction) == Axis.vertical
        ? displacement.dy
        : displacement.dx;
    if (distance.abs() <= _deadZone) return;
    final speed = (math.pow(distance.abs() - _deadZone, 1.6) * 7).clamp(
      0.0,
      100000.0,
    );
    final direction = axisDirectionIsReversed(widget.direction) ? -1 : 1;
    final next = (position.pixels + distance.sign * direction * speed * seconds)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (next != position.pixels) {
      AppUserScrollNotification(
        position: position,
        delta: next - position.pixels,
      ).dispatch(context);
      position.jumpTo(next);
    }
  }

  void _stopAutoScroll() {
    if (_autoOverlay == null) return;
    _autoTicker.stop();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_autoPointerEvent);
    HardwareKeyboard.instance.removeHandler(_autoKeyEvent);
    _autoOverlay!.remove();
    _autoOverlay!.dispose();
    _autoOverlay = null;
    _autoPosition = null;
    _activationEvent = null;
    if (identical(_activeAutoScroll, this)) _activeAutoScroll = null;
  }

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
    if (!widget.smoothWheel ||
        !mounted ||
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
    AppUserScrollNotification(
      position: position,
      delta: delta,
    ).dispatch(context);
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
    if (event is PointerDownEvent &&
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kMiddleMouseButton) {
      if (identical(
        _WheelRegionState._lastMiddleDown,
        event.original ?? event,
      )) {
        return;
      }
      _WheelRegionState._lastMiddleDown = event.original ?? event;
      for (final region in _regions) {
        if (region.state.canAutoScroll) {
          region.state._startAutoScroll(event);
          break;
        }
      }
      return;
    }
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
