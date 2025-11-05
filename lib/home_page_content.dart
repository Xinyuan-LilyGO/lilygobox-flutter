import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'provider/theme_provider.dart';
import 'provider/home_page_provider.dart';

// 主页内容 (改为 StatefulWidget 以支持列表的 State)
class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  // 定义菜单项数据结构 (用于左侧列表)
  final List<Map<String, dynamic>> menuItems = [
    {'type': 'header', 'title': '我的'},
    {'type': 'item', 'title': '个人设置', 'key': 'settings'},
    {'type': 'item', 'title': '偏好设置', 'key': 'preferences'},
    {'type': 'divider'},
    {'type': 'header', 'title': '导航'},
    {'type': 'item', 'title': '工作区', 'key': 'workspace'},
    {'type': 'item', 'title': '文件浏览器', 'key': 'file_explorer'},
  ];

  // 默认选中的菜单项 Key
  String _selectedTitleKey = 'settings';
  // 用于存储当前悬停颜色状态的 Map
  final Map<String, Color> _currentHoverColors = {};
  // 悬停动画持续时间
  final Duration _animationDuration = const Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    // 获取主题数据 (使用 listen: true，因为左侧内容需要响应主题变化)
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    // 获取 HomePageProvider (使用 listen: false 仅用于 SplitViewTemplate 的初始化和拖动更新)
    final homePageProvider = Provider.of<HomePageProvider>(
      context,
      listen: false,
    );

    // 左侧面板的新内容
    final leftPanelContent = Container(
      color: theme.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
            child: Text(
              'Home',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textColorPrimary, // 使用 theme.textColorPrimary
              ),
            ),
          ),

          // 分割线
          Divider(color: theme.dividerColor2, height: 1, thickness: 2),

          // 滚动菜单列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 5.0), // 顶部留出空间
              itemCount: menuItems.length,
              itemBuilder: (context, index) {
                final item = menuItems[index];

                if (item['type'] == 'divider') {
                  // 横线分类设置
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 15.0,
                    ),
                    child: Divider(color: theme.dividerColor, height: 1),
                  );
                }

                if (item['type'] == 'header') {
                  // 分类标题
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(15.0, 10.0, 10.0, 5.0),
                    child: Text(
                      item['title'], // 本地化的标题
                      style: TextStyle(
                        color: theme.textColorTertiary, // 浅色字体
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }

                // 设置项 (type: 'item')
                final title = item['title'] as String;
                final key = item['key'] as String; // 菜单项的固定 key
                final isSelected = key == _selectedTitleKey; // 使用 key 来判断是否选中

                // 计算目标背景色
                final targetColor = isSelected
                    ? theme.primaryTextSelectedColor
                    : _currentHoverColors[key] ??
                          Colors.transparent; // 使用 key 访问 hover 颜色

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15.0,
                    vertical: 2.0, // 保持外部垂直边距一致
                  ),
                  // 使用 TweenAnimationBuilder 实现颜色渐变
                  child: TweenAnimationBuilder<Color?>(
                    duration: _animationDuration, // 渐变时间
                    tween: ColorTween(
                      begin: Colors.transparent,
                      end: targetColor, // 渐变的目标颜色
                    ),
                    builder: (context, color, child) {
                      // 使用 SizedBox 强制列表项高度固定
                      return SizedBox(
                        height: 30.0,
                        child: InkWell(
                          // onHover 实现鼠标悬停/离开效果
                          onHover: (isHovering) {
                            // 只有未选中项才响应悬停
                            if (!isSelected) {
                              setState(() {
                                // 更新 Map 中的悬停目标颜色，使用 key
                                _currentHoverColors[key] = isHovering
                                    ? theme.primaryTextHoverColor
                                    : Colors.transparent;
                              });
                            }
                          },

                          // 使用 InkWell 实现点击效果
                          onTap: () {
                            // 点击时重置所有 hover 颜色，并切换选中项
                            setState(() {
                              _selectedTitleKey = key; // 切换选中的 key
                              // 重置所有项的悬停颜色为透明，因为点击操作已经完成
                              _currentHoverColors.updateAll(
                                (k, value) => Colors.transparent,
                              );
                            });
                          },
                          borderRadius: BorderRadius.circular(6.0),
                          child: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10.0,
                              vertical: 0.0,
                            ),
                            decoration: BoxDecoration(
                              // 使用 TweenAnimationBuilder 返回的 color
                              color: color,
                              borderRadius: BorderRadius.circular(6.0),
                            ),
                            child: Text(
                              title, // 本地化的标题
                              style: TextStyle(
                                // 字体颜色保持不变，只有背景色变化
                                color: theme.textColorSecondary,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    // 右侧面板的新内容
    final rightPanelContent = Container(
      color: theme.tertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
            child: Text(
              '标题',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textColorPrimary, // 使用 theme.textColorPrimary
              ),
            ),
          ),

          // 分割线
          // Divider(color: theme.dividerColor2, height: 1, thickness: 2),
        ],
      ),
    );

    // 使用 ClipRRect 确保 SplitViewTemplate 遵循外部 Container 的圆角
    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
      // 使用自定义的可拖动分界线视图
      child: SplitViewTemplate(
        leftColor: theme.secondary,
        rightColor: theme.tertiary,
        // 左边内容使用新的 Column 布局
        leftWidget: leftPanelContent,
        // 右边内容保持不变
        rightWidget: Container(color: theme.tertiary, child: rightPanelContent),
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
            totalWidth - leftWidgetWidth - _dividerVisualWidth;

        // 确保左右宽度都是有效的（非负）
        final double safeLeftWidth = leftWidgetWidth.clamp(0.0, totalWidth);
        final double safeRightWidth = rightWidgetWidth.clamp(0.0, totalWidth);

        return Stack(
          // 使用 Stack 来叠加拖动热区
          children: <Widget>[
            // 底层：Row 布局，紧密排列左侧、视觉分割线和右侧
            Row(
              children: <Widget>[
                // 左侧面板 (使用绝对宽度)
                SizedBox(width: safeLeftWidth, child: widget.leftWidget),

                // 视觉分割线：一个独立的、可见的 Container
                Container(
                  width: _dividerVisualWidth,
                  height: constraints.maxHeight,
                  color: Colors.white, // 可以使用一个主题色，并调整透明度
                ),

                // 右侧面板 (使用计算出的剩余宽度)
                SizedBox(width: safeRightWidth, child: widget.rightWidget),
              ],
            ),

            // 顶层：定位的 GestureDetector 拖动热区
            Positioned(
              left:
                  safeLeftWidth -
                  (_touchTargetWidth / 2) +
                  (_dividerVisualWidth / 2), // 精确计算定位
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent, // 确保透明区域也能接收事件
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: _touchTargetWidth,
                    height: constraints.maxHeight,
                    color: Colors.transparent, // 必须透明，但占据空间
                  ),
                ),
                onPanUpdate: (details) =>
                    _handlePanUpdate(details, totalWidth, homePageProvider),
              ),
            ),
          ],
        );
      },
    );
  }
}
