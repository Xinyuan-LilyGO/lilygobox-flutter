/*
 * @Description: 全局平滑滚轮与鼠标中键连续滚动，保留嵌套仲裁和减少动画偏好。
 */
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 公共滚动在启动位移动画前通知用户意图，便于聊天取消底部跟随。
class AppUserScrollNotification extends Notification {
  const AppUserScrollNotification({
    required this.position,
    required this.delta,
  });

  final ScrollPosition position;
  final double delta;
}

class WheelScrollAcceleration {
  static const _interval = Duration(milliseconds: 100);
  static const _fastInterval = Duration(milliseconds: 25);
  Duration? _lastTime;
  Offset _lastDelta = Offset.zero;

  Offset apply(Offset delta, Duration timeStamp, {bool continuing = true}) {
    final elapsed = _lastTime == null ? null : timeStamp - _lastTime!;
    final fast =
        continuing &&
        timeStamp > Duration.zero &&
        elapsed != null &&
        elapsed > Duration.zero &&
        elapsed <= _interval &&
        delta.dx * _lastDelta.dx + delta.dy * _lastDelta.dy > 0;
    final multiplier = fast
        ? (1 +
                  2 *
                      (_interval.inMicroseconds - elapsed.inMicroseconds) /
                      (_interval - _fastInterval).inMicroseconds)
              .clamp(1.0, 3.0)
        : 1.0;
    _lastTime = timeStamp;
    _lastDelta = delta;
    return delta * multiplier;
  }

  void reset() {
    _lastTime = null;
    _lastDelta = Offset.zero;
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior({this.scrollbars = true}) : _configuration = null;

  const AppScrollBehavior._({
    required this.scrollbars,
    required this._configuration,
  });

  final ScrollBehavior? _configuration;

  /// 滚动条外缘到所属承载区边缘的统一距离；已有外层留白时须扣除。
  static const scrollbarEdgeInset = 6.0;

  /// 自绘滚动条时只关闭装饰，保留平滑滚轮与嵌套事件仲裁。
  final bool scrollbars;

  @override
  AppScrollBehavior copyWith({
    bool? scrollbars,
    bool? overscroll,
    Set<PointerDeviceKind>? dragDevices,
    MultitouchDragStrategy? multitouchDragStrategy,
    Set<LogicalKeyboardKey>? pointerAxisModifiers,
    ScrollPhysics? physics,
    TargetPlatform? platform,
    ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior,
  }) => AppScrollBehavior._(
    scrollbars: scrollbars ?? this.scrollbars,
    configuration: (_configuration ?? const MaterialScrollBehavior()).copyWith(
      overscroll: overscroll,
      dragDevices: dragDevices,
      multitouchDragStrategy: multitouchDragStrategy,
      pointerAxisModifiers: pointerAxisModifiers,
      physics: physics,
      platform: platform,
      keyboardDismissBehavior: keyboardDismissBehavior,
    ),
  );

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      _configuration?.getPlatform(context) ?? super.getPlatform(context);

  @override
  Set<PointerDeviceKind> get dragDevices =>
      _configuration?.dragDevices ?? super.dragDevices;

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers =>
      _configuration?.pointerAxisModifiers ?? super.pointerAxisModifiers;

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      _configuration?.getMultitouchDragStrategy(context) ??
      super.getMultitouchDragStrategy(context);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      _configuration?.getScrollPhysics(context) ??
      super.getScrollPhysics(context);

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) =>
      _configuration?.getKeyboardDismissBehavior(context) ??
      super.getKeyboardDismissBehavior(context);

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      _configuration?.buildOverscrollIndicator(context, child, details) ??
      super.buildOverscrollIndicator(context, child, details);

