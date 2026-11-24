/*
 * @Description: 全局平滑滚轮，保留嵌套仲裁和减少动画偏好。
 */
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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

class WindowedScrollController extends ScrollController {
  bool hasUnloadedBefore = false;
  bool hasUnloadedAfter = false;

  bool _canExtendTo(ScrollPosition position, double target) =>
      (hasUnloadedBefore && target < position.minScrollExtent) ||
      (hasUnloadedAfter && target > position.maxScrollExtent);
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

  static void scrollByPage(
    BuildContext context,
    ScrollPosition position,
    double delta,
  ) {
    final region = context.findAncestorStateOfType<_WheelRegionState>();
    AppUserScrollNotification(
      position: position,
      delta: delta,
    ).dispatch(context);
    if (region == null || !region.widget.smoothWheel) {
      position.pointerScroll(delta);
    } else {
      region._wheelAcceleration.reset();
      region._scrollBy(position, delta);
    }
  }

  static void correctForContentChange(
    ScrollPosition position,
    double correction,
  ) {
    if (!correction.isFinite || !position.hasPixels) return;
    position.correctBy(correction);
    final region = _WheelRegionState._regionsByPosition[position];
    final simulation = region?._wheelSimulation;
    if (region != null &&
        (region._wheelActivity?.active ?? false) &&
        simulation != null) {
      region._target = region._target! + correction;
      simulation.shift(correction);
    }
  }

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
    final inherited = ScrollConfiguration.of(context);
    final showScrollbar =
        scrollbars && (inherited is! AppScrollBehavior || inherited.scrollbars);
    final decoration = context
        .dependOnInheritedWidgetOfExactType<AppScrollDecoration>();
    final content =
        decoration != null && identical(decoration.controller, controller)
        ? decoration.builder(context, child)
        : showScrollbar
        ? super.buildScrollbar(context, child, details)
        : child;
    return controller == null
        ? content
        : _WheelRegion(
            controller: controller,
            direction: details.direction,
            smoothWheel: !MediaQuery.disableAnimationsOf(context),
            child: content,
          );
  }
}

class AppScrollDecoration extends InheritedWidget {
  const AppScrollDecoration({
    super.key,
    required this.controller,
    required this.builder,
    required super.child,
  });

  final ScrollController controller;
  final Widget Function(BuildContext, Widget) builder;

