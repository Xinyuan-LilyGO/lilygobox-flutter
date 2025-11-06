import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'provider/theme_provider.dart';
import 'provider/window_provider.dart';

import 'home_page_content.dart';

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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: _buildCurrentPage(context),
              ),
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
    final windowProvider = Provider.of<WindowProvider>(context, listen: false);

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
                  isSelected: _selectedIndex == boardIndex,
                  selectedColor: theme.sidebarSelectedIconColor,
                  hoverColor: theme.sidebarHoverIconColor,
                  indicatorColor: theme.sidebarIndicatorColor,
                  showDotIndicator: true, // 板子按钮显示小白点
                );
              },
            ),
          ),

          // 添加板子按钮,
          SidebarButtonTemplate(
            icon: Symbols.add,
            onPressed: () {
              windowProvider.setPage(WindowPage.addBoard);
            },
            iconColor: theme.sidebarIconColor,
            iconBackgroundColor: theme.sidebarIconBackgroundColor,
            isSelected: false,
            selectedColor: theme.sidebarSelectedIconColor,
            hoverColor: theme.sidebarHoverIconColor2,
            indicatorColor: theme.sidebarIndicatorColor,
            isAddButton: true,
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
      // 为每个页面的根 Widget 添加 Key
      return const HomePageContent(key: ValueKey<int>(0));
    }
    // 1 到 10 是板子页
    else if (_selectedIndex >= 1 && _selectedIndex <= 10) {
      // 传递板子的索引
      // 为每个页面的根 Widget 添加 Key，使用 _selectedIndex 作为 ValueKey 的值
      return BoardPageContent(
        key: ValueKey<int>(_selectedIndex),
        boardIndex: _selectedIndex,
      );
    }
    // 其他值（如 -1 或超出范围）
    else {
      // 为默认页面添加 Key
      return const Center(key: ValueKey<int>(-1), child: Text('页面未找到'));
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
    this.isAddButton = false,
    this.showDotIndicator = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final double iconWeight;
  final double grade;
  final double opticalSize;
  final Color iconColor;
  final Color iconBackgroundColor;
  final bool isSelected;
  final Color selectedColor;
  final double selectedBorderRadius;
  final Color hoverColor;
  final bool disableHoverEffect;
  final Color indicatorColor;
  final bool isAddButton;
  final bool showDotIndicator;

  @override
  State<SidebarButtonTemplate> createState() => _SidebarButtonTemplateState();
}

