import 'dart:math' as math;
import 'dart:ui' show SemanticsAction;

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Scrollbar;

import '../../../../core/widgets/app_scroll_behavior.dart';

class ChatHistoryScrollbar extends StatefulWidget {
  const ChatHistoryScrollbar({
    super.key,
    required this.controller,
    required this.readLogicalFraction,
    required this.seek,
    required this.isSeeking,
    required this.readUnits,
    required this.usesLogicalNavigation,
    required this.child,
  });

  final ScrollController controller;
  final double Function() readLogicalFraction;
  final void Function(double fraction, bool logicalNavigation) seek;
  final bool Function() isSeeking;
  final int Function() readUnits;
  final bool Function() usesLogicalNavigation;
  final Widget child;

  @override
  State<ChatHistoryScrollbar> createState() => _ChatHistoryScrollbarState();
}

class _ChatHistoryScrollbarState extends State<ChatHistoryScrollbar> {
  final _controller = ScrollController();
  _HistoryScrollbarPosition? _position;
  BuildContext? _notificationContext;
  bool _scheduled = false;
  bool _synchronizing = false;
  bool _logicalNavigation = false;
  double _fraction = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleSync);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(ChatHistoryScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleSync);
      widget.controller.addListener(_scheduleSync);
      _detachPosition();
    }
    _scheduleSync();
  }

  void _detachPosition() {
    final position = _position;
    if (position == null) return;
    position.removeListener(_seek);
    position.isScrollingNotifier.removeListener(_scheduleSync);
    _controller.detach(position);
    position.dispose();
    _position = null;
  }

  void _scheduleSync() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted ||
          !widget.controller.hasClients ||
          widget.controller.positions.length != 1) {
        return;
      }
      final source = widget.controller.position;
      if (!source.hasPixels ||
          !source.hasContentDimensions ||
          !source.hasViewportDimension) {
        return;
      }
      var position = _position;
      if (position == null || !identical(position.source, source)) {
        _detachPosition();
        position = _HistoryScrollbarPosition(
          source: source,
          context: _HistoryScrollbarContext(source.context),
          onPage: (delta) {
            final target = _notificationContext;
            if (target == null || !target.mounted) return;
            AppScrollBehavior.scrollByPage(target, source, delta);
          },
        );
        _position = position;
        _controller.attach(position);
        position.addListener(_seek);
        position.isScrollingNotifier.addListener(_scheduleSync);
      }
      if (position.isScrollingNotifier.value || widget.isSeeking()) return;
      _logicalNavigation = widget.usesLogicalNavigation();
      final extent = _logicalNavigation
          ? source.viewportDimension * math.max(1, widget.readUnits())
          : source.maxScrollExtent;
      final previous = position.pixels;
      final pixels = _logicalNavigation
          ? widget.readLogicalFraction().clamp(0.0, 1.0) * extent
          : source.pixels.clamp(0.0, extent);
      _fraction = extent > 0 ? pixels / extent : 0;
      final dimensionsChanged =
          !position.hasContentDimensions ||
          position.maxScrollExtent != extent ||
          position.viewportDimension != source.viewportDimension;
      if (!dimensionsChanged && previous == pixels) return;
      _synchronizing = true;
      if (dimensionsChanged) {
        position.applyViewportDimension(source.viewportDimension);
        position.applyContentDimensions(0, extent);
      }
      position.synchronize(pixels);
      _synchronizing = false;
      final target = _notificationContext;
      if (target == null || !target.mounted) return;
      final metrics = position.copyWith();
      if (dimensionsChanged) {
        ScrollMetricsNotification(
          metrics: metrics,
          context: target,
        ).dispatch(target);
      }
      if (previous != pixels) {
        ScrollUpdateNotification(
          metrics: metrics,
          context: target,
          scrollDelta: pixels - previous,
        ).dispatch(target);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _seek() {
    final position = _position;
    if (!mounted ||
        _synchronizing ||
        position == null ||
        !_controller.hasClients ||
        !widget.controller.hasClients ||
        widget.controller.positions.length != 1 ||
        !position.hasContentDimensions ||
        !position.hasPixels ||
        position.maxScrollExtent <= 0) {
      return;
    }
    final fraction = (position.pixels / position.maxScrollExtent).clamp(
      0.0,
      1.0,
    );
    final delta = fraction - _fraction;
    _fraction = fraction;
    final source = widget.controller.position;
    if (!source.hasPixels) return;
    AppUserScrollNotification(position: source, delta: delta).dispatch(context);
    widget.seek(fraction, _logicalNavigation);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleSync);
    _detachPosition();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScrollDecoration(
    controller: widget.controller,
    builder: _buildScrollbar,
    child: widget.child,
  );

  Widget _buildScrollbar(BuildContext context, Widget viewport) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) =>
            notification.metrics is _HistoryScrollbarMetrics,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) =>
              notification.metrics is _HistoryScrollbarMetrics,
          child: Scrollbar(
            controller: _controller,
            interactive: true,
            notificationPredicate: (notification) =>
                notification.metrics is _HistoryScrollbarMetrics,
            child: Builder(
              builder: (context) {
                _notificationContext = context;
                return NotificationListener<ScrollMetricsNotification>(
                  onNotification: (notification) {
                    if (notification.metrics is! _HistoryScrollbarMetrics) {
                      _scheduleSync();
                    }
                    return false;
                  },
                  child: viewport,
                );
              },
            ),
          ),
        ),
      );
}

