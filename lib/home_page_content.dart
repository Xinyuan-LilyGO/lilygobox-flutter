import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme.dart';
import 'home_page.dart';

// 主页内容
class HomePageContent extends StatelessWidget {
  const HomePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    // 获取主题数据
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    final homePageProvider = Provider.of<HomePageProvider>(
      context,
      listen: false,
    );

    // 使用 ClipRRect 确保 SplitViewTemplate 遵循外部 Container 的圆角
    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
      // 使用自定义的可拖动分界线视图
      child: SplitViewTemplate(
        leftColor: theme.secondary,
        rightColor: theme.tertiary,
        // 左边内容
        leftWidget: Container(
          color: theme.secondary,
          child: const Center(
            child: Text(
              '主页 - 左侧面板 (theme.secondary)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, color: Colors.white),
            ),
          ),
        ),
        // 右边内容
        rightWidget: Container(
          color: theme.tertiary,
          child: const Center(
            child: Text(
              '主页 - 右侧面板 (theme.tertiary)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, color: Colors.white),
            ),
          ),
        ),
        initialWidth: homePageProvider.splitWidth,
      ),
    );
  }
}

// 可拖动的分界线组件 (保持不变)
class SplitViewTemplate extends StatefulWidget {
  const SplitViewTemplate({
    super.key,
    required this.leftWidget,
    required this.rightWidget,
    required this.leftColor,
    required this.rightColor,

    this.initialWidth = 300.0,
  });

  final Widget leftWidget;
  final Widget rightWidget;
  final Color leftColor;
  final Color rightColor;
  final double initialWidth; // 初始左侧面板的绝对宽度

  @override
  State<SplitViewTemplate> createState() => _SplitViewTemplateState();
}

class _SplitViewTemplateState extends State<SplitViewTemplate> {
  // 存储左侧面板的绝对宽度
  late double _leftPanelWidth;

  // 左侧面板的宽度限制
  static const double _minLeftWidth = 100.0;
  static const double _maxLeftWidthFactor = 0.4; // 左侧最大总宽度的百分比

  // 视觉和触摸常量
  static const double _dividerVisualWidth = 0.0;
  static const double _touchTargetWidth = 5.0;

  @override
  void initState() {
    super.initState();
    _leftPanelWidth = widget.initialWidth;
  }

  // 处理拖动更新
  void _handlePanUpdate(
    DragUpdateDetails details,
    double totalWidth,
    HomePageProvider homePageProvider,
  ) {
    setState(() {
      double newWidth = _leftPanelWidth + details.delta.dx;

      // 在拖动时也需要限制，以防止拖动到无效区域
      final double maxLeftWidth =
          totalWidth * _maxLeftWidthFactor - _touchTargetWidth;

      _leftPanelWidth = newWidth.clamp(_minLeftWidth, maxLeftWidth);

      // 更新状态管理中的宽度值
      homePageProvider.updateSplitWidth(_leftPanelWidth);
    });
  }

  @override
  Widget build(BuildContext context) {
    final homePageProvider = Provider.of<HomePageProvider>(
      context,
      listen: false,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double totalWidth = constraints.maxWidth;

        // 计算最大允许的左侧宽度（考虑总宽度变化）
        final double maxLeftWidth =
            totalWidth * _maxLeftWidthFactor - _touchTargetWidth;

        // 在布局时校正 _leftPanelWidth
        // 这会在窗口大小改变（LayoutBuilder重建）时，自动调整 _leftPanelWidth
        // 如果当前宽度超过了新窗口的最大限制，则将其缩小到最大限制
        // 使用 setState/didUpdateWidget 无法实现，因为 LayoutBuilder 自身不会触发这些生命周期函数
        // 必须在 build 内部直接修正值
        _leftPanelWidth = _leftPanelWidth.clamp(_minLeftWidth, maxLeftWidth);

        // 宽度计算
        final double leftWidgetWidth = _leftPanelWidth;
        final double rightWidgetWidth =
            totalWidth - leftWidgetWidth - _touchTargetWidth;

        // 确保左右宽度都是有效的（非负）
        final double safeLeftWidth = leftWidgetWidth.clamp(0.0, totalWidth);
        final double safeRightWidth = rightWidgetWidth.clamp(0.0, totalWidth);

        return Row(
          children: <Widget>[
            // 左侧面板 (使用绝对宽度)
            SizedBox(width: safeLeftWidth, child: widget.leftWidget),

            // 可拖动的分界线
            GestureDetector(
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: Container(
                  width: _touchTargetWidth,
                  height: constraints.maxHeight,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: _dividerVisualWidth,
                      height: constraints.maxHeight,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
              onPanUpdate: (details) =>
                  _handlePanUpdate(details, totalWidth, homePageProvider),
            ),

            // 右侧面板 (使用计算出的剩余宽度)
            SizedBox(width: safeRightWidth, child: widget.rightWidget),
          ],
        );
      },
    );
  }
}
