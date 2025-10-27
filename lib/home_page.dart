import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Text(
                  //   context.l10n.appTitle,
                  //   style: TextStyle(color: theme.textColor, fontSize: 100),
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

    return Container(
      width: 60,
      color: Colors.transparent,
      child: Column(
        children: [
          // 房子按钮
          SidebarButtonTemplate(
            icon: Symbols.home,
            onPressed: () {
              // 主页按钮点击事件
            },
            iconColor: theme.sidebarIconColor,
            iconBackgroundColor: theme.sidebarIconBackgroundColor,
            highlightColor: theme.sidebarIconHighlightColor,
            splashColor: theme.sidebarIconSplashColor,
          ),

          // 分隔线
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            color: theme.dividerColor?.withOpacity(0.3) ?? Colors.grey.shade600,
          ),

          // 可滚动的板子列表
          // Expanded(
          //   child: ListView.builder(
          //     padding: const EdgeInsets.only(top: 8),
          //     itemCount: 10, // 示例数据，实际使用时替换为你的数据
          //     itemBuilder: (context, index) {
          //       return SidebarButtonTemplate(
          //         icon: boardSymbols[index % boardSymbols.length],
          //         onPressed: () {
          //           // 板子项点击事件
          //         },
          //         theme: theme,
          //         isSelected: index == 0,
          //       );
          //     },
          //   ),
          // ),

          // 添加板子按钮
          SidebarButtonTemplate(
            icon: Symbols.add,
            onPressed: () {
              // 添加板子按钮点击事件
            },
            iconColor: theme.sidebarIconColor,
            iconBackgroundColor: theme.sidebarIconBackgroundColor,
            highlightColor: theme.sidebarIconHighlightColor,
            splashColor: theme.sidebarIconSplashColor,
          ),

          // const SizedBox(height: 10),
        ],
      ),
    );
  }

  // Widget _buildBoardItem({required int index, required AppTheme theme}) {
  //   // 示例数据 - 实际使用时替换为你的板子数据
  //   final boardSymbols = [
  //     Symbols.chat,
  //     Symbols.people,
  //     Symbols.music_note,
  //     Symbols.games,
  //     Symbols.code,
  //     Symbols.photo_camera,
  //     Symbols.videogame_asset,
  //     Symbols.sports_esports,
  //     Symbols.movie,
  //     Symbols.science,
  //   ];

  //   final boardColors = [
  //     Colors.red,
  //     Colors.blue,
  //     Colors.green,
  //     Colors.orange,
  //     Colors.purple,
  //     Colors.pink,
  //     Colors.teal,
  //     Colors.amber,
  //     Colors.cyan,
  //     Colors.deepOrange,
  //   ];

  //   return Container(
  //     margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
  //     child: Material(
  //       color: index == 0 ? theme.secondary : Colors.transparent,
  //       borderRadius: BorderRadius.circular(15),
  //       child: InkWell(
  //         onTap: () {
  //           // 板子项点击事件
  //         },
  //         borderRadius: BorderRadius.circular(15),
  //         child: Container(
  //           width: 50,
  //           height: 50,
  //           decoration: BoxDecoration(
  //             borderRadius: BorderRadius.circular(15),
  //             color: index == 0
  //                 ? theme.secondary
  //                 : boardColors[index % boardColors.length].withOpacity(0.8),
  //           ),
  //           child: Icon(
  //             boardSymbols[index % boardSymbols.length],
  //             color: index == 0 ? theme.textColor : Colors.white,
  //             size: 24,
  //           ),
  //         ),
  //       ),
  //     ),
  //   );
  // }
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

  @override
  State<SidebarButtonTemplate> createState() => _SidebarButtonTemplateState();
}

class _SidebarButtonTemplateState extends State<SidebarButtonTemplate>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _borderRadiusAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _borderRadiusAnimation =
        Tween<double>(
          begin: 25.0, // 初始圆角
          end: 15.0, // 悬停时的圆角
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleHover(bool isHovered) {
    if (isHovered) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _handleHover(true),
      onExit: (_) => _handleHover(false),
      cursor: SystemMouseCursors.click,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        child: SizedBox(
          width: 45,
          height: 45,
          child: AnimatedBuilder(
            animation: _borderRadiusAnimation,
            builder: (context, child) {
              return Material(
                color: widget.iconBackgroundColor, 
                borderRadius: BorderRadius.circular(
                  _borderRadiusAnimation.value,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(
                    _borderRadiusAnimation.value,
                  ),
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
      ),
    );
  }
}
