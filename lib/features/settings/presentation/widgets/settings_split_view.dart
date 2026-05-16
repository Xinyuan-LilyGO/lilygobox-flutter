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

  // 用于存储每个菜单项当前 Hover 颜色的 Map
  // Key: 菜单项的 key (例如 'general'), Value: 当前的悬停颜色 (Color)
  late Map<String, Color> _currentHoverColors;

  @override
  void initState() {
    super.initState();
    // 初始化 Hover 颜色 Map，使用固定的 key
    _currentHoverColors = {
      _generalKey: Colors.transparent,
      _languageKey: Colors.transparent,
      _themeKey: Colors.transparent,
      _aboutKey: Colors.transparent,
    };
  }

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 监听主题变化，但只在主题真正变化时重置悬停颜色
    final newTheme = Provider.of<ThemeProvider>(
      context,
      listen: true,
    ).themeData;

    // 只有当主题变化时才更新悬停颜色
    if (_lastTheme != newTheme) {
      _lastTheme = newTheme;

      // 重置所有非选中项的悬停颜色为主题的主色
      setState(() {
        _currentHoverColors.updateAll((key, value) {
          // 如果是选中项，保持选中颜色；否则重置为主题主色
          return key == _selectedTitleKey
              ? value // 保持选中项的颜色不变
              : newTheme.primary;
        });
      });
    }
  }

  // 添加一个变量来追踪上次的主题
  AppTheme? _lastTheme;

  @override
  Widget build(BuildContext context) {
    // 明确使用 Provider.of 并设置为 listen: true 以响应主题更改
    final theme = Provider.of<ThemeProvider>(context, listen: true).themeData;
    // 获取本地化文本
    final menuItems = _buildMenuItems(context);

    return Row(
      children: [
        // 左侧：设置菜单导航 (Menu/Sidebar)
        Container(
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

                    // 计算目标背景色
                    final targetColor = isSelected
                        ? theme.primaryTextSelectedColor
                        : _currentHoverColors[key] ??
                              theme.primary; // 使用 key 访问 hover 颜色

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15.0,
                        vertical: 2.0, // 保持外部垂直边距一致
                      ),
                      // 使用 TweenAnimationBuilder 实现颜色渐变
                      child: TweenAnimationBuilder<Color?>(
                        duration: _animationDuration, // 渐变时间
                        tween: ColorTween(
                          begin: theme.primary,
                          end: targetColor, // 渐变的目标颜色
                        ),
                        builder: (context, color, child) {
                          // 使用 SizedBox 强制列表项高度固定
                          return SizedBox(
                            height: 30.0,
                            child: InkWell(
                              // onHover 实现鼠标悬停/离开效果
                              onHover: (isHovering) {
                                // 只有未选中项才响应悬停
                                if (!isSelected) {
                                  setState(() {
                                    // 更新 Map 中的悬停目标颜色，使用 key
                                    _currentHoverColors[key] = isHovering
                                        ? theme.primaryTextHoverColor
                                        : theme.primary;
                                  });
                                }
                              },

                              // 使用 InkWell 实现点击效果
                              onTap: () {
                                // 点击时重置所有 hover 颜色，并切换选中项
                                setState(() {
                                  _selectedTitleKey = key; // 切换选中的 key
                                  // 重置所有项的悬停颜色为透明，因为点击操作已经完成
                                  _currentHoverColors.updateAll(
                                    (k, value) => theme.primary,
                                  );
                                });
                              },
                              borderRadius: BorderRadius.circular(6.0),
                              child: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0,
                                  vertical: 0.0,
                                ),
                                decoration: BoxDecoration(
                                  // 使用 TweenAnimationBuilder 返回的 color
                                  color: color,
                                  borderRadius: BorderRadius.circular(6.0),
                                ),
                                child: Text(
                                  title, // 本地化的标题
                                  style: TextStyle(
                                    // 字体颜色保持不变，只有背景色变化
                                    color: theme.textColorSecondary,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
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
          child: Container(
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
