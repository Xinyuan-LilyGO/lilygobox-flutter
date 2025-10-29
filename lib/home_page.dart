import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 0: home, 1-10: boards, -1: add button (never selected)
  int _selectedIndex = 0;

  void _selectItem(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

    // 为了让 Expanded 工作，外部需要一个 Row 或 Column
    // 假设这个 HomePage 是某个更大的 Widget 的 child
    return Expanded(
      child: Row(
        children: [
          // 左边侧边栏
          _buildLeftSidebar(context),

          // 右边主内容区域
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.secondary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                ),
              ),
              child: _buildCurrentPage(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftSidebar(BuildContext context) {
    // 使用 listen: false 因为只需要获取主题数据，不需要在主题变化时重建侧边栏
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    final boardSymbols = [
      Symbols.chat,
      Symbols.people,
      Symbols.music_note,
      Symbols.games,
      Symbols.code,
      Symbols.photo_camera,
      Symbols.videogame_asset,
      Symbols.sports_esports,
      Symbols.movie,
      Symbols.science,
    ];

    return Container(
      width: 65,
      color: theme.primary,
      child: Column(
        children: [
          // 房子按钮
          SidebarButtonTemplate(
            icon: Symbols.home,
            onPressed: () {
              _selectItem(0);
            },
            iconColor: theme.sidebarIconColor,
            iconBackgroundColor: theme.sidebarIconBackgroundColor,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            isSelected: _selectedIndex == 0,
            selectedColor: theme.sidebarSelectedIconColor,
            hoverColor: theme.sidebarHoverIconColor,
            indicatorColor: theme.sidebarIndicatorColor,
          ),

          //间距
          const SizedBox(height: 5),

          // 分隔线
          Container(
            height: 1.5,
            margin: const EdgeInsets.symmetric(horizontal: 15),
            color: theme.dividerColor,
          ),

          //间距
          const SizedBox(height: 10),

          // 可滚动的板子列表
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: boardSymbols.length,
              itemBuilder: (context, index) {
                final boardIndex = index + 1;
                return SidebarButtonTemplate(
                  icon: boardSymbols[index],
                  onPressed: () {
                    _selectItem(boardIndex);
                  },
                  iconColor: theme.sidebarIconColor,
                  iconBackgroundColor: theme.sidebarIconBackgroundColor,
                  highlightColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  isSelected: _selectedIndex == boardIndex,
                  selectedColor: theme.sidebarSelectedIconColor,
                  hoverColor: theme.sidebarHoverIconColor,
                  indicatorColor: theme.sidebarIndicatorColor,
                );
              },
            ),
          ),

          // 添加板子按钮 - 永远不选中
          SidebarButtonTemplate(
            icon: Symbols.add,
            onPressed: () {
              print('点击了添加板子按钮');
            },
            iconColor: theme.sidebarIconColor,
            iconBackgroundColor: theme.sidebarIconBackgroundColor,
            highlightColor: theme.sidebarIconHighlightColor,
            splashColor: theme.sidebarIconSplashColor,
            isSelected: false,
            selectedColor: theme.sidebarSelectedIconColor,
            disableHoverEffect: true,
            hoverColor: theme.sidebarHoverIconColor,
            indicatorColor: theme.sidebarIndicatorColor,
          ),

          //间距
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildCurrentPage(BuildContext context) {
    // 0 是主页
    if (_selectedIndex == 0) {
      return const HomePageContent();
    }
    // 1 到 10 是板子页
    else if (_selectedIndex >= 1 && _selectedIndex <= 10) {
      // 传递板子的索引
      return BoardPageContent(boardIndex: _selectedIndex);
    }
    // 其他值（如 -1 或超出范围）
    else {
      return const Center(child: Text('页面未找到'));
    }
  }
}

class SidebarButtonTemplate extends StatefulWidget {
  const SidebarButtonTemplate({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.highlightColor,
    required this.splashColor,
    required this.selectedColor,
    required this.indicatorColor,
    this.isSelected = false,
    this.selectedBorderRadius = 15.0,
    this.hoverColor = Colors.grey,
    this.disableHoverEffect = false,
    this.iconSize = 24,
    this.iconWeight = 600.0,
    this.grade = -25.0,
    this.opticalSize = 48.0,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final double iconWeight;
  final double grade;
  final double opticalSize;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Color highlightColor;
  final Color splashColor;
  final bool isSelected;
  final Color selectedColor;
  final double selectedBorderRadius;
  final Color hoverColor; // 悬停颜色，现在将作为内发光的颜色
  final bool disableHoverEffect;
  final Color indicatorColor;

  @override
  State<SidebarButtonTemplate> createState() => _SidebarButtonTemplateState();
}

class _SidebarButtonTemplateState extends State<SidebarButtonTemplate>
    with TickerProviderStateMixin {
  // 1. 选中 (按钮主体) 控制器
  late AnimationController _selectAnimationController;
  late Animation<double> _borderRadiusAnimation;
  late Animation<Color?> _selectColorAnimation;

  // 新增：悬停状态 (取代悬停颜色控制器)
  bool _isHovered = false;

  // 3. 指示器 (圆点/长条) 专用控制器
  late AnimationController _indicatorAnimationController;
  late Animation<double> _indicatorHeightAnimation;
  late Animation<double> _indicatorRadiusAnimation;

  static const double buttonSize = 45.0;
  static const double fullCircleRadius = buttonSize / 2;

  // 指示器尺寸常量
  static const double indicatorMaxWidth = 7.0; // 侧边线宽度
  static const double indicatorMinDiameter = 7.0; // 小白点直径
  static const double indicatorMaxHeight = buttonSize - 2 * 5.0; // 侧边线高度 (35.0)

  // 指示器负偏移，保持紧贴左侧边缘（半隐藏）
  static const double indicatorLeftOffset = -2.8;

  // 定义按钮主体向右偏移的距离
  static const double buttonLeftOffset = 10.0;

  @override
  void initState() {
    super.initState();

    // 1. 选中动画控制器 (用于圆角和选中背景色)
    _selectAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // 3. 指示器动画控制器 (用于选中指示器)
    _indicatorAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _updateAnimations();

    // 确保初始选中状态正确设置控制器值
    if (widget.isSelected) {
      _selectAnimationController.value = 1.0;
      _indicatorAnimationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SidebarButtonTemplate oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selectedColor != widget.selectedColor ||
        oldWidget.iconBackgroundColor != widget.iconBackgroundColor ||
        oldWidget.selectedBorderRadius != widget.selectedBorderRadius ||
        oldWidget.indicatorColor != widget.indicatorColor) {
      _updateAnimations();
    }

    // 处理选中状态的变化 (驱动选中控制器和指示器控制器)
    if (oldWidget.isSelected != widget.isSelected) {
      if (widget.isSelected) {
        // 选中: 两个动画向前
        _selectAnimationController.forward();
        _indicatorAnimationController.forward();
        // 选中时取消悬停状态，确保内发光消失
        setState(() {
          _isHovered = false;
        });
      } else {
        // 取消选中: 两个动画反转
        _selectAnimationController.reverse();
        _indicatorAnimationController.reverse();
      }
    }
  }

  void _updateAnimations() {
    // 选中/圆角动画
    _borderRadiusAnimation =
        Tween<double>(
          begin: fullCircleRadius,
          end: widget.selectedBorderRadius,
        ).animate(
          CurvedAnimation(
            parent: _selectAnimationController,
            curve: Curves.easeInOut,
          ),
        );

    // 选中背景色动画
    _selectColorAnimation =
        ColorTween(
          begin: widget.iconBackgroundColor,
          end: widget.selectedColor,
        ).animate(
          CurvedAnimation(
            parent: _selectAnimationController,
            curve: Curves.easeInOut,
          ),
        );

    // 指示器动画
    _indicatorHeightAnimation =
        Tween<double>(
          begin: indicatorMinDiameter,
          end: indicatorMaxHeight,
        ).animate(
          CurvedAnimation(
            parent: _indicatorAnimationController,
            curve: Curves.easeInOut,
          ),
        );

    _indicatorRadiusAnimation =
        Tween<double>(
          begin: indicatorMinDiameter / 2,
          end: indicatorMaxWidth / 2,
        ).animate(
          CurvedAnimation(
            parent: _indicatorAnimationController,
            curve: Curves.easeInOut,
          ),
        );
  }

  // 鼠标悬停时只更新 _isHovered 状态
  void _handleHover(bool isHovered) {
    if (widget.isSelected) return; // 选中时不响应悬停

    // 只有在非选中且未禁用悬停效果时才更新状态
    if (!widget.isSelected && !widget.disableHoverEffect) {
      setState(() {
        _isHovered = isHovered;
      });
    }
  }

  @override
  void dispose() {
    _selectAnimationController.dispose();
    _indicatorAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _handleHover(true),
      onExit: (_) => _handleHover(false),
      cursor: SystemMouseCursors.click,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        width: 65,
        height: buttonSize, // 45.0
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // 指示器 (小白点/侧边线) - 保持不变
            Positioned(
              left: indicatorLeftOffset,
              child: AnimatedBuilder(
                animation: _indicatorAnimationController,
                builder: (context, child) {
                  final double currentIndicatorHeight =
                      _indicatorHeightAnimation.value;
                  final double currentBorderRadius =
                      _indicatorRadiusAnimation.value;

                  if (widget.disableHoverEffect &&
                      _indicatorAnimationController.value < 0.01) {
                    return const SizedBox.shrink();
                  }

                  return Container(
                    width: indicatorMaxWidth,
                    height: currentIndicatorHeight,
                    decoration: BoxDecoration(
                      color: widget.indicatorColor,
                      borderRadius: BorderRadius.circular(currentBorderRadius),
                    ),
                  );
                },
              ),
            ),

            // 按钮本体 - 向右偏移
            Container(
              width: buttonSize, // 45.0
              height: buttonSize, // 45.0
              margin: const EdgeInsets.only(left: buttonLeftOffset),
              child: AnimatedBuilder(
                animation: _selectAnimationController,
                builder: (context, child) {
                  final double currentRadius = _borderRadiusAnimation.value;
                  final Color? buttonColor = widget.isSelected
                      ? _selectColorAnimation.value
                      : widget.iconBackgroundColor;

                  // 使用 ClipRRect 裁剪按钮的所有子元素，包括内发光层
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(currentRadius),
                    child: Material(
                      color: buttonColor,
                      // Material 上的 borderRadius 被 ClipRRect 取代，但为了 InkWell 仍然需要
                      borderRadius: BorderRadius.circular(currentRadius),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(currentRadius),
                        onTap: widget.onPressed,
                        highlightColor: widget.highlightColor,
                        splashColor: widget.splashColor,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 1. 内发光层 (新的悬停效果) - 现在被 ClipRRect 裁剪
                            if (!widget.isSelected)
                              AnimatedOpacity(
                                opacity: _isHovered ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: Container(
                                  width: buttonSize,
                                  height: buttonSize,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      currentRadius,
                                    ),
                                    boxShadow: _buildBoxShadow(),
                                  ),
                                ),
                              ),

                            // 2. 图标本体 (覆盖在发光层之上)
                            Center(
                              child: Icon(
                                widget.icon,
                                size: widget.iconSize,
                                color: widget.iconColor,
                                weight: widget.iconWeight,
                                grade: widget.grade,
                                opticalSize: widget.opticalSize,
                                fill: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  //按钮悬停发光阴影
  // 专门的柔和阴影构建方法
  List<BoxShadow> _buildBoxShadow() {
    return [
      BoxShadow(
        color: widget.hoverColor.withValues(alpha: 0.5), // 阴影颜色和透明度：黑色，50%透明度
        blurRadius: 17, // 模糊半径：阴影边缘模糊程度，值越大越模糊
        spreadRadius: -15, // 扩散半径：负值让阴影向内收缩，消除硬边
      ),
      BoxShadow(
        color: widget.hoverColor.withValues(alpha: 0.3),
        blurRadius: 15,
        spreadRadius: -13,
      ),
      BoxShadow(
        color: widget.hoverColor.withValues(alpha: 0.2),
        blurRadius: 14,
        spreadRadius: -12,
      ),
      BoxShadow(
        color: widget.hoverColor.withValues(alpha: 0.2),
        blurRadius: 13,
        spreadRadius: -11,
      ),
      BoxShadow(
        color: widget.hoverColor.withValues(alpha: 0.2),
        blurRadius: 12,
        spreadRadius: -10,
      ),
    ];
  }
}

// 主页内容
class HomePageContent extends StatelessWidget {
  const HomePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    // 获取主题数据
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

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
      ),
    );
  }
}

// 可拖动的分界线组件
class SplitViewTemplate extends StatefulWidget {
  const SplitViewTemplate({
    super.key,
    required this.leftWidget,
    required this.rightWidget,
    required this.leftColor,
    required this.rightColor,
    // 将 initialRatio 更改为 initialWidth，以反映其新用途
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
  void _handlePanUpdate(DragUpdateDetails details, double totalWidth) {
    setState(() {
      double newWidth = _leftPanelWidth + details.delta.dx;

      // 在拖动时也需要限制，以防止拖动到无效区域
      final double maxLeftWidth =
          totalWidth * _maxLeftWidthFactor - _touchTargetWidth;

      _leftPanelWidth = newWidth.clamp(_minLeftWidth, maxLeftWidth);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double totalWidth = constraints.maxWidth;

        // 1. 计算最大允许的左侧宽度（考虑总宽度变化）
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
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
              onPanUpdate: (details) => _handlePanUpdate(details, totalWidth),
            ),

            // 右侧面板 (使用计算出的剩余宽度)
            SizedBox(width: safeRightWidth, child: widget.rightWidget),
          ],
        );
      },
    );
  }
}

// 板子内容
class BoardPageContent extends StatelessWidget {
  final int boardIndex;
  const BoardPageContent({super.key, required this.boardIndex});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '这是 板子 $boardIndex 的内容 (Selected Index: $boardIndex)',
        style: const TextStyle(fontSize: 24, color: Colors.white),
      ),
    );
  }
}
