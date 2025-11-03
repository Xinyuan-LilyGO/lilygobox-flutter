import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart';
import 'language.dart';
import 'window.dart';

class SplitViewTemplate extends StatefulWidget {
  // 引入 windowProvider 用于关闭按钮
  final WindowProvider windowProvider;

  const SplitViewTemplate({super.key, required this.windowProvider});

  @override
  State<SplitViewTemplate> createState() => _SplitViewTemplateState();
}

class _SplitViewTemplateState extends State<SplitViewTemplate> {
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

  // 用于追踪关闭按钮的悬停状态
  bool _isHoveringClose = false;

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
        return Center(
          child: Text(
            '语言与地区设置内容区域 ($_selectedTitleKey)',
            style: TextStyle(color: theme.textColorPrimary),
          ),
        );
      case 2: // 外观主题
        return Center(
          child: Text(
            '外观主题设置内容区域 ($_selectedTitleKey)',
            style: TextStyle(color: theme.textColorPrimary),
          ),
        );
      case 3: // 关于
        return Center(
          child: Text(
            '关于内容区域 ($_selectedTitleKey)',
            style: TextStyle(color: theme.textColorPrimary),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // 构建菜单项列表，需要在 build 方法中调用，以便访问 context
  List<Map<String, dynamic>> _buildMenuItems(BuildContext context) {
    // 访问本地化文本
    final l10n = context.l10n;

    return [
      {'type': 'header', 'title': l10n.basic}, // '基础' -> l10n.basic
      {
        'type': 'item',
        'title': l10n.general,
        'key': _generalKey,
      }, // '通用设置' -> l10n.general
      {'type': 'divider'}, // 分隔线
      {'type': 'header', 'title': l10n.application}, // '应用' -> l10n.application
      {
        'type': 'item',
        'title': l10n.languageAndRegion,
        'key': _languageKey,
      }, // '语言与地区' -> l10n.languageAndRegion
      {
        'type': 'item',
        'title': l10n.personalization,
        'key': _themeKey,
      }, // '外观主题' -> l10n.personalization
      {
        'type': 'item',
        'title': l10n.about,
        'key': _aboutKey,
      }, // '关于' -> l10n.about
    ];
  }

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
                  context.l10n.settingsTitle, // 使用本地化标题
                  style: TextStyle(
                    fontWeight: FontWeight.w900, // 设得更粗一些
                    fontSize: 18,
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
                        ? theme.textSelectedColor
                        : _currentHoverColors[key] ??
                              Colors.transparent; // 使用 key 访问 hover 颜色

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15.0,
                        vertical: 2.0, // 保持外部垂直边距一致
                      ),
                      // 使用 TweenAnimationBuilder 实现颜色渐变
                      child: TweenAnimationBuilder<Color?>(
                        duration: _animationDuration, // 渐变时间
                        tween: ColorTween(
                          begin: Colors.transparent,
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
                                        ? theme.textHoverColor
                                        : Colors.transparent;
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
                                    (k, value) => Colors.transparent,
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
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHoveringClose = true),
                    onExit: (_) => setState(() => _isHoveringClose = false),
                    child: AnimatedContainer(
                      duration: _animationDuration,
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _isHoveringClose
                            ? theme.iconHoverColor
                            : theme.iconBackgroundColor,
                        shape: BoxShape.circle,
                      ),
                      child: Material(
                        color: Colors.transparent, // 确保 Material 背景透明
                        child: InkWell(
                          onTap: () {
                            widget.windowProvider.setPage(WindowPage.home);
                          },
                          borderRadius: BorderRadius.circular(20.0),
                          child: Center(
                            child: Icon(
                              Symbols.close_rounded,
                              size: 18,
                              color: theme.iconColor,
                            ),
                          ),
                        ),
                      ),
                    ),
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

class SettingsPage extends StatelessWidget {
  final WindowProvider windowProvider;

  const SettingsPage({super.key, required this.windowProvider});

  @override
  Widget build(BuildContext context) {
    // 确保使用正确的方式获取 Provider 的值 (使用 listen: false)
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    // 移除顶部栏Container，让 SplitViewTemplate 填充整个屏幕
    return Container(
      color: theme.primary, // 整体背景色
      child: SplitViewTemplate(windowProvider: windowProvider),
    );
  }
}
