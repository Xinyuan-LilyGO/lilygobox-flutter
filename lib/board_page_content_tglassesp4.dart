/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-17 13:38:52
 * @LastEditTime: 2025-11-18 13:58:02
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'provider/theme_provider.dart';
import 'provider/home_page_provider.dart';
import 'provider/language_provider.dart';

// T-Glasses-P4 板子页面内容
class BoardPageContentTGlassesP4 extends StatefulWidget {
  const BoardPageContentTGlassesP4({super.key});

  @override
  State<BoardPageContentTGlassesP4> createState() =>
      _BoardPageContentTGlassesP4State();
}

class _BoardPageContentTGlassesP4State
    extends State<BoardPageContentTGlassesP4> {
  // 默认选中的菜单项 Key
  String _selectedTitleKey = 'overview';
  // 用于存储当前悬停颜色状态的 Map
  final Map<String, Color> _currentHoverColors = {};

  // 用于存储分类的折叠状态 - 初始全部折叠
  final Map<String, bool> _collapsedCategories = {'configuration': true};

  // 用于存储分类标题的悬停状态
  final Map<String, Color> _headerHoverColors = {};

  // 动画持续时间
  final Duration _animationDuration = const Duration(milliseconds: 150);

  // 获取一个 item 所属的 header key
  String? _getHeaderKeyForItemKey(String itemKey) {
    String? currentHeaderKey;
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

    for (int i = 0; i < currentIndex; i++) {
      final item = menuItems[i];
      if (item['type'] == 'header') {
        currentHeaderKey = item['key'];
        isCollapsed = _collapsedCategories[currentHeaderKey] ?? true;
      }
    }

    final item = menuItems[currentIndex];

    if (item['type'] == 'standalone_item') {
      return false;
    }

    if (item['type'] == 'item') {
      final isSelected = item['key'] == _selectedTitleKey;
      return isCollapsed && !isSelected;
    }

    return false;
  }

  // 切换分类的折叠状态
  void _toggleCollapse(String headerKey) {
    setState(() {
      final isCurrentlyCollapsed = _collapsedCategories[headerKey] ?? true;
      _collapsedCategories[headerKey] = !isCurrentlyCollapsed;
    });
  }

  // 获取 T-Glasses-P4 特定的菜单项列表
  List<Map<String, dynamic>> _getMenuItems(BuildContext context) {
    return [
      {
        'type': 'standalone_item',
        'title': context.l10n.start,
        'key': 'overview',
        'icon': Symbols.borg,
      },
      {'type': 'header', 'title': "配置", 'key': 'config_header'},
      {
        'type': 'item',
        'title': "设备设置",
        'key': 'device_settings',
        'icon': Symbols.settings,
      },
      {
        'type': 'item',
        'title': "显示配置",
        'key': 'display_config',
        'icon': Symbols.display_settings,
      },
      {
        'type': 'item',
        'title': "网络设置",
        'key': 'network_settings',
        'icon': Symbols.network_wifi,
      },
    ];
  }

  // 根据选中的key获取对应的右侧内容
  Widget _buildRightContent(String selectedKey, BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    switch (selectedKey) {
      case 'overview':
        return _buildOverviewContent(theme, context);
      case 'device_settings':
        return _buildDeviceSettingsContent(theme, context);
      case 'display_config':
        return _buildDisplayConfigContent(theme, context);
      case 'network_settings':
        return _buildNetworkSettingsContent(theme, context);
      default:
        return _buildDefaultContent(theme, context);
    }
  }

  // 概览页面内容
  Widget _buildOverviewContent(AppTheme theme, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 50),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 50.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 板子图标和名称
              Icon(
                Symbols.developer_board_rounded,
                size: 64,
                color: theme.textColorPrimary,
              ),
              const SizedBox(height: 16),
              Text(
                "T-Glasses-P4",
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: theme.textColorPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                "智能眼镜开发板",
                style: TextStyle(fontSize: 16, color: theme.textColorSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),

              // 状态卡片网格
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 2.5,
                children: [
                  _buildStatusCard(
                    theme,
                    "连接状态",
                    "已连接",
                    Symbols.check_circle,
                    Colors.green,
                  ),
                  _buildStatusCard(
                    theme,
                    "固件版本",
                    "v1.2.3",
                    Symbols.info,
                    theme.textColorPrimary,
                  ),
                  _buildStatusCard(
                    theme,
                    "电池电量",
                    "85%",
                    Symbols.battery_5_bar,
                    Colors.blue,
                  ),
                  _buildStatusCard(
                    theme,
                    "温度",
                    "32°C",
                    Symbols.thermostat,
                    Colors.orange,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 设备设置页面内容
  Widget _buildDeviceSettingsContent(AppTheme theme, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
          child: Text(
            "设备设置",
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
                    "基本设置",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildSettingItem(theme, "设备名称", "T-Glasses-P4"),
                  _buildSettingItem(theme, "设备ID", "TGLS-P4-20241117"),
                  _buildSettingItem(theme, "硬件版本", "Rev 2.1"),
                  _buildSettingItem(theme, "启动模式", "正常启动"),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 显示配置页面内容
  Widget _buildDisplayConfigContent(AppTheme theme, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
          child: Text(
            "显示配置",
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
                    "显示参数",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildSettingItem(theme, "分辨率", "1280x720"),
                  _buildSettingItem(theme, "刷新率", "60Hz"),
                  _buildSettingItem(theme, "亮度", "75%"),
                  _buildSettingItem(theme, "色彩模式", "sRGB"),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 网络设置页面内容
  Widget _buildNetworkSettingsContent(AppTheme theme, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
          child: Text(
            "网络设置",
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
                    "网络状态",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildSettingItem(theme, "WiFi连接", "已连接"),
                  _buildSettingItem(theme, "IP地址", "192.168.1.105"),
                  _buildSettingItem(theme, "信号强度", "良好"),
                  _buildSettingItem(theme, "蓝牙", "已开启"),
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

  // 构建状态卡片
  Widget _buildStatusCard(
    AppTheme theme,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      color: theme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textColorTertiary,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textColorPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;
    final homePageProvider = Provider.of<HomePageProvider>(
      context,
      listen: false,
    );

    final menuItems = _getMenuItems(context);

    // 左侧面板内容
    final leftPanelContent = Container(
      color: theme.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
            child: Text(
              "T-Glasses-P4",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textColorPrimary,
              ),
            ),
          ),

          // 分割线
          Divider(color: theme.dividerColorNormal, height: 1, thickness: 2),

          // 菜单列表
          Expanded(
            child: AnimatedSize(
              duration: _animationDuration,
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 5.0),
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final item = menuItems[index];

                  if (item['type'] == 'header') {
                    final headerTitle = item['title'] as String;
                    final headerKey = item['key'] as String;
                    final isCollapsed = _collapsedCategories[headerKey] ?? true;
                    final selectedItemHeader = _getHeaderKeyForItemKey(
                      _selectedTitleKey,
                    );
                    final containsSelectedItem =
                        selectedItemHeader == headerKey;
                    final targetColor =
                        _headerHoverColors[headerKey] ?? theme.secondary;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5.0,
                        vertical: 2.0,
                      ),
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
                                    AnimatedRotation(
                                      turns: isCollapsed ? 0.0 : 0.25,
                                      duration: _animationDuration,
                                      curve: Curves.easeInOut,
                                      child: Icon(
                                        Icons.chevron_right,
                                        size: 20,
                                        color: containsSelectedItem
                                            ? theme.textColorPrimary
                                            : theme.textColorTertiary,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        headerTitle,
                                        style: TextStyle(
                                          color: containsSelectedItem
                                              ? theme.textColorPrimary
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

                  if (item['type'] == 'standalone_item') {
                    final title = item['title'] as String;
                    final key = item['key'] as String;
                    final isSelected = key == _selectedTitleKey;
                    final icon = item['icon'] as IconData?;
                    final targetColor = isSelected
                        ? theme.secondaryTextSelectedColor
                        : _currentHoverColors[key] ?? theme.secondary;

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

                  if (item['type'] == 'item') {
                    final title = item['title'] as String;
                    final key = item['key'] as String;
                    final isSelected = key == _selectedTitleKey;
                    final isCollapsed = _isItemInCollapsedCategory(
                      index,
                      context,
                    );
                    final icon = item['icon'] as IconData?;
                    final targetColor = isSelected
                        ? theme.secondaryTextSelectedColor
                        : _currentHoverColors[key] ?? theme.secondary;

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

    // 右侧面板内容
    final rightPanelContent = Container(
      color: theme.tertiary,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: Container(
          key: ValueKey(_selectedTitleKey),
          child: _buildRightContent(_selectedTitleKey, context),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
      child: SplitViewTemplate(
        leftColor: theme.secondary,
        rightColor: theme.tertiary,
        leftWidget: leftPanelContent,
        rightWidget: rightPanelContent,
        initialWidth: homePageProvider.splitWidth,
      ),
    );
  }
}

// SplitViewTemplate 组件（从 home_page_content.dart 复制）
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
  final double initialWidth;

  @override
  State<SplitViewTemplate> createState() => _SplitViewTemplateState();
}

class _SplitViewTemplateState extends State<SplitViewTemplate> {
  late double _leftPanelWidth;
  static const double _minLeftWidth = 100.0;
  static const double _maxLeftWidthFactor = 0.4;
  static const double _dividerVisualWidth = 0.0;
  static const double _touchTargetWidth = 5.0;

  @override
  void initState() {
    super.initState();
    _leftPanelWidth = widget.initialWidth;
  }

  void _handlePanUpdate(
    DragUpdateDetails details,
    double totalWidth,
    HomePageProvider homePageProvider,
  ) {
    setState(() {
      double newWidth = _leftPanelWidth + details.delta.dx;
      final double maxLeftWidth =
          totalWidth * _maxLeftWidthFactor - _touchTargetWidth;
      _leftPanelWidth = newWidth.clamp(_minLeftWidth, maxLeftWidth);
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
        final double maxLeftWidth =
            totalWidth * _maxLeftWidthFactor - _touchTargetWidth;
        _leftPanelWidth = _leftPanelWidth.clamp(_minLeftWidth, maxLeftWidth);

        final double leftWidgetWidth = _leftPanelWidth;
        final double rightWidgetWidth =
            totalWidth - leftWidgetWidth - _dividerVisualWidth;
        final double safeLeftWidth = leftWidgetWidth.clamp(0.0, totalWidth);
        final double safeRightWidth = rightWidgetWidth.clamp(0.0, totalWidth);

        return Stack(
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(width: safeLeftWidth, child: widget.leftWidget),
                Container(
                  width: _dividerVisualWidth,
                  height: constraints.maxHeight,
                  color: Colors.white,
                ),
                SizedBox(width: safeRightWidth, child: widget.rightWidget),
              ],
            ),
            Positioned(
              left:
                  safeLeftWidth -
                  (_touchTargetWidth / 2) +
                  (_dividerVisualWidth / 2),
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: _touchTargetWidth,
                    height: constraints.maxHeight,
                    color: Colors.transparent,
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
