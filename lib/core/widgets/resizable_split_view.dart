import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../layout/split_view_provider.dart';

/// 可复用的左右分栏组件。
///
/// 只负责布局、拖拽和宽度持久化；左右两侧展示什么内容由调用方决定。
class ResizableSplitView extends StatefulWidget {
  const ResizableSplitView({
    super.key,
    required this.leftWidget,
    required this.rightWidget,
    this.initialWidth = SplitViewProvider.defaultSplitWidth,
  });

  final Widget leftWidget;
  final Widget rightWidget;
  final double initialWidth;

  @override
  State<ResizableSplitView> createState() => _ResizableSplitViewState();
}

class _ResizableSplitViewState extends State<ResizableSplitView> {
  static const double _minLeftWidth = 100.0;
  static const double _maxLeftWidthFactor = 0.4;
  static const double _dividerVisualWidth = 0.0;
  static const double _touchTargetWidth = 5.0;

  late double _leftPanelWidth;

  @override
  void initState() {
    super.initState();
    _leftPanelWidth = widget.initialWidth;
  }

  double _maxLeftPanelWidth(double totalWidth) {
    // 窗口很窄时，40% 宽度可能小于最小宽度，这里兜底避免 clamp 的上下限反转。
    return math.max(
      _minLeftWidth,
      totalWidth * _maxLeftWidthFactor - _touchTargetWidth,
    );
  }

  double _clampWidth(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  void _handlePanUpdate(
    DragUpdateDetails details,
    double totalWidth,
    SplitViewProvider splitViewProvider,
  ) {
    setState(() {
      final maxLeftWidth = _maxLeftPanelWidth(totalWidth);
      final newWidth = _leftPanelWidth + details.delta.dx;
      _leftPanelWidth = _clampWidth(newWidth, _minLeftWidth, maxLeftWidth);

      // 拖拽结果同步给 Provider，让同类页面复用用户最近一次调整过的宽度。
      splitViewProvider.updateSplitWidth(_leftPanelWidth);
    });
  }

  @override
  Widget build(BuildContext context) {
    final splitViewProvider = Provider.of<SplitViewProvider>(
      context,
      listen: false,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final maxLeftWidth = _maxLeftPanelWidth(totalWidth);

        // 每次布局都重新限制宽度，窗口缩放后不会留下越界的旧宽度。
        _leftPanelWidth = _clampWidth(
          _leftPanelWidth,
          _minLeftWidth,
          maxLeftWidth,
        );

        final leftWidgetWidth = _leftPanelWidth;
        final rightWidgetWidth =
            totalWidth - leftWidgetWidth - _dividerVisualWidth;
        final safeLeftWidth = _clampWidth(leftWidgetWidth, 0.0, totalWidth);
        final safeRightWidth = _clampWidth(rightWidgetWidth, 0.0, totalWidth);

        return Stack(
          children: [
            Row(
              children: [
                SizedBox(width: safeLeftWidth, child: widget.leftWidget),
                const SizedBox(width: _dividerVisualWidth),
                SizedBox(width: safeRightWidth, child: widget.rightWidget),
              ],
            ),
            Positioned(
              left:
                  safeLeftWidth -
                  (_touchTargetWidth / 2) +
                  (_dividerVisualWidth / 2),
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanUpdate: (details) =>
                    _handlePanUpdate(details, totalWidth, splitViewProvider),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: _touchTargetWidth,
                    height: constraints.maxHeight,
                    color: Colors.transparent,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