class _HistoryScrollbarPosition extends ScrollPositionWithSingleContext {
  _HistoryScrollbarPosition({
    required this.source,
    required this.onPage,
    required super.context,
  }) : super(
         physics: const ClampingScrollPhysics(),
         initialPixels: 0,
         keepScrollOffset: false,
       );

  final ScrollPosition source;
  final ValueChanged<double> onPage;

  @override
  Future<void> moveTo(
    double to, {
    Duration? duration,
    Curve? curve,
    bool? clamp = true,
  }) {
    final delta = to - pixels;
    if (delta != 0) onPage(delta);
    return Future<void>.value();
  }

  @override
  void pointerScroll(double delta) => source.pointerScroll(delta);

  void synchronize(double value) => forcePixels(value);

  @override
  void goBallistic(double velocity) => goIdle();

  @override
  FixedScrollMetrics copyWith({
    double? minScrollExtent,
    double? maxScrollExtent,
    double? pixels,
    double? viewportDimension,
    AxisDirection? axisDirection,
    double? devicePixelRatio,
  }) => _HistoryScrollbarMetrics(
    minScrollExtent:
        minScrollExtent ?? (hasContentDimensions ? this.minScrollExtent : null),
    maxScrollExtent:
        maxScrollExtent ?? (hasContentDimensions ? this.maxScrollExtent : null),
    pixels: pixels ?? this.pixels,
    viewportDimension:
        viewportDimension ??
        (hasViewportDimension ? this.viewportDimension : null),
    axisDirection: axisDirection ?? this.axisDirection,
    devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
  );
}

class _HistoryScrollbarContext implements ScrollContext {
  _HistoryScrollbarContext(this.source);

  final ScrollContext source;

  @override
  BuildContext? get notificationContext => source.notificationContext;

  @override
  BuildContext get storageContext => source.storageContext;

  @override
  TickerProvider get vsync => source.vsync;

  @override
  AxisDirection get axisDirection => source.axisDirection;

  @override
  double get devicePixelRatio => source.devicePixelRatio;

  @override
  void setIgnorePointer(bool value) {}

  @override
  void setCanDrag(bool value) {}

  @override
  void setSemanticsActions(Set<SemanticsAction> actions) {}

  @override
  void saveOffset(double offset) {}
}

class _HistoryScrollbarMetrics extends FixedScrollMetrics {
  _HistoryScrollbarMetrics({
    required super.minScrollExtent,
    required super.maxScrollExtent,
    required super.pixels,
    required super.viewportDimension,
    required super.axisDirection,
    required super.devicePixelRatio,
  });
}
