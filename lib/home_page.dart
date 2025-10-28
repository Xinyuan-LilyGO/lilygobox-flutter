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
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
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
                  // Text(
                  //      context.l10n.appTitle,
                  //      style: TextStyle(color: theme.textColor, fontSize: 100),
                  // ),
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

    // 侧边栏容器，宽度为 60
    return Container(
      width: 60,
      color: Colors.transparent,
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
            // 保持常规悬停颜色和效果
            hoverColor: theme.sidebarHoverIconColor,
          ),

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
              padding: EdgeInsets.zero, // 移除ListView默认的padding
              itemCount: boardSymbols.length,
              itemBuilder: (context, index) {
                final boardIndex = index + 1; // board indices start from 1
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
                  // 保持常规悬停颜色和效果
                  hoverColor: theme.sidebarHoverIconColor,
                );
              },
            ),
          ),

          // 添加板子按钮 - 永远不选中
          SidebarButtonTemplate(
            icon: Symbols.add,
            onPressed: () {
              // 添加板子按钮点击事件
              print('点击了添加板子按钮');
            },
            iconColor: theme.sidebarIconColor,
            iconBackgroundColor: theme.sidebarIconBackgroundColor,
            highlightColor: theme.sidebarIconHighlightColor,
            splashColor: theme.sidebarIconSplashColor,
            isSelected: false, // 明确设置为不选中
            selectedColor: theme.sidebarSelectedIconColor,
            // 禁用悬停圆角变化
            disableHoverEffect: true,
            // 悬停时变亮，使用主题的悬停色
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

    // 新增选中相关参数
    this.isSelected = false,
    this.selectedBorderRadius = 15.0,
    // 作为悬停颜色
    this.hoverColor = Colors.grey,
    // 禁用圆角变化
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
  final Color highlightColor; // 点击按住时的颜色
  final Color splashColor;

  // 选中状态相关属性
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
  // 两个颜色动画，一个用于选中/未选中状态，一个用于悬停时的颜色变化
  late Animation<Color?> _selectColorAnimation;
  late Animation<Color?> _hoverColorAnimation;

  static const double buttonSize = 45.0;
  // 对应的圆形圆角半径 (45 / 2 = 22.5)
  static const double fullCircleRadius = buttonSize / 2;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    _updateAnimations();

    // 如果按钮被选中，直接设置为选中状态
    if (widget.isSelected) {
      _animationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SidebarButtonTemplate oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 只有颜色、圆角或背景色改变时才需要重建动画对象
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
        // 从未选中动画到选中
        _animationController.forward(from: _animationController.value);
      } else {
        // 从选中动画到未选中
        _animationController.reverse(from: _animationController.value);
      }
    }
  }

  void _updateAnimations() {
    // 如果禁用悬停效果 (用于加号按钮)，圆角动画的终点是圆形
    final double endRadius = widget.disableHoverEffect
        ? fullCircleRadius
        : widget.selectedBorderRadius;

    // 控制按钮的圆角半径
    _borderRadiusAnimation =
        Tween<double>(
          begin: fullCircleRadius, // 圆形 (22.5)
          end: endRadius, // 悬停或选中时的圆角 (15.0) 或保持圆形 (22.5)
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    // 使用传入的 hoverColor 作为目标色（对于加号按钮，它现在是一个亮色）
    final Color hoverTargetColor = widget.hoverColor;

    // 控制按钮从默认背景色变到悬停颜色（或加号按钮的亮色）
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

    // 控制按钮从默认背景色变到选中颜色
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
  }

  void _handleHover(bool isHovered) {
    // 如果按钮已经被选中，不响应悬停效果
    if (widget.isSelected) return;

    // 如果处于未选中状态，响应悬停来驱动圆角和悬停颜色动画
    if (isHovered) {
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
    // 调整 margin 以适配 45x45 尺寸 (60 - 45 = 15, 15 / 2 = 7.5)
    const double horizontalMargin = 7.5;

    return MouseRegion(
      onEnter: (_) => _handleHover(true),
      onExit: (_) => _handleHover(false),
      cursor: SystemMouseCursors.click,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: horizontalMargin,
          vertical: 8,
        ),
        width: buttonSize, // 45.0
        height: buttonSize, // 45.0
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            // 根据动画值确定圆角
            final double currentRadius = _borderRadiusAnimation.value;

            final Color? buttonColor;
            if (widget.isSelected) {
              // 选中状态：使用 selectColorAnimation
              buttonColor = _selectColorAnimation.value;
            } else {
              // 未选中状态：使用 hoverColorAnimation (加号按钮会变亮)
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
    );
  }
}
