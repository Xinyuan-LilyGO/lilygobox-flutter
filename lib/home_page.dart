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
          ),

          // const SizedBox(height: 10),
        ],
      ),
    );
  }

  // Widget _buildBoardItem({required int index, required AppTheme theme}) {
  //   // 示例数据
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

class SidebarButtonTemplate extends StatelessWidget {
  const SidebarButtonTemplate({
    super.key,
    required this.icon,
    required this.onPressed,
    this.iconSize = 24,
    this.iconWeight = 600.0,
    this.grade = -25.0,
    this.opticalSize = 48.0,
    this.iconColor = Colors.white,
    this.iconBackgroundColor = Colors.grey,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final double iconWeight;
  final double grade;
  final double opticalSize;
  final Color iconColor;
  final Color iconBackgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      child: SizedBox(
        width: 45,
        height: 45,
        child: Material(
          color: iconBackgroundColor,
          borderRadius: BorderRadius.circular(25),
          child: InkWell(
            borderRadius: BorderRadius.circular(25),
            onTap: onPressed,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                // color: backgroundColor,
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: iconColor,
                weight: iconWeight,
                grade: grade,
                opticalSize: opticalSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
