import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
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
            highlightColor: theme.sidebarIconHighlightColor,
            splashColor: theme.sidebarIconSplashColor,
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
                  highlightColor: theme.sidebarIconHighlightColor,
                  splashColor: theme.sidebarIconSplashColor,
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
  final Color hoverColor;
  final bool disableHoverEffect;
  final Color indicatorColor;

  @override
  State<SidebarButtonTemplate> createState() => _SidebarButtonTemplateState();
}

class _SidebarButtonTemplateState extends State<SidebarButtonTemplate>
    with TickerProviderStateMixin {
  // 更改为 TickerProviderStateMixin 支持多个控制器

  // 1. 悬停/选中 (按钮主体) 控制器
  late AnimationController _buttonAnimationController;
  late Animation<double> _borderRadiusAnimation;
  late Animation<Color?> _selectColorAnimation;
  late Animation<Color?> _hoverColorAnimation;

  // 2. 指示器 (圆点/长条) 专用控制器
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

    // 初始化按钮主体动画控制器 (用于悬停和选中时的圆角/背景色)
    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // 初始化指示器动画控制器 (只用于选中时的圆点/长条动画)
    _indicatorAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _updateAnimations();

    // 确保初始选中状态正确设置控制器值
    if (widget.isSelected) {
      _buttonAnimationController.value = 1.0;
      _indicatorAnimationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SidebarButtonTemplate oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selectedColor != widget.selectedColor ||
        oldWidget.iconBackgroundColor != widget.iconBackgroundColor ||
        oldWidget.selectedBorderRadius != widget.selectedBorderRadius ||
        oldWidget.hoverColor != widget.hoverColor ||
        oldWidget.disableHoverEffect != widget.disableHoverEffect) {
      _updateAnimations();
    }

    // 处理选中状态的变化 (驱动两个控制器)
    if (oldWidget.isSelected != widget.isSelected) {
      if (widget.isSelected) {
        // 选中: 两个动画向前
        _buttonAnimationController.forward();
        _indicatorAnimationController.forward();
      } else {
        // 取消选中: 两个动画反转
        _buttonAnimationController.reverse();
        _indicatorAnimationController.reverse();
      }
    }
  }

  void _updateAnimations() {
    final double endRadius = widget.disableHoverEffect
        ? fullCircleRadius
        : widget.selectedBorderRadius;

    // 按钮主体动画
    // 按钮圆角动画
    _borderRadiusAnimation =
        Tween<double>(begin: fullCircleRadius, end: endRadius).animate(
          CurvedAnimation(
            parent: _buttonAnimationController,
            curve: Curves.easeInOut,
          ),
        );

    // 按钮背景色动画 (选中)
    _selectColorAnimation =
        ColorTween(
          begin: widget.iconBackgroundColor,
          end: widget.selectedColor,
        ).animate(
          CurvedAnimation(
            parent: _buttonAnimationController,
            curve: Curves.easeInOut,
          ),
        );

    // 按钮背景色动画 (悬停)
    _hoverColorAnimation =
        ColorTween(
          begin: widget.iconBackgroundColor,
          end: widget.hoverColor,
        ).animate(
          CurvedAnimation(
            parent: _buttonAnimationController,
            curve: Curves.easeInOut,
          ),
        );

    // 指示器动画
    // 指示器高度动画
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

    // 指示器半径动画
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

  // 鼠标悬停时只驱动按钮主体动画控制器
  void _handleHover(bool isHovered) {
    if (widget.isSelected) return; // 选中时不响应悬停

    if (isHovered) {
      if (widget.disableHoverEffect) return;
      // 悬停时：只驱动按钮主体动画
      _buttonAnimationController.forward();
    } else {
      // 离开时：只驱动按钮主体动画反转
      _buttonAnimationController.reverse();
    }
  }

  @override
  void dispose() {
    _buttonAnimationController.dispose();
    _indicatorAnimationController.dispose(); // 释放新控制器
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
            // 指示器 (小白点/侧边线) - 浮动在最左侧
            Positioned(
              left: indicatorLeftOffset,
              child: AnimatedBuilder(
                // 使用指示器专用控制器
                animation: _indicatorAnimationController,
                builder: (context, child) {
                  final double currentIndicatorHeight =
                      _indicatorHeightAnimation.value;
                  final double currentBorderRadius =
                      _indicatorRadiusAnimation.value;

                  // 禁用悬停效果的按钮 (如“添加”)，在未选中且动画静止时隐藏
                  if (widget.disableHoverEffect &&
                      _indicatorAnimationController.value < 0.01) {
                    return const SizedBox.shrink();
                  }

                  return Container(
                    width: indicatorMaxWidth, // 始终为 5.0
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
                // 使用按钮主体控制器
                animation: _buttonAnimationController,
                builder: (context, child) {
                  final double currentRadius = _borderRadiusAnimation.value;

                  final Color? buttonColor;
                  if (widget.isSelected) {
                    // 选中时，使用选中颜色动画
                    buttonColor = _selectColorAnimation.value;
                  } else {
                    // 未选中时，使用悬停颜色动画
                    buttonColor = _hoverColorAnimation.value;
                  }

                  return Material(
                    color: buttonColor,
                    borderRadius: BorderRadius.circular(currentRadius),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(currentRadius),
                      onTap: widget.onPressed,
                      highlightColor: widget.highlightColor,
                      splashColor: widget.splashColor,
                      child: Center(
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
}

// 主页内容
class HomePageContent extends StatelessWidget {
  const HomePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '欢迎来到主页！ (Selected Index: 0)',
        style: TextStyle(fontSize: 24, color: Colors.white),
      ),
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
