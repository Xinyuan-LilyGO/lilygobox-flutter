/*
 * @Description: 统一悬停提示的间距与延迟，隐藏页面时清理提示浮层。
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

class AppTooltipScope extends StatefulWidget {
  const AppTooltipScope({super.key, required this.child});

  final Widget child;

  @override
  State<AppTooltipScope> createState() => _AppTooltipScopeState();
}

class _AppTooltipScopeState extends State<AppTooltipScope> {
  final _currentRoute = ValueNotifier(true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentRoute.value = ModalRoute.isCurrentOf(context) ?? true;
  }

  @override
  Widget build(BuildContext context) =>
      _TooltipRouteScope(currentRoute: _currentRoute, child: widget.child);

  @override
  void dispose() {
    _currentRoute.dispose();
    super.dispose();
  }
}

class _TooltipRouteScope extends InheritedWidget {
  const _TooltipRouteScope({required this.currentRoute, required super.child});

  final ValueListenable<bool> currentRoute;

  static ValueListenable<bool>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_TooltipRouteScope>()
      ?.currentRoute;

  @override
  bool updateShouldNotify(_TooltipRouteScope oldWidget) =>
      !identical(currentRoute, oldWidget.currentRoute);
}

/// 共用悬停提示，文案由调用处提供本地化文本。
class AppTooltip extends StatefulWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
    this.verticalOffset,
  });

  static const Duration waitDuration = Duration(milliseconds: 500);

  /// Tooltip 与其触发控件之间的固定间距，所有普通悬停提示统一使用。
  static const double defaultVerticalOffset = 8;

  final String message;
  final Widget child;
  final double? verticalOffset;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  // 提示重建时保留按钮自身状态，避免影响点击反馈及内部控件。
  final _childKey = GlobalKey();
  ValueListenable<TickerModeData>? _tickerMode;
  ValueListenable<bool>? _currentRoute;
  Size? _viewportSize;
  TextScaler? _textScaler;
  bool _routeActive = true;
  bool _scopeActive = true;
  bool _active = true;
  bool _tooltipVisible = true;
  bool _hasActivity = false;
  bool _hovered = false;
  double _targetHeight = 0;

  void _updateTargetHeight(PointerEnterEvent event) {
    _hovered = true;
    if (!_active) return;
    _hasActivity = true;
    final box = _childKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && box.size.height != _targetHeight) {
      setState(() => _targetHeight = box.size.height);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenToTickerMode();
    _listenToRouteScope();
    _scopeActive = TooltipVisibility.of(context);
    _updateActivity();
    final size = MediaQuery.sizeOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    if (_viewportSize != null &&
        (_viewportSize != size || _textScaler != scaler)) {
      _resetTooltip();
    }
    _viewportSize = size;
    _textScaler = scaler;
  }

  @override
  void activate() {
    super.activate();
    _listenToTickerMode();
  }

  void _listenToTickerMode() {
    final tickerMode = TickerMode.getValuesNotifier(context);
    if (identical(_tickerMode, tickerMode)) return;
    _tickerMode?.removeListener(_updateActivity);
    _tickerMode = tickerMode..addListener(_updateActivity);
  }

  void _listenToRouteScope() {
    final currentRoute = _TooltipRouteScope.maybeOf(context);
    if (!identical(_currentRoute, currentRoute)) {
      _currentRoute?.removeListener(_updateRouteActivity);
      _currentRoute = currentRoute;
      currentRoute?.addListener(_updateRouteActivity);
    }
    _routeActive =
        currentRoute?.value ?? (ModalRoute.isCurrentOf(context) ?? true);
  }

  void _updateRouteActivity() {
    _routeActive = _currentRoute?.value ?? true;
    _updateActivity();
  }

  void _updateActivity() {
    final active =
        (_tickerMode?.value.enabled ?? true) && _scopeActive && _routeActive;
    if (_active == active) return;
    _active = active;
    if (!active) {
      _resetTooltip();
    } else if (!_tooltipVisible) {
      _hasActivity = _hovered;
      setState(() => _tooltipVisible = true);
    }
  }

  void _resetTooltip() {
    if (!_hasActivity) return;
    setState(() {
      _hasActivity = false;
      _tooltipVisible = false;
    });
    if (_active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _active && !_tooltipVisible) {
          _hasActivity = _hovered;
          setState(() => _tooltipVisible = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_updateActivity);
    _currentRoute?.removeListener(_updateRouteActivity);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _updateTargetHeight,
      onExit: (_) => _hovered = false,
      // 将悬停提示浮层的遍历锚点与外层的
      // MenuAnchor/OverlayPortal 分开，避免无障碍锚点被合并。
      child: Semantics(
        container: true,
        child: TooltipVisibility(
          visible: _tooltipVisible && TooltipVisibility.of(context),
          child: Tooltip(
            message: widget.message,
            waitDuration: AppTooltip.waitDuration,
            ignorePointer: true,
            onTriggered: () => _hasActivity = true,
            // Flutter 从控件中心定位，而规范的间距从控件边缘计算。
            verticalOffset:
                _targetHeight / 2 +
                (widget.verticalOffset ?? AppTooltip.defaultVerticalOffset),
            child: KeyedSubtree(key: _childKey, child: widget.child),
          ),
        ),
      ),
    );
  }
}
