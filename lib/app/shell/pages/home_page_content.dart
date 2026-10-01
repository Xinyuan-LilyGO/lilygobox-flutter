/*
 * @Description: 展示首页导航、欢迎内容及可拖动的左右分栏。
 * @Author: LILYGO_L
 * @Date: 2025-11-07 11:23:45
 * @LastEditTime: 2025-11-19 16:30:42
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/language_provider.dart';
import '../../../core/layout/split_view_provider.dart';
import '../../../core/theme/provider.dart';
import '../../../core/widgets/resizable_split_view.dart';

class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  // 默认选中的菜单项 Key
  String _selectedTitleKey = 'start'; // 修改默认选中为"开始"
  // 用于存储当前悬停颜色状态的 Map
  final Map<String, Color> _currentHoverColors = {};

  // 动画持续时间
  final Duration _animationDuration = const Duration(milliseconds: 150);

  // 获取菜单项列表 - 只保留 start 项
  List<Map<String, dynamic>> _getMenuItems(BuildContext context) {
    return [
      // 没有header的"开始"item，放在最前面
      {
        'type': 'standalone_item',
        'title': context.l10n.start,
        'key': 'start',
        'icon': Symbols.borg,
      },
    ];
  }

  // 根据选中的key获取对应的右侧内容
  Widget _buildRightContent(String selectedKey, BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    switch (selectedKey) {
      case 'start':
        return _buildStartContent(theme, context);
      default:
        return _buildDefaultContent(theme, context);
    }
  }

  // 开始页面内容
  Widget _buildStartContent(AppTheme theme, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center, // 改为居中
      children: [
        const SizedBox(height: 50),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 50.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center, // 改为居中
            children: [
              Text(
                context.l10n.homePageContentStartTitle,
                style: TextStyle(
                  fontSize: 30, // 增大标题字体大小
                  fontWeight: FontWeight.bold,
                  color: theme.textColorPrimary,
                ),
                textAlign: TextAlign.center, // 文字居中
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.homePageContentStartDescription,
                style: TextStyle(
                  fontSize: 14, // 描述文字保持较小
                  color: theme.textColorSecondary,
                ),
                textAlign: TextAlign.center, // 文字居中
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 默认页面内容
  Widget _buildDefaultContent(AppTheme theme, BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.help_outline, size: 64, color: theme.textColorSecondary),
          const SizedBox(height: 16),
          Text(
            "页面开发中",
            style: TextStyle(fontSize: 18, color: theme.textColorSecondary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取主题数据
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    final splitViewProvider = Provider.of<SplitViewProvider>(
      context,
      listen: false,
    );

    // 获取菜单项
    final menuItems = _getMenuItems(context);

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
              context.l10n.home,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textColorPrimary, // 使用 theme.textColorPrimary
              ),
            ),
          ),

          // 分割线
          Divider(color: theme.dividerColorNormal, height: 1, thickness: 2),

          // 使用 AnimatedSize 包裹整个列表以实现整体高度动画
          Expanded(
            child: AnimatedSize(
              duration: _animationDuration,
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 5.0), // 顶部留出空间
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final item = menuItems[index];

                  // 处理 standalone_item
                  if (item['type'] == 'standalone_item') {
                    final title = item['title'] as String;
                    final key = item['key'] as String;
                    final isSelected = key == _selectedTitleKey;
                    final icon = item['icon'] as IconData?;

                    // 计算目标背景色
                    final targetColor = isSelected
                        ? theme.secondaryTextSelectedColor
                        : _currentHoverColors[key] ?? theme.secondary;

                    // standalone_item 使用不同的边距，使其与有header的item位置不同
                    return Container(
                      margin: const EdgeInsets.only(
                        left: 10.0,
                        top: 2.0,
                        right: 15.0,
                        bottom: 2.0,
                      ),
                      child: SizedBox(
                        height: 30.0,
                        child: TweenAnimationBuilder<Color?>(
                          duration: const Duration(milliseconds: 150),
                          tween: ColorTween(
                            begin: theme.secondary,
                            end: targetColor,
                          ),
                          builder: (context, color, child) {
                            return InkWell(
                              onHover: (isHovering) {
                                if (!isSelected) {
                                  setState(() {
                                    _currentHoverColors[key] = isHovering
                                        ? theme.secondaryTextHoverColor
                                        : theme.secondary;
                                  });
                                }
                              },
                              onTap: () {
                                setState(() {
                                  _selectedTitleKey = key;
                                  _currentHoverColors.updateAll(
                                    (k, value) => theme.secondary,
                                  );
                                });
                              },
                              borderRadius: BorderRadius.circular(6.0),
                              child: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 0.0,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(6.0),
                                ),
                                child: Row(
                                  children: [
                                    // 图标
                                    if (icon != null)
                                      Icon(
                                        icon,
                                        size: 18,
                                        color: theme.textColorSecondary,
                                        fill: 1,
                                        grade: 200,
                                        opticalSize: 20,
                                        weight: 300,
                                      ),
                                    if (icon != null) const SizedBox(width: 3),
                                    // 文本
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: theme.textColorSecondary,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
    );

    // 右侧面板的新内容 - 使用 AnimatedSwitcher 实现动画切换
    final rightPanelContent = Container(
      color: theme.tertiary,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: Container(
          key: ValueKey(_selectedTitleKey), // 使用选中的key作为唯一标识
          child: _buildRightContent(_selectedTitleKey, context),
        ),
      ),
    );

    // 使用 ClipRRect 确保分栏视图遵循外部 Container 的圆角
    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
      child: ResizableSplitView(
        leftWidget: leftPanelContent,
        rightWidget: rightPanelContent,
        initialWidth: splitViewProvider.splitWidth,
      ),
    );
  }
}
