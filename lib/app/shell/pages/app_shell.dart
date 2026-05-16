/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-06 14:22:51
 * @LastEditTime: 2025-11-20 10:08:41
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_provider.dart';
import '../../../features/devices/presentation/device_presentation_catalog.dart';
import '../../../features/devices/state/device_manager_provider.dart';
import '../../navigation/app_navigation_provider.dart';
import '../state/app_shell_provider.dart';
import '../widgets/sidebar_button.dart';
import 'home_page_content.dart';

/// 应用主外壳。
///
/// 左侧是全局设备导航，右侧根据选中项显示主页或具体设备页面。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  void _selectItem(int index) {
    final shellProvider = Provider.of<AppShellProvider>(
      context,
      listen: false,
    );
    shellProvider.updateSelectedIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;
    final deviceManager = Provider.of<DeviceManagerProvider>(context);
    final shellProvider = Provider.of<AppShellProvider>(
      context,
    );

    return Expanded(
      child: Row(
        children: [
          // 左边侧边栏
          _buildLeftSidebar(
            context,
            deviceManager.addedDevices,
            shellProvider.selectedIndex,
          ),

          // 右边主内容区域
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.secondary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: _buildCurrentPage(
                  context,
                  deviceManager.addedDevices,
                  shellProvider.selectedIndex,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftSidebar(
    BuildContext context,
    List<String> addedDevices,
    int selectedIndex,
  ) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;
    final navigationProvider = Provider.of<AppNavigationProvider>(
      context,
      listen: false,
    );

    return Container(
      width: 65,
      color: theme.primary,
      child: Column(
        children: [
          // 房子按钮
          SidebarButtonTemplate(
            icon: Symbols.home,
            onPressed: () {
              _selectItem(0);
            },
            iconColor: theme.sidebarIconColor,
            iconBackgroundColor: theme.sidebarIconBackgroundColor,
            isSelected: selectedIndex == 0,
            selectedColor: theme.basePrimary,
            hoverColor: theme.sidebarHoverIconColor,
            indicatorColor: theme.sidebarIndicatorColor,
          ),

          //间距
          const SizedBox(height: 5),

          // 分隔线
          Container(
            height: 1.5,
            margin: const EdgeInsets.symmetric(horizontal: 15),
            color: theme.dividerColor,
          ),

          //间距
          const SizedBox(height: 10),

          // 可滚动的板子列表 - 只显示动态添加的板子
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: addedDevices.length,
              itemBuilder: (context, index) {
                final deviceIndex = index + 1; // 从1开始
                final deviceName = addedDevices[index];

                final deviceIcon = DevicePresentationCatalog.iconFor(
                  deviceName,
                );

                return SidebarButtonTemplate(
                  icon: deviceIcon,
                  onPressed: () {
                    _selectItem(deviceIndex);
                  },
                  iconColor: theme.sidebarIconColor,
                  iconBackgroundColor: theme.sidebarIconBackgroundColor,
                  isSelected: selectedIndex == deviceIndex,
                  selectedColor: theme.basePrimary,
                  hoverColor: theme.sidebarHoverIconColor,
                  indicatorColor: theme.sidebarIndicatorColor,
                  showDotIndicator: true, // 板子按钮显示小白点
                );
              },
            ),
          ),

          // 添加板子按钮
          SidebarButtonTemplate(
            icon: Symbols.add,
            onPressed: () {
              navigationProvider.setPage(AppPage.addDevice);
            },
            iconColor: theme.sidebarIconColor,
            iconBackgroundColor: theme.sidebarIconBackgroundColor,
            isSelected: false,
            selectedColor: theme.basePrimary,
            hoverColor: theme.sidebarHoverIconColor2,
            indicatorColor: theme.sidebarIndicatorColor,
            isAddButton: true,
          ),

          //间距
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildCurrentPage(
    BuildContext context,
    List<String> addedDevices,
    int selectedIndex,
  ) {
    // 主页使用索引零；后续索引对应 addedDevices 中的设备顺序。
    if (selectedIndex == 0) {
      return const HomePageContent(key: ValueKey<int>(0));
    }

    // 选中已添加设备时，按设备顺序展示对应页面。
    if (selectedIndex >= 1) {
      final dynamicIndex = selectedIndex - 1;
      if (dynamicIndex < addedDevices.length) {
        final deviceName = addedDevices[dynamicIndex];
        return DevicePresentationCatalog.pageFor(deviceName);
      }
    }

    // 其他值（如 -1 或超出范围）
    return const Center(key: ValueKey<int>(-1), child: Text('页面未找到'));
  }
}
