import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart'; // 假设你有一个 theme.dart 文件

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
    // 假设 ThemeProvider 存在且提供 themeData
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

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
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 主内容区域
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftSidebar(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    // 板子图标列表
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

    // 侧边栏容器，宽度为 65
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
          ),

                    //间距
          const SizedBox(height: 5),

          // 分隔线
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: theme.dividerColor?.withOpacity(0.3) ?? Colors.grey.shade600,
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
                );
              },
            ),
          ),

          // 添加板子按钮 - 永远不选中
          SidebarButtonTemplate(
            icon: Symbols.add,
            onPressed: () {
              // 这里的 print 应该会在控制台输出
              print('点击了添加板子按钮');
              // 实际应用中可以弹出一个对话框
            },
            iconColor: theme.sidebarIconColor,
            iconBackgroundColor: theme.sidebarIconBackgroundColor,
            highlightColor: theme.sidebarIconHighlightColor,
            splashColor: theme.sidebarIconSplashColor,
            isSelected: false,
            selectedColor: theme.sidebarSelectedIconColor,
            disableHoverEffect: true,
            hoverColor: theme.sidebarHoverIconColor,
          ),

          //间距
          const SizedBox(height: 10),
        ],
      ),
    );
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

  @override
  State<SidebarButtonTemplate> createState() => _SidebarButtonTemplateState();
}

class _SidebarButtonTemplateState extends State<SidebarButtonTemplate>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _borderRadiusAnimation;
  late Animation<Color?> _selectColorAnimation;
  late Animation<Color?> _hoverColorAnimation;

  // 指示器动画
  late Animation<double> _indicatorHeightAnimation;
  late Animation<double> _indicatorRadiusAnimation;

  static const double buttonSize = 45.0;
  static const double fullCircleRadius = buttonSize / 2;

  // 指示器尺寸常量
  static const double indicatorMaxWidth = 5.0; // 侧边线宽度
  // 核心优化 1：将小白点的直径改为 5.0，与侧边线宽度一致，解决不对齐的视觉问题
  static const double indicatorMinDiameter = 5.0;
  static const double indicatorMaxHeight = buttonSize - 2 * 5.0; // 侧边线高度 (35.0)

  // 核心优化 2：指示器负偏移，保持紧贴左侧边缘（半隐藏）
  static const double indicatorLeftOffset = -1.5;

  // 核心优化 3：定义按钮主体向右偏移的距离
  static const double buttonLeftOffset = 10.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200), // 动画时间
      vsync: this,
    );

    _updateAnimations();

    if (widget.isSelected) {
      _animationController.value = 1.0;
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

    // 处理选中状态的变化
    if (oldWidget.isSelected != widget.isSelected) {
      if (widget.isSelected) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  void _updateAnimations() {
    final double endRadius = widget.disableHoverEffect
        ? fullCircleRadius
        : widget.selectedBorderRadius;

    _borderRadiusAnimation =
        Tween<double>(begin: fullCircleRadius, end: endRadius).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    final Color hoverTargetColor = widget.hoverColor;

    _hoverColorAnimation =
        ColorTween(
          begin: widget.iconBackgroundColor,
          end: hoverTargetColor,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    _selectColorAnimation =
        ColorTween(
          begin: widget.iconBackgroundColor,
          end: widget.selectedColor,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    _indicatorHeightAnimation =
        Tween<double>(
          begin: indicatorMinDiameter, // 5.0
          end: indicatorMaxHeight, // 35.0
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    // 核心优化 4：起始半径为 2.5
    _indicatorRadiusAnimation =
        Tween<double>(
          begin: indicatorMinDiameter / 2,
          end: indicatorMaxWidth / 2, // 2.5
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );
  }

  void _handleHover(bool isHovered) {
    if (widget.isSelected) return;

    if (isHovered) {
      // 禁用悬停效果的按钮不执行 forward
      if (widget.disableHoverEffect) return;
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 整个父级 Container 仍然保持 65 宽度
    return MouseRegion(
      onEnter: (_) => _handleHover(true),
      onExit: (_) => _handleHover(false),
      cursor: SystemMouseCursors.click,
      // **重要：移除 GestureDetector，恢复 InkWell 的 onTap**
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        width: 65,
        height: buttonSize, // 45.0
        child: Stack(
          // **重要：使用左对齐**
          alignment: Alignment.centerLeft,
          children: [
            // 1. 指示器 (小白点/侧边线) - 浮动在最左侧
            Positioned(
              // *** 负偏移，使其紧贴左侧边缘（半隐藏） ***
              left: indicatorLeftOffset,
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  final bool isHovered =
                      _animationController.status != AnimationStatus.dismissed;
                  Color indicatorColor = widget.selectedColor;

                  // 只有在选中或悬停时才显示
                  if (!widget.isSelected && !isHovered) {
                    return const SizedBox.shrink(); // 隐藏指示器
                  }

                  // 禁用悬停效果的按钮，如果未选中，也不显示指示器
                  if (!widget.isSelected && widget.disableHoverEffect) {
                    return const SizedBox.shrink(); // 隐藏指示器
                  }

                  double currentIndicatorHeight;
                  double currentIndicatorWidth;
                  double currentBorderRadius;

                  if (widget.isSelected) {
                    // 选中状态：从圆点动画到侧边线
                    currentIndicatorHeight = _indicatorHeightAnimation.value;
                    currentIndicatorWidth = indicatorMaxWidth; // 5.0
                    currentBorderRadius = _indicatorRadiusAnimation.value;
                  } else {
                    // 未选中但悬停状态：固定为 5.0x5.0 圆点
                    currentIndicatorHeight = indicatorMinDiameter; // 5.0
                    currentIndicatorWidth = indicatorMaxWidth; // 5.0
                    currentBorderRadius = indicatorMaxWidth / 2; // 2.5
                  }

                  return Container(
                    width: currentIndicatorWidth,
                    height: currentIndicatorHeight,
                    decoration: BoxDecoration(
                      color: indicatorColor,
                      borderRadius: BorderRadius.circular(currentBorderRadius),
                    ),
                  );
                },
              ),
            ),

            // 2. 按钮本体 - 向右偏移
            Container(
              width: buttonSize, // 45.0
              height: buttonSize, // 45.0
              // *** 使用左侧边距将按钮向右推开，与指示器分离 ***
              margin: const EdgeInsets.only(left: buttonLeftOffset),
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  final double currentRadius = _borderRadiusAnimation.value;

                  final Color? buttonColor;
                  if (widget.isSelected) {
                    buttonColor = _selectColorAnimation.value;
                  } else {
                    buttonColor = _hoverColorAnimation.value;
                  }

                  return Material(
                    color: buttonColor,
                    borderRadius: BorderRadius.circular(currentRadius),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(currentRadius),
                      // **核心修复：恢复 onTap**
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