class _SidebarButtonTemplateState extends State<SidebarButtonTemplate>
    with TickerProviderStateMixin {
  // 1. 选中 (按钮主体) 控制器
  late AnimationController _selectAnimationController;
  late Animation<double> _borderRadiusAnimation;
  late Animation<Color?> _selectColorAnimation;

  // 新增：悬停状态
  bool _isHovered = false;

  // 3. 指示器 (圆点/长条) 专用控制器
  late AnimationController _indicatorAnimationController;
  late Animation<double> _indicatorHeightAnimation;
  late Animation<double> _indicatorRadiusAnimation;

  // 新增：悬停背景色动画控制器和动画
  late AnimationController _hoverAnimationController;
  late Animation<Color?> _hoverColorAnimation;

  static const double buttonSize = 45.0;
  static const double fullCircleRadius = buttonSize / 2;

  // 指示器尺寸常量
  static const double indicatorMaxWidth = 7.0;
  static const double indicatorMinDiameter = 7.0;
  static const double indicatorMaxHeight = buttonSize - 2 * 5.0;

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

    // 新增：悬停背景色动画控制器
    _hoverAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
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
    } else {
      // 确保未选中时显示小白点
      _indicatorAnimationController.value = 0.0;
    }
  }

  @override
  void didUpdateWidget(SidebarButtonTemplate oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selectedColor != widget.selectedColor ||
        oldWidget.iconBackgroundColor != widget.iconBackgroundColor ||
        oldWidget.selectedBorderRadius != widget.selectedBorderRadius ||
        oldWidget.indicatorColor != widget.indicatorColor ||
        oldWidget.hoverColor != widget.hoverColor) {
      _updateAnimations();
    }

    // 处理选中状态的变化 (驱动选中控制器和指示器控制器)
    if (oldWidget.isSelected != widget.isSelected) {
      if (widget.isSelected) {
        // 选中: 两个动画向前
        _selectAnimationController.forward();
        _indicatorAnimationController.forward();
        // 选中时取消悬停状态，确保悬停动画反转
        if (_isHovered) {
          _hoverAnimationController.reverse();
          _isHovered = false;
        }
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

    // 新增：悬停背景色动画
    _hoverColorAnimation =
        ColorTween(
          begin: widget.iconBackgroundColor,
          end: widget.hoverColor,
        ).animate(
          CurvedAnimation(
            parent: _hoverAnimationController,
            curve: Curves.easeOut,
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

  void _handleHover(bool isHovered) {
    if (widget.isSelected) return; // 选中时不响应悬停

    if (_isHovered != isHovered) {
      setState(() {
        _isHovered = isHovered;
      });

      // 驱动悬停动画控制器
      if (isHovered) {
        _hoverAnimationController.forward();
      } else {
        _hoverAnimationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _selectAnimationController.dispose();
    _indicatorAnimationController.dispose();
    _hoverAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      width: 65,
      height: buttonSize,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // 指示器 (小白点/侧边线)
          if (!widget.isAddButton)
            Positioned(
              left: indicatorLeftOffset,
              child: AnimatedBuilder(
                animation: _indicatorAnimationController,
                builder: (context, child) {
                  final double currentIndicatorHeight =
                      _indicatorHeightAnimation.value;
                  final double currentBorderRadius =
                      _indicatorRadiusAnimation.value;

                  // 只有当完全未选中且动画值为0且showDotIndicator为true时才显示小白点
                  if (!widget.isSelected &&
                      _indicatorAnimationController.value == 0.0 &&
                      widget.showDotIndicator) {
                    // 未选中状态显示小白点
                    return Container(
                      width: indicatorMinDiameter,
                      height: indicatorMinDiameter,
                      decoration: BoxDecoration(
                        color: widget.indicatorColor,
                        borderRadius: BorderRadius.circular(
                          indicatorMinDiameter / 2,
                        ),
                      ),
                    );
                  }

                  // 选中或过渡状态显示动画指示器（长条）
                  if (widget.isSelected ||
                      _indicatorAnimationController.value > 0.0) {
                    return Container(
                      width: indicatorMaxWidth,
                      height: currentIndicatorHeight,
                      decoration: BoxDecoration(
                        color: widget.indicatorColor,
                        borderRadius: BorderRadius.circular(
                          currentBorderRadius,
                        ),
                      ),
                    );
                  }

                  // 如果showDotIndicator为false且未选中，不显示任何指示器
                  return const SizedBox.shrink();
                },
              ),
            ),

          // 按钮本体 - 使用 Material 定义精确的悬停和点击区域
          Container(
            width: buttonSize,
            height: buttonSize,
            margin: const EdgeInsets.only(left: buttonLeftOffset),
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _selectAnimationController,
                _hoverAnimationController,
              ]),
              builder: (context, child) {
                final double currentRadius = _borderRadiusAnimation.value;

                Color? buttonColor;
                if (widget.isSelected) {
                  buttonColor = _selectColorAnimation.value;
                } else {
                  buttonColor = _hoverColorAnimation.value;
                }

                return Material(
                  color: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(currentRadius),
                  ),
                  child: MouseRegion(
                    onEnter: (_) => _handleHover(true),
                    onExit: (_) => _handleHover(false),
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                      onTap: widget.onPressed,
                      borderRadius: BorderRadius.circular(currentRadius),
                      hoverColor: widget.hoverColor,
                      child: Container(
                        width: buttonSize,
                        height: buttonSize,
                        decoration: BoxDecoration(
                          color: buttonColor,
                          borderRadius: BorderRadius.circular(currentRadius),
                        ),
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
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