  @override
  bool shouldNotify(covariant AppScrollBehavior oldDelegate) =>
      scrollbars != oldDelegate.scrollbars ||
      _configuration.runtimeType != oldDelegate._configuration.runtimeType ||
      (_configuration?.shouldNotify(oldDelegate._configuration!) ?? false);

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
    if (!TickerMode.valuesOf(context).enabled) {
      _stopAutoScroll();
      _stopWheelScroll();
    }
    if (!widget.smoothWheel) _stopWheelScroll();
  }

  @override
  void didUpdateWidget(covariant _WheelRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.direction != widget.direction) {
      _stopAutoScroll();
      _stopWheelScroll();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopAutoScroll();
      _stopWheelScroll();
    }
  }

  @override
  void deactivate() {
    _stopAutoScroll();
    _stopWheelScroll();
    super.deactivate();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _stopWheelScroll();
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
  _WheelScrollActivity? _wheelActivity;
  _WheelSimulation? _wheelSimulation;
  final _wheelAcceleration = WheelScrollAcceleration();

  void _stopWheelScroll() {
    _wheelActivity?.stop();
    _wheelActivity = null;
    _wheelSimulation = null;
    _target = null;
    _position = null;
    _wheelAcceleration.reset();
  }

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
    final rawDelta = _delta(event);
    AppUserScrollNotification(
      position: position,
      delta: rawDelta,
    ).dispatch(context);
    final continuing =
        _position == position && (_wheelActivity?.active ?? false);
    final delta = _wheelAcceleration
        .apply(Offset(rawDelta, 0), event.timeStamp, continuing: continuing)
        .dx;
    final reversing =
        _target != null && (_target! - position.pixels) * delta < 0;
    if (!continuing || reversing) _target = position.pixels;
    _position = position;
    final target = (_target! + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _target = target;
    if (position is ScrollPositionWithSingleContext) {
      if (continuing) {
        _wheelSimulation!.retarget(target, reverse: reversing);
      } else {
        final simulation = _WheelSimulation(position.pixels, target);
        final activity = _WheelScrollActivity(
          position,
          simulation,
          vsync: position.context.vsync,
        );
        _wheelSimulation = simulation;
        _wheelActivity = activity;
        position.beginActivity(activity);
      }
    } else {
      // 自定义滚动位置可以自行管理滚动活动的生命周期。
      unawaited(
        position.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) =>
      _WheelHitRegion(state: this, child: widget.child);
}

/// 一组连续滚轮输入共用一个原生滚动活动，更新目标不会重置
/// 其计时器；触摸或滚动条交互仍由 Flutter 正常释放该活动。
class _WheelScrollActivity extends DrivenScrollActivity {
  _WheelScrollActivity(super.delegate, super.simulation, {required super.vsync})
    : super.simulation();

  bool active = true;

  @override
  bool applyMoveTo(double value) {
    final position = delegate as ScrollPosition;
    final bounded = value
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    final applied = super.applyMoveTo(bounded);
    // 连续滚轮输入期间内容可能缩短，应停在新的边界，
    // 避免旧的模拟过程恢复已失效的滚动位置。
    return applied && bounded == value;
  }

  void stop() {
    if (active) delegate.goIdle();
  }

  @override
  void dispose() {
    active = false;
    super.dispose();
  }
}

/// 新增滚轮输入时，三次 Hermite 曲线段保持当前速度。
/// 各曲线段共用动画时钟，反向输入会丢弃尚未完成的正向尾段。
class _WheelSimulation extends Simulation {
  _WheelSimulation(this._from, this._target)
    : _startVelocity = 3 * (_target - _from) / _duration;

  static const _duration = .200;
  double _from;
  double _target;
  double _startVelocity;
  double _startTime = 0;
  double _time = 0;

  void retarget(double target, {required bool reverse}) {
    final current = x(_time);
    final velocity = dx(_time);
    _from = current;
    _target = target;
    _startTime = _time;
    final distance = target - current;
    // 此斜率范围可确保曲线段在受限边界附近保持单调。
    _startVelocity = reverse || velocity * distance < 0
        ? 0
        : velocity.sign *
              math.min(velocity.abs(), 3 * distance.abs() / _duration);
  }

  double _progress(double time) =>
      ((time - _startTime) / _duration).clamp(0, 1);

  @override
  double x(double time) {
    _time = time;
    final t = _progress(time);
    final t2 = t * t;
    final t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * _from +
        (t3 - 2 * t2 + t) * _duration * _startVelocity +
        (-2 * t3 + 3 * t2) * _target;
  }

  @override
  double dx(double time) {
    final t = _progress(time);
    return ((6 * t * t - 6 * t) * _from +
            (3 * t * t - 4 * t + 1) * _duration * _startVelocity +
            (-6 * t * t + 6 * t) * _target) /
        _duration;
  }

  @override
  bool isDone(double time) => time - _startTime >= _duration;
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
