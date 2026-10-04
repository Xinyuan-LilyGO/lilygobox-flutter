/*
 * @Description: 构建 T-Glasses-P4 设备导航、页面分栏及连接状态展示。
 * @Author: LILYGO_L
 * @Date: 2025-11-17 13:38:52
 * @LastEditTime: 2026-10-04 13:10:34
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../../app/navigation/provider.dart';
import '../../../../../core/context_menu/right_click_menu.dart';
import '../../../../../core/l10n/language_provider.dart';
import '../../../../../core/layout/split_view_provider.dart';
import '../../../../../core/theme/provider.dart';
import '../../../../../core/widgets/interaction_decoration.dart';
import '../../../../../core/widgets/resizable_split_view.dart';
import '../../../../../core/widgets/retained_page_stack.dart';
import '../../../domain/catalog.dart';
import '../../domain/connection_status.dart';
import '../widgets/right_click_menu.dart';
import '../widgets/settings_content.dart';
import 'control_center_page.dart';
import 'default_page.dart';
import 'start_page.dart';

// T-Glasses-P4 板子页面内容
class DevicePageContentTGlassesP4 extends StatefulWidget {
  const DevicePageContentTGlassesP4({super.key});

  @override
  State<DevicePageContentTGlassesP4> createState() =>
      _DevicePageContentTGlassesP4State();
}

class _DevicePageContentTGlassesP4State
    extends State<DevicePageContentTGlassesP4> {
  // 默认选中的菜单项 Key
  String _selectedTitleKey = 'start';
  // 记录悬停状态，颜色由当前主题逐帧计算
  final Map<String, bool> _hoveredItems = {};

  // 用于存储分类的折叠状态 - 初始全部折叠
  final Map<String, bool> _collapsedCategories = {'configuration': true};

  // 用于存储分类标题的悬停状态
  final Map<String, bool> _hoveredHeaders = {};

  // 动画持续时间
  final Duration _animationDuration = const Duration(milliseconds: 150);

  // 右键菜单控制器
  final RightClickMenuController _menuController = RightClickMenuController();

  void _handleDelete() {
    // 处理删除逻辑
    debugPrint('删除 T-Glasses-P4');
    _menuController.close(); // 确保菜单关闭
    // TODO(lilygo): 实现删除功能
  }

  void _handleDeviceSettings() {
    // 处理板子设置逻辑
    debugPrint('打开 T-Glasses-P4 板子设置');
    _menuController.close(); // 确保菜单关闭

    context.read<AppNavigationProvider>().openDeviceSettings(
      DeviceCatalog.tGlassesP4Name,
    );
  }

  void _connectToDevice() {
    // TODO(lilygo): 接入真实设备连接，并根据通信结果更新连接状态。
  }

  void _disconnectDevice() {
    // TODO(lilygo): 接入真实设备断开连接。
  }

  void _pair() {
    // TODO(lilygo): 接入真实设备配对。
  }

  void _refresh() {
    // TODO(lilygo): 从设备读取最新连接状态和数据。
  }

  @override
  void initState() {
    super.initState();
    // 启用此窗口的右键菜单
    _menuController.enable();
  }

  @override
  void dispose() {
    _menuController.close();
    super.dispose();
  }

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
        'key': 'start',
        'icon': Symbols.borg,
      },
      {
        'type': 'standalone_item',
        'title': context.l10n.controlCenter,
        'key': 'control_center',
        'icon': Symbols.dashboard,
      },
      {'type': 'header', 'title': "配置", 'key': 'config_header'},
      {
        'type': 'item',
        'title': "设备设置",
        'key': 'device_settings',
        'icon': Symbols.settings,
      },
    ];
  }

  // 根据选中的key获取对应的右侧内容
  Widget _buildRightContent(String selectedKey, BuildContext context) {
    switch (selectedKey) {
      case 'start':
        return const TGlassesP4PageStart();
      case 'control_center':
        return TGlassesP4PageControlCenter(
          connectionStatus: ConnectionStatus.unpaired,
          onConnect: _connectToDevice,
          onDisconnect: _disconnectDevice,
          onPair: _pair,
          onRefresh: _refresh,
        );
      case 'device_settings':
        return const TGlassesP4PageDeviceSettings();
      // 已删除显示配置和网络设置 case
      default:
        return const TGlassesP4PageDefault();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;
    final splitViewProvider = context.watch<SplitViewProvider>();

    final menuItems = _getMenuItems(context);

    // 构建菜单项的回调
    final menuItemsList = TGlassesP4RightClickMenu.getMenuItems(
      context: context,
      onDeviceSettings: _handleDeviceSettings,
      onDelete: _handleDelete,
    );

    // 左侧面板内容
    final leftPanelContent = Container(
      color: theme.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 - 使用 MenuAnchor 实现右键菜单
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
            child: RightClickMenuBuilder.buildMenuAnchor(
              context: context,
              controller: _menuController,
              menuItems: menuItemsList,
              theme: theme,
              onSecondaryTapDown: () {
                // 可以在这里添加额外的处理逻辑
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.contextMenu,
                child: Text(
                  "T-Glasses-P4",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.textColorPrimary,
                  ),
                ),
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
                    final targetColor = (_hoveredHeaders[headerKey] ?? false)
                        ? theme.secondaryTextHoverColor
                        : theme.secondary;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5.0,
                        vertical: 2.0,
                      ),
                      child: InteractionDecoration.color(
                        palette: theme,
                        color: targetColor,
                        builder: (context, color) {
                          return SizedBox(
                            height: 25.0,
                            child: InkWell(
                              hoverColor: Colors.transparent,
                              onHover: (isHovering) {
                                setState(() {
                                  _hoveredHeaders[headerKey] = isHovering;
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
                        : (_hoveredItems[key] ?? false)
                        ? theme.secondaryTextHoverColor
                        : theme.secondary;

                    return Container(
                      margin: const EdgeInsets.only(
                        left: 10.0,
                        top: 2.0,
                        right: 15.0,
                        bottom: 2.0,
                      ),
                      child: SizedBox(
                        height: 30.0,
                        child: InteractionDecoration.color(
                          palette: theme,
                          color: targetColor,
                          builder: (context, color) {
                            return InkWell(
                              hoverColor: Colors.transparent,
                              onHover: (isHovering) {
                                if (!isSelected) {
                                  setState(() {
                                    _hoveredItems[key] = isHovering;
                                  });
                                }
                              },
                              onTap: () {
                                setState(() {
                                  _selectedTitleKey = key;
                                  _hoveredItems.updateAll((k, value) => false);
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
                        : (_hoveredItems[key] ?? false)
                        ? theme.secondaryTextHoverColor
                        : theme.secondary;

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
                          child: InteractionDecoration.color(
                            palette: theme,
                            color: targetColor,
                            builder: (context, color) {
                              return InkWell(
                                hoverColor: Colors.transparent,
                                onHover: (isHovering) {
                                  if (!isSelected) {
                                    setState(() {
                                      _hoveredItems[key] = isHovering;
                                    });
                                  }
                                },
                                onTap: () {
                                  setState(() {
                                    _selectedTitleKey = key;
                                    _hoveredItems.updateAll(
                                      (k, value) => false,
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
      child: RetainedPageStack(
        activeKey: _selectedTitleKey,
        pages: {
          for (final item in menuItems)
            if (item['type'] == 'item' || item['type'] == 'standalone_item')
              item['key'] as String: _buildRightContent(
                item['key'] as String,
                context,
              ),
        },
      ),
    );

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
