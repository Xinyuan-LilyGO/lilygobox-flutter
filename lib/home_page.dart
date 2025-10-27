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
    // 监听主题变化
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
                // 移除不必要的 const
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
    // 侧边栏构建时，不监听主题变化，只获取一次数据。
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
            // ************ 新增 hoverColor 传递 ************
            hoverColor: theme.sidebarHoverIconColor,
          ),

          // 分隔线
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: theme.dividerColor?.withOpacity(0.3) ?? Colors.grey.shade600,
          ),

          // ****************** 修改点：在分隔线和列表之间添加间距 ******************
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
                  // ************ 新增 hoverColor 传递 ************
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
            // ************ 新增 hoverColor 传递 ************
            hoverColor: theme.sidebarHoverIconColor,
          ),

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
    // ************ 新增 hoverColor 参数 ************
    this.hoverColor = Colors.grey,

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

  // 选中状态相关属性
  final bool isSelected;
  final Color selectedColor;
  final double selectedBorderRadius;
  // ************ 新增 hoverColor 属性 ************
  final Color hoverColor;

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

  // **修改点 1: 按钮的尺寸改为 45.0**
  static const double buttonSize = 45.0;
  // **修改点 2: 对应的圆形圆角半径 (45 / 2 = 22.5)**
  static const double fullCircleRadius = buttonSize / 2; // 22.5

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
        // ************ 新增判断 hoverColor 是否改变 ************
        oldWidget.hoverColor != widget.hoverColor) {
      _updateAnimations();
    }

    // 处理选中状态的变化
    if (oldWidget.isSelected != widget.isSelected) {
      if (widget.isSelected) {
        // 从未选中动画到选中
        // 注意：这里我们让动画运行到 1.0，这会同时影响圆角和颜色（如果是选中状态）。
        _animationController.forward(from: _animationController.value);
      } else {
        // 从选中动画到未选中
        _animationController.reverse(from: _animationController.value);
      }
    }
  }

  void _updateAnimations() {
    _borderRadiusAnimation =
        Tween<double>(
          begin: fullCircleRadius, // 圆形 (22.5)
          end: widget.selectedBorderRadius, // 选中/悬停时的圆角 (15.0)
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    // ************ 新增悬停颜色动画 ************
    // 这个动画专门用于“未选中”时的悬停效果：iconBackgroundColor -> hoverColor
    _hoverColorAnimation =
        ColorTween(
          begin: widget.iconBackgroundColor,
          end: widget.hoverColor,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    // ************ 选中颜色动画（保持原始逻辑） ************
    // 这个动画用于“选中”状态时的颜色：iconBackgroundColor -> selectedColor
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

    // 未选中时，响应悬停来驱动圆角和悬停颜色动画
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
    // **修改点 3: 调整 margin 以适配 45x45 尺寸 (60 - 45 = 15, 15 / 2 = 7.5)**
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

            // ****************** 关键修改点: 背景颜色逻辑 ******************
            final Color? buttonColor;
            if (widget.isSelected) {
              // 选中状态：使用 selectColorAnimation（过渡到 selectedColor）
              buttonColor = _selectColorAnimation.value;
            } else {
              // 未选中状态：使用 hoverColorAnimation（过渡到 hoverColor）
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
