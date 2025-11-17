import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'provider/theme_provider.dart';
import 'provider/language_provider.dart';
import 'provider/window_provider.dart';
import 'provider/package_info_provider.dart';

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
        return LanguageAndRegionContent(theme: theme);
      case 2: // 外观主题
        return Center(
          child: Text(
            '外观主题设置内容区域 ($_selectedTitleKey)',
            style: TextStyle(color: theme.textColorPrimary),
          ),
        );
      case 3: // 关于
        return AboutContent(theme: theme);
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
                              size: 22,
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

/// 关于内容区域的 Widget
class AboutContent extends StatelessWidget {
  final dynamic theme; // 接受主题数据

  const AboutContent({super.key, required this.theme});

  // 构建关于页面中的信息项 (Item)
  Widget _buildInfoItem(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: theme.textColorTertiary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: theme.textColorSecondary, // 主要颜色用于内容
              fontSize: 16,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packageInfoProvider = Provider.of<PackageInfoProvider>(
      context,
      listen: false,
    );

    return Container(
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.fromLTRB(40.0, 30.0, 40.0, 40.0), // 内部边距
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 主标题
            Text(
              context.l10n.about,
              style: TextStyle(
                color: theme.textColorPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            // 分隔线
            Divider(color: theme.dividerColor, height: 1),

            const SizedBox(height: 20),

            _buildInfoItem(
              context.l10n.version,
              'v${packageInfoProvider.version}',
            ),

            const SizedBox(height: 10),

            _buildInfoItem(
              context.l10n.copyright,
              '${packageInfoProvider.appName} \n© 2025 LILYGO Corporation${context.l10n.allRightsReserved}',
            ),
          ],
        ),
      ),
    );
  }
}

// 添加新的语言与地区内容组件
class LanguageAndRegionContent extends StatefulWidget {
  final dynamic theme;

  const LanguageAndRegionContent({super.key, required this.theme});

  @override
  State<LanguageAndRegionContent> createState() =>
      _LanguageAndRegionContentState();
}

class _LanguageAndRegionContentState extends State<LanguageAndRegionContent> {
  // 语言选择器的折叠状态
  bool _isLanguageSelectorExpanded = false;

  // 用于存储语言选项的悬停状态
  final Map<String, Color> _languageHoverColors = {};

  // 当前选中语言的悬停状态
  Color? _currentLanguageHoverColor;

  // 动画持续时间
  final Duration _animationDuration = const Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(
      context,
      listen: true,
    );
    final currentLanguageCode = languageProvider.locale.languageCode;

    // 根据当前的语言代码找到对应的 Map 对象
    final currentLanguageMap = LanguageProvider.supportedLanguages.firstWhere(
      (lang) => lang['code'] == currentLanguageCode,
      orElse: () => {'code': 'en', 'name': 'English', 'nativeName': 'English'},
    );

