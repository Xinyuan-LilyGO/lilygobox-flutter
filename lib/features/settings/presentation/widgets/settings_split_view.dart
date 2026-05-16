import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/app_navigation_provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/widgets/animated_circle_icon_button.dart';
import '../pages/settings_page_about_content.dart';
import '../pages/settings_page_language_and_region_content.dart';
import '../pages/settings_page_personalization_content.dart';

class SettingsSplitView extends StatefulWidget {
  const SettingsSplitView({super.key});

  @override
  State<SettingsSplitView> createState() => _SettingsSplitViewState();
}

class _SettingsSplitViewState extends State<SettingsSplitView> {
  // 菜单项的键（不变的），用于 _selectedTitle 和 _contentMap
  static const String _generalKey = 'general';
  static const String _languageKey = 'languageAndRegion';
  static const String _themeKey = 'personalization';
  static const String _aboutKey = 'about';

  // 当前选中的菜单项的 key
  String _selectedTitleKey = _generalKey; // 使用不变的 key 作为选中标识

  // 映射菜单项的 key 到一个唯一的数字 ID，用于 _buildContent 的 switch 语句
  final Map<String, int> _contentMap = {
    _generalKey: 0,
    _languageKey: 1,
    _themeKey: 2,
    _aboutKey: 3,
  };

  // 只记录悬停项，具体颜色始终从当前主题实时计算。
  final Set<String> _hoveredMenuKeys = <String>{};

  // 颜色渐变的持续时间
  static const Duration _animationDuration = Duration(milliseconds: 150);

  /// 根据当前选中的键返回对应的设置内容 Widget
  Widget _buildContent(dynamic theme) {
    final selectedIndex = _contentMap[_selectedTitleKey] ?? 0;

    switch (selectedIndex) {
      case 0: // 通用设置
        return Center(
          child: Text(
            // 这里可以继续使用本地化文本，或者直接写固定的 key 方便调试
            '通用设置内容区域 ($_selectedTitleKey)',
            style: TextStyle(color: theme.textColorPrimary),
          ),
        );
      case 1: // 语言与地区
        return LanguageAndRegionContent(theme: theme);
      case 2: // 外观主题
        return PersonalizationContent(theme: theme);
      case 3: // 关于
        return AboutContent(theme: theme);
      default:
        return const SizedBox.shrink();
    }
  }

  // 构建菜单项列表，需要在 build 方法中调用，以便访问 context
  List<Map<String, dynamic>> _buildMenuItems(BuildContext context) {
    return [
      {'type': 'header', 'title': context.l10n.basic}, // 基础
      {
        'type': 'item',
        'title': context.l10n.general,
        'key': _generalKey,
      }, // 通用设置
      {'type': 'divider'}, // 分隔线
      {'type': 'header', 'title': context.l10n.application}, // 应用
      {
        'type': 'item',
        'title': context.l10n.languageAndRegion,
        'key': _languageKey,
      }, // 语言与地区
      {
        'type': 'item',
        'title': context.l10n.personalization,
        'key': _themeKey,
      }, // 外观主题
      {'type': 'item', 'title': context.l10n.about, 'key': _aboutKey}, // 关于
    ];
  }

  Color _menuItemBackgroundColor(
    AppTheme theme, {
    required bool isSelected,
    required bool isHovered,
  }) {
    if (isSelected) {
      return theme.primaryTextSelectedColor;
    }

    if (isHovered) {
      return theme.primaryTextHoverColor;
    }

    return theme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

    // 获取本地化文本
    final menuItems = _buildMenuItems(context);

    return Row(
      children: [
        // 左侧：设置菜单导航 (Menu/Sidebar)
        AnimatedContainer(
          duration: _animationDuration,
          width: 250, // 侧边栏略微加宽
          color: theme.primary, // 保持 theme.primary 颜色
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题：移到左侧栏
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  15.0,
                  15.0,
                  15.0,
                  5.0,
                ), // 顶部/左侧边距
                child: Text(
                  context.l10n.settings, // 使用本地化标题
                  style: TextStyle(
                    fontWeight: FontWeight.bold, // 设得更粗一些
                    fontSize: 20,
                    color: theme.textColorPrimary,
                  ),
                ),
              ),

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
                        padding: const EdgeInsets.fromLTRB(
                          15.0,
                          10.0,
                          10.0,
                          5.0,
                        ),
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
                    final isSelected =
                        key == _selectedTitleKey; // 使用 key 来判断是否选中
                    final isHovered = _hoveredMenuKeys.contains(key);

                    final targetColor = _menuItemBackgroundColor(
                      theme,
                      isSelected: isSelected,
                      isHovered: isHovered,
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15.0,
                        vertical: 2.0, // 保持外部垂直边距一致
                      ),
                      child: SizedBox(
                        height: 30.0,
                        child: InkWell(
                          onHover: (isHovering) {
                            if (!isSelected) {
                              setState(() {
                                if (isHovering) {
                                  _hoveredMenuKeys.add(key);
                                } else {
                                  _hoveredMenuKeys.remove(key);
                                }
                              });
                            }
                          },
                          onTap: () {
                            setState(() {
                              _selectedTitleKey = key;
                              _hoveredMenuKeys.clear();
                            });
                          },
                          borderRadius: BorderRadius.circular(6.0),
                          child: AnimatedContainer(
                            duration: _animationDuration,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10.0,
                              vertical: 0.0,
                            ),
                            decoration: BoxDecoration(
                              color: targetColor,
                              borderRadius: BorderRadius.circular(6.0),
                            ),
                            child: Text(
                              title,
                              style: TextStyle(
                                color: theme.textColorSecondary,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
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
        ),

        // 右侧：设置详细内容 (Content)
        Expanded(
          child: AnimatedContainer(
            duration: _animationDuration,
            color: theme.secondary,
            child: Stack(
              children: [
                // 内容区
                Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: Container(
                      key: ValueKey<String>(_selectedTitleKey), // 使用 key
                      child: _buildContent(theme),
                    ),
                  ),
                ),

                Positioned(
                  top: 20,
                  right: 20,
                  child: AnimatedCircleIconButton(
                    icon: Symbols.close_rounded,
                    theme: theme,
                    size: 40,
                    iconSize: 22,
                    onPressed: () =>
                        context.read<AppNavigationProvider>().goHome(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