  @override
  bool updateShouldNotify(AppScrollDecoration oldWidget) =>
      controller != oldWidget.controller || builder != oldWidget.builder;
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
    with WidgetsBindingObserver {
  static final _regionsByPosition = Expando<_WheelRegionState>();
  static const _readerChannel = MethodChannel('lilygobox/reader_mode');
  static int _nextReader = 0;
  static int? _activeReader;
  int? _reader;
  double? _target;
  ScrollPosition? _position;
  _WheelScrollActivity? _wheelActivity;
  _WheelSimulation? _wheelSimulation;
  final _wheelAcceleration = WheelScrollAcceleration();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) _stopReader();
    if (!TickerMode.valuesOf(context).enabled || !widget.smoothWheel) {
      _stopWheelScroll();
    }
  }

  @override
  void didUpdateWidget(covariant _WheelRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.direction != widget.direction) {
      _stopReader();
      _stopWheelScroll();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopReader();
      _stopWheelScroll();
    }
  }

  @override
  void deactivate() {
    _stopReader();
    _stopWheelScroll(afterFrame: true);
    super.deactivate();
  }

  @override
  void dispose() {
    _stopReader();
    _stopWheelScroll();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _canRead =>
      mounted &&
      widget.controller.positions.length == 1 &&
      widget.controller.position.hasContentDimensions &&
      widget.controller.position.physics.allowUserScrolling &&
      (widget.controller.position.maxScrollExtent >
              widget.controller.position.minScrollExtent ||
          (_window?.hasUnloadedBefore ?? false) ||
          (_window?.hasUnloadedAfter ?? false));

  void _stopReader() {
    final session = _reader;
    if (session == null) return;
    _reader = null;
    if (_activeReader == session) _activeReader = null;
    unawaited(
      _readerChannel
          .invokeMethod<void>('stop', session)
          .catchError((Object _, StackTrace _) {}),
    );
  }

  Future<void> _startReader(Offset point) async {
    if (_activeReader != null || !_canRead) return;
    final session = _reader = _activeReader = ++_nextReader;
    final ratio = View.of(context).devicePixelRatio;
    var accepted = false;
    try {
      final started = await _readerChannel.invokeMethod<bool>('start', [
        session,
        axisDirectionToAxis(widget.direction) == Axis.horizontal,
        (point.dx * ratio).round(),
        (point.dy * ratio).round(),
      ]);
      if (started != true || _reader != session) return;
      accepted = true;
      _stopWheelScroll();
      while (_reader == session && _canRead) {
        await SchedulerBinding.instance.endOfFrame;
        if (_reader != session) break;
        final distance = await _readerChannel.invokeMethod<double>(
          'take',
          session,
        );
        if (!mounted || distance == null || _reader != session || !_canRead) {
          if (distance == null && _reader == session) _reader = null;
          break;
        }
        if (distance == 0) continue;
        final delta =
            (axisDirectionIsReversed(widget.direction) ? -distance : distance) /
            ratio;
        final position = widget.controller.position;
        AppUserScrollNotification(
          position: position,
          delta: delta,
        ).dispatch(context);
        position.pointerScroll(delta);
      }
      if (_reader == session && !_canRead) _stopReader();
    } on MissingPluginException {
      // Native reader mode is optional on platforms without the runner hook.
    } catch (_) {
      // A window can disappear while the native modal reader is active. The
      // session is cancelled below so that a late channel error cannot leave
      // the runner in reader mode.
    } finally {
      if (accepted && _reader == session) _stopReader();
      if (_reader == session) _reader = null;
      if (_activeReader == session) _activeReader = null;
    }
  }

  void _stopWheelScroll({bool afterFrame = false}) {
    final activity = _wheelActivity;
    if (activity != null && activity.active) {
      if (afterFrame) {
        WidgetsBinding.instance.addPostFrameCallback((_) => activity.stop());
      } else {
        activity.stop();
      }
    }
    _wheelActivity = null;
    _wheelSimulation = null;
    _target = null;
    if (_position case final position?) {
      if (identical(_regionsByPosition[position], this)) {
        _regionsByPosition[position] = null;
      }
    }
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
    if (!position.hasContentDimensions) return false;
    final delta = _delta(event);
    final target = position.pixels + delta;
    if (delta == 0) return false;
    if (_window?._canExtendTo(position, target) ?? false) {
      return position.physics.allowUserScrolling;
    }
    return position.physics.shouldAcceptUserOffset(position) &&
        target.clamp(position.minScrollExtent, position.maxScrollExtent) !=
            position.pixels;
  }

  WindowedScrollController? get _window => switch (widget.controller) {
    final WindowedScrollController controller => controller,
    _ => null,
  };

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
    _scrollBy(position, delta);
  }

  void _scrollBy(ScrollPosition position, double delta) {
    final continuing =
        _position == position && (_wheelActivity?.active ?? false);
    final reversing =
        _target != null && (_target! - position.pixels) * delta < 0;
    if (!continuing || reversing) _target = position.pixels;
    _position = position;
    _regionsByPosition[position] = this;
    final requested = _target! + delta;
    final target = (_window?._canExtendTo(position, requested) ?? false)
        ? requested
        : requested
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
    _target = target;
    if (position is ScrollPositionWithSingleContext) {
      if (continuing) {
        _wheelSimulation!.retarget(
          target,
          from: position.pixels,
          reverse: reversing,
        );
      } else {
        final simulation = _WheelSimulation(position.pixels, target);
        final activity = _WheelScrollActivity(
          position,
          simulation,
          window: _window,
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
  _WheelScrollActivity(
    super.delegate,
    super.simulation, {
    required this.window,
    required super.vsync,
  }) : super.simulation();

  final WindowedScrollController? window;
  bool active = true;

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool applyMoveTo(double value) {
    final position = delegate as ScrollPosition;
    final bounded = value
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    final applied = super.applyMoveTo(bounded);
    // 连续滚轮输入期间内容可能缩短，应停在新的边界，
    // 避免旧的模拟过程恢复已失效的滚动位置。
    return applied &&
        (bounded == value || (window?._canExtendTo(position, value) ?? false));
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

  void shift(double correction) {
    _from += correction;
    _target += correction;
  }

  void retarget(double target, {required double from, required bool reverse}) {
    final velocity = dx(_time);
    final interval = (_time - _startTime) * Duration.microsecondsPerSecond;
    _from = from;
    _target = target;
    _startTime = _time;
    final distance = target - from;
    if (interval > WheelScrollAcceleration._interval.inMicroseconds) {
      _startVelocity = 3 * distance / _duration;
      return;
    }
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
        event.buttons == kMiddleMouseButton &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows) {
      for (final region in _regions) {
        if (region.state._canRead) {
          unawaited(region.state._startReader(event.position));
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