    return Container(
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.fromLTRB(40.0, 30.0, 40.0, 40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            context.l10n.languageAndRegion,
            style: TextStyle(
              color: widget.theme.textColorPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          // 分隔线
          Divider(color: widget.theme.dividerColor, height: 1),

          const SizedBox(height: 20),

          // 语言设置区域 - 改为折叠选择器
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧说明 (flex: 2)
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "语言",
                      style: TextStyle(
                        color: widget.theme.textColorTertiary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "选择您偏好的应用程序界面语言",
                      style: TextStyle(
                        color: widget.theme.textColorSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 40),

              // 右侧语言选择折叠列表
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 当前选中的语言显示区域 (可点击展开/折叠)
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: widget.theme.primary,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: MouseRegion(
                          onEnter: (_) {
                            setState(() {
                              _currentLanguageHoverColor =
                                  widget.theme.secondaryTextHoverColor;
                            });
                          },
                          onExit: (_) {
                            setState(() {
                              _currentLanguageHoverColor = null;
                            });
                          },
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isLanguageSelectorExpanded =
                                    !_isLanguageSelectorExpanded;
                              });
                            },
                            child: AnimatedContainer(
                              duration: _animationDuration,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10.0,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _currentLanguageHoverColor ??
                                    widget.theme.primary,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        // 语言名称和本地名称紧挨着显示
                                        Flexible(
                                          child: RichText(
                                            overflow: TextOverflow.ellipsis,
                                            text: TextSpan(
                                              children: [
                                                TextSpan(
                                                  text:
                                                      currentLanguageMap['nativeName']!,
                                                  style: TextStyle(
                                                    color: widget
                                                        .theme
                                                        .textColorPrimary,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text:
                                                      " (${currentLanguageMap['name']!})",
                                                  style: TextStyle(
                                                    color: widget
                                                        .theme
                                                        .textColorTertiary,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AnimatedRotation(
                                    turns: _isLanguageSelectorExpanded
                                        ? 0.0
                                        : -0.25,
                                    duration: _animationDuration,
                                    curve: Curves.easeInOut,
                                    child: Icon(
                                      Icons.arrow_drop_down,
                                      color: widget.theme.textColorSecondary,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 3),

                    // 语言选项列表 (可折叠)
                    AnimatedContainer(
                      duration: _animationDuration,
                      height: _isLanguageSelectorExpanded
                          ? (LanguageProvider.supportedLanguages.length * 40.0)
                          : 0,
                      child: AnimatedOpacity(
                        duration: _animationDuration,
                        opacity: _isLanguageSelectorExpanded ? 1.0 : 0.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: widget.theme.primary,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          clipBehavior: Clip.antiAlias, // 确保子组件不会超出圆角边界
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount:
                                LanguageProvider.supportedLanguages.length,
                            itemBuilder: (context, index) {
                              final language =
                                  LanguageProvider.supportedLanguages[index];
                              final isSelected =
                                  language['code'] == currentLanguageCode;
                              final isFirst = index == 0;
                              final isLast =
                                  index ==
                                  LanguageProvider.supportedLanguages.length -
                                      1;

                              // 根据位置设置不同的圆角
                              BorderRadius borderRadius = BorderRadius.zero;
                              if (isFirst && isLast) {
                                // 只有一个选项时
                                borderRadius = BorderRadius.circular(5);
                              } else if (isFirst) {
                                // 第一个选项
                                borderRadius = const BorderRadius.only(
                                  topLeft: Radius.circular(5),
                                  topRight: Radius.circular(5),
                                );
                              } else if (isLast) {
                                // 最后一个选项
                                borderRadius = const BorderRadius.only(
                                  bottomLeft: Radius.circular(5),
                                  bottomRight: Radius.circular(5),
                                );
                              }
                              // 中间选项保持 BorderRadius.zero（无圆角）

                              return Material(
                                color: Colors.transparent,
                                child: MouseRegion(
                                  onEnter: (_) {
                                    if (!isSelected) {
                                      setState(() {
                                        _languageHoverColors[language['code']!] =
                                            widget.theme.primaryTextHoverColor;
                                      });
                                    }
                                  },
                                  onExit: (_) {
                                    if (!isSelected) {
                                      setState(() {
                                        _languageHoverColors[language['code']!] =
                                            widget.theme.primary;
                                      });
                                    }
                                  },
                                  child: GestureDetector(
                                    onTap: () {
                                      if (language['code'] !=
                                          currentLanguageCode) {
                                        languageProvider.changeLanguage(
                                          language['code']!,
                                        );
                                        setState(() {
                                          _isLanguageSelectorExpanded = false;
                                          _languageHoverColors.clear();
                                          _currentLanguageHoverColor = null;
                                        });
                                      }
                                    },
                                    child: AnimatedContainer(
                                      duration: _animationDuration,
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12.0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? widget
                                                  .theme
                                                  .primaryTextSelectedColor
                                            : _languageHoverColors[language['code']] ??
                                                  widget.theme.primary,
                                        borderRadius: borderRadius,
                                      ),
                                      child: Row(
                                        children: [
                                          // 语言名称和本地名称紧挨着显示
                                          Expanded(
                                            child: RichText(
                                              overflow: TextOverflow.ellipsis,
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text:
                                                        language['nativeName']!,
                                                    style: TextStyle(
                                                      color: widget
                                                          .theme
                                                          .textColorPrimary,
                                                      fontWeight: isSelected
                                                          ? FontWeight.bold
                                                          : FontWeight.w600,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text:
                                                        " (${language['name']!})",
                                                    style: TextStyle(
                                                      color: widget
                                                          .theme
                                                          .textColorTertiary,
                                                      fontSize: 11,
                                                      fontWeight: isSelected
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (isSelected)
                                            Icon(
                                              Icons.check,
                                              size: 16,
                                              color:
                                                  widget.theme.textColorPrimary,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
