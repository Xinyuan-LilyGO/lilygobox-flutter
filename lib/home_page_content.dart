import 'package:LilygoBox/provider/language_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'provider/theme_provider.dart';
import 'provider/home_page_provider.dart';

// 主页内容 (改为 StatefulWidget 以支持列表的 State)
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

  // 用于存储分类的折叠状态 - 初始全部折叠
  final Map<String, bool> _collapsedCategories = {
    'my': true, // 默认折叠
    'navigation': true, // 默认折叠
  };

  // 用于存储分类标题的悬停状态
  final Map<String, Color> _headerHoverColors = {};

  // 动画持续时间
  final Duration _animationDuration = const Duration(milliseconds: 150);

  // 获取一个 item 所属的 header key
  String? _getHeaderKeyForItemKey(String itemKey) {
    String? currentHeaderKey;
    // 从头遍历，找到 itemKey 所属的最近一个 header
    for (final item in _getMenuItems(context)) {
      if (item['type'] == 'header') {
        currentHeaderKey = item['key'];
      } else if ((item['type'] == 'item' ||
              item['type'] == 'standalone_item') &&
          item['key'] == itemKey) {
        return currentHeaderKey;
      }
    }
    return null;
  }

  // 判断一个 item 是否属于折叠的分类（用于动画）
  bool _isItemInCollapsedCategory(int currentIndex, BuildContext context) {
    String? currentHeaderKey;
    bool isCollapsed = true;

    final menuItems = _getMenuItems(context);

    // 遍历到当前索引，找到它所属的最近一个 header 的状态
    for (int i = 0; i < currentIndex; i++) {
      final item = menuItems[i];
      if (item['type'] == 'header') {
        currentHeaderKey = item['key'];
        isCollapsed = _collapsedCategories[currentHeaderKey] ?? true;
      }
    }

    final item = menuItems[currentIndex];

    // 对于 standalone_item 类型，永远不折叠
    if (item['type'] == 'standalone_item') {
      return false;
    }

    // 对于 item 类型，检查是否在折叠的分类中且不是选中项
    if (item['type'] == 'item') {
      final isSelected = item['key'] == _selectedTitleKey;
      return isCollapsed && !isSelected;
    }

    return false;
  }

  // 切换分类的折叠状态 - 所有分类都可以自由折叠
  void _toggleCollapse(String headerKey) {
    setState(() {
      final isCurrentlyCollapsed = _collapsedCategories[headerKey] ?? true;
      // 直接切换状态，不检查是否包含选中项
      _collapsedCategories[headerKey] = !isCurrentlyCollapsed;
    });
  }

  // 获取菜单项列表
  List<Map<String, dynamic>> _getMenuItems(BuildContext context) {
    return [
      // 没有header的"开始"item，放在最前面
      {
        'type': 'standalone_item',
        'title': context.l10n.start,
        'key': 'start',
        'icon': Symbols.borg,
      },
      // 增加 'key' 字段以便更清晰地管理 header 状态
      {'type': 'header', 'title': "my", 'key': 'my_header'},
      {
        'type': 'item',
        'title': "personalSettings",
        'key': 'settings',
        'icon': Symbols.border_all,
      },
      {
        'type': 'item',
        'title': "preferences",
        'key': 'preferences',
        'icon': Symbols.border_all,
      },
      {'type': 'header', 'title': "navigation", 'key': 'nav_header'},
      {
        'type': 'item',
        'title': "workspace",
        'key': 'workspace',
        'icon': Symbols.border_all,
      },
      {
        'type': 'item',
        'title': "fileExplorer",
        'key': 'file_explorer',
        'icon': Symbols.border_all,
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
      case 'settings':
        return _buildSettingsContent(theme, context);
      case 'preferences':
        return _buildPreferencesContent(theme, context);
      case 'workspace':
        return _buildWorkspaceContent(theme, context);
      case 'file_explorer':
        return _buildFileExplorerContent(theme, context);
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
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
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
        ),
      ],
    );
  }

  // 个人设置页面内容
  Widget _buildSettingsContent(AppTheme theme, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
          child: Text(
            "个人设置",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          child: Card(
            color: theme.secondary,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "账户设置",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildSettingItem(theme, "用户名", "user123"),
                  _buildSettingItem(theme, "邮箱", "user@example.com"),
                  _buildSettingItem(theme, "语言", "简体中文"),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 偏好设置页面内容
  Widget _buildPreferencesContent(AppTheme theme, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
          child: Text(
            "偏好设置",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          child: Card(
            color: theme.secondary,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "应用偏好",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildSettingItem(theme, "主题", "深色"),
                  _buildSettingItem(theme, "字体大小", "中等"),
                  _buildSettingItem(theme, "自动保存", "开启"),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 工作空间页面内容
  Widget _buildWorkspaceContent(AppTheme theme, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
          child: Text(
            "工作空间",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              _buildWorkspaceCard(theme, "项目 A", Icons.folder),
              _buildWorkspaceCard(theme, "项目 B", Icons.folder),
              _buildWorkspaceCard(theme, "项目 C", Icons.folder),
              _buildWorkspaceCard(theme, "新建项目", Icons.create_new_folder),
            ],
          ),
        ),
      ],
    );
  }

  // 文件浏览器页面内容
  Widget _buildFileExplorerContent(AppTheme theme, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
          child: Text(
            "文件浏览器",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          child: Card(
            color: theme.secondary,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "最近文件",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildFileItem(theme, "document.pdf", Icons.picture_as_pdf),
                  _buildFileItem(theme, "image.png", Icons.image),
                  _buildFileItem(theme, "data.csv", Icons.table_chart),
                ],
              ),
            ),
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

  // 构建设置项
  Widget _buildSettingItem(AppTheme theme, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: theme.textColorSecondary)),
          Text(
            value,
            style: TextStyle(
              color: theme.textColorPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // 构建工作空间卡片
  Widget _buildWorkspaceCard(AppTheme theme, String title, IconData icon) {
    return Card(
      color: theme.primary,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: theme.textColorPrimary),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: theme.textColorPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建文件项
  Widget _buildFileItem(AppTheme theme, String fileName, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.textColorSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              style: TextStyle(color: theme.textColorSecondary),
            ),
          ),
          Icon(Icons.more_vert, size: 16, color: theme.textColorTertiary),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取主题数据
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    // 获取 HomePageProvider
    final homePageProvider = Provider.of<HomePageProvider>(
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

                  // 处理 Header
                  if (item['type'] == 'header') {
                    // 分类标题
                    final headerTitle = item['title'] as String;
                    final headerKey = item['key'] as String;
                    final isCollapsed = _collapsedCategories[headerKey] ?? true;

                    // 检查当前分类是否包含选中项（仅用于视觉提示）
                    final selectedItemHeader = _getHeaderKeyForItemKey(
                      _selectedTitleKey,
                    );
                    final containsSelectedItem =
                        selectedItemHeader == headerKey;

                    // 计算目标背景色
                    final targetColor =
                        _headerHoverColors[headerKey] ?? theme.secondary;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5.0,
                        vertical: 2.0,
                      ),
                      // 使用 TweenAnimationBuilder 实现颜色渐变
                      child: TweenAnimationBuilder<Color?>(
                        duration: const Duration(milliseconds: 150),
                        tween: ColorTween(
                          begin: theme.secondary,
                          end: targetColor,
                        ),
                        builder: (context, color, child) {
                          return SizedBox(
                            height: 25.0,
                            child: InkWell(
                              onHover: (isHovering) {
                                setState(() {
                                  _headerHoverColors[headerKey] = isHovering
                                      ? theme.secondaryTextHoverColor
                                      : theme.secondary;
                                });
                              },
                              onTap: () => _toggleCollapse(headerKey),
                              borderRadius: BorderRadius.circular(20.0),
                              child: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3.0,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    // 折叠图标添加旋转动画
                                    AnimatedRotation(
                                      turns: isCollapsed
                                          ? 0.0
                                          : 0.25, // 0° 和 90°
                                      duration: _animationDuration,
                                      curve: Curves.easeInOut,
                                      child: Icon(
                                        Icons.chevron_right,
                                        size: 20,
                                        color: containsSelectedItem
                                            ? theme
                                                  .textColorPrimary // 包含选中项时使用主色
                                            : theme.textColorTertiary,
                                      ),
                                    ),
                                    // 分类文本
                                    Expanded(
                                      child: Text(
                                        headerTitle,
                                        style: TextStyle(
                                          color: containsSelectedItem
                                              ? theme
                                                    .textColorPrimary // 包含选中项时使用主色提示
                                              : theme.textColorTertiary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }

                  //处理 standalone_item (新增类型)
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
                        top: 5.0,
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

                  // 处理普通 Item
                  if (item['type'] == 'item') {
                    final title = item['title'] as String;
                    final key = item['key'] as String;
                    final isSelected = key == _selectedTitleKey;
                    final isCollapsed = _isItemInCollapsedCategory(
                      index,
                      context,
                    );
                    final icon = item['icon'] as IconData?;

                    // 计算目标背景色
                    final targetColor = isSelected
                        ? theme.secondaryTextSelectedColor
                        : _currentHoverColors[key] ?? theme.secondary;

                    // 使用 AnimatedContainer 控制高度和边距
                    return AnimatedContainer(
                      duration: _animationDuration,
                      curve: Curves.easeInOut,
                      height: isCollapsed ? 0 : 30.0,
                      margin: EdgeInsets.symmetric(
                        horizontal: 15.0,
                        vertical: isCollapsed ? 0 : 2.0,
                      ),
                      child: AnimatedOpacity(
                        duration: _animationDuration,
                        opacity: isCollapsed ? 0 : 1.0,
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
                                      if (icon != null)
                                        const SizedBox(width: 3),
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

    // 使用 ClipRRect 确保 SplitViewTemplate 遵循外部 Container 的圆角
    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
      // 使用自定义的可拖动分界线视图
      child: SplitViewTemplate(
        leftColor: theme.secondary,
        rightColor: theme.tertiary,
        // 左边内容使用新的 Column 布局
        leftWidget: leftPanelContent,
        // 右边内容使用带动画切换的内容
        rightWidget: rightPanelContent,
        initialWidth: homePageProvider.splitWidth,
      ),
    );
  }
}

// 可拖动的分界线组件 (保持不变)
class SplitViewTemplate extends StatefulWidget {
  const SplitViewTemplate({
    super.key,
    required this.leftWidget,
    required this.rightWidget,
    required this.leftColor,
    required this.rightColor,

    this.initialWidth = 300.0,
  });

  final Widget leftWidget;
  final Widget rightWidget;
  final Color leftColor;
  final Color rightColor;
  final double initialWidth; // 初始左侧面板的绝对宽度

  @override
  State<SplitViewTemplate> createState() => _SplitViewTemplateState();
}

class _SplitViewTemplateState extends State<SplitViewTemplate> {
  // 存储左侧面板的绝对宽度
  late double _leftPanelWidth;

  // 左侧面板的宽度限制
  static const double _minLeftWidth = 100.0;
  static const double _maxLeftWidthFactor = 0.4; // 左侧最大总宽度的百分比

  // 视觉和触摸常量
  static const double _dividerVisualWidth = 0.0;
  static const double _touchTargetWidth = 5.0;

  @override
  void initState() {
    super.initState();
    _leftPanelWidth = widget.initialWidth;
  }

  // 处理拖动更新
  void _handlePanUpdate(
    DragUpdateDetails details,
    double totalWidth,
    HomePageProvider homePageProvider,
  ) {
    setState(() {
      double newWidth = _leftPanelWidth + details.delta.dx;

      // 在拖动时也需要限制，以防止拖动到无效区域
      final double maxLeftWidth =
          totalWidth * _maxLeftWidthFactor - _touchTargetWidth;

      _leftPanelWidth = newWidth.clamp(_minLeftWidth, maxLeftWidth);

      // 更新状态管理中的宽度值
      homePageProvider.updateSplitWidth(_leftPanelWidth);
    });
  }

  @override
  Widget build(BuildContext context) {
    final homePageProvider = Provider.of<HomePageProvider>(
      context,
      listen: false,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double totalWidth = constraints.maxWidth;

        // 计算最大允许的左侧宽度（考虑总宽度变化）
        final double maxLeftWidth =
            totalWidth * _maxLeftWidthFactor - _touchTargetWidth;

        // 在布局时校正 _leftPanelWidth
        _leftPanelWidth = _leftPanelWidth.clamp(_minLeftWidth, maxLeftWidth);

        // 宽度计算
        final double leftWidgetWidth = _leftPanelWidth;
        final double rightWidgetWidth =
            totalWidth - leftWidgetWidth - _dividerVisualWidth;

        // 确保左右宽度都是有效的（非负）
        final double safeLeftWidth = leftWidgetWidth.clamp(0.0, totalWidth);
        final double safeRightWidth = rightWidgetWidth.clamp(0.0, totalWidth);

        return Stack(
          // 使用 Stack 来叠加拖动热区
          children: <Widget>[
            // 底层：Row 布局，紧密排列左侧、视觉分割线和右侧
            Row(
              children: <Widget>[
                // 左侧面板 (使用绝对宽度)
                SizedBox(width: safeLeftWidth, child: widget.leftWidget),

                // 视觉分割线：一个独立的、可见的 Container
                Container(
                  width: _dividerVisualWidth,
                  height: constraints.maxHeight,
                  color: Colors.white, // 可以使用一个主题色，并调整透明度
                ),

                // 右侧面板 (使用计算出的剩余宽度)
                SizedBox(width: safeRightWidth, child: widget.rightWidget),
              ],
            ),

            // 顶层：定位的 GestureDetector 拖动热区
            Positioned(
              left:
                  safeLeftWidth -
                  (_touchTargetWidth / 2) +
                  (_dividerVisualWidth / 2), // 精确计算定位
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent, // 确保透明区域也能接收事件
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: _touchTargetWidth,
                    height: constraints.maxHeight,
                    color: Colors.transparent, // 必须透明，但占据空间
                  ),
                ),
                onPanUpdate: (details) =>
                    _handlePanUpdate(details, totalWidth, homePageProvider),
              ),
            ),
          ],
        );
      },
    );
  }
}
