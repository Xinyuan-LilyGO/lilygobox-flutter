/*
 * @Description: 构建品牌侧栏、设备导航、账号入口和当前页面内容。
 * @Author: LILYGO_L
 * @Date: 2025-11-06 14:22:51
 * @LastEditTime: 2025-11-20 10:08:41
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/provider.dart';
import '../../../features/devices/presentation/catalog.dart';
import '../../../features/devices/state/manager_provider.dart';
import '../state/provider.dart';
import '../widgets/resizable_sidebar.dart';
import '../widgets/sidebar_account_button.dart';
import '../widgets/sidebar_navigation_item.dart';
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
    final shellProvider = Provider.of<AppShellProvider>(context, listen: false);
    shellProvider.updateSelectedIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;
    final deviceManager = Provider.of<DeviceManagerProvider>(context);
    final selectedIndex = context.select<AppShellProvider, int>(
      (provider) => provider.selectedIndex,
    );

    return ResizableSidebar(
      sidebar: _buildLeftSidebar(
        context,
        deviceManager.addedDevices,
        selectedIndex,
      ),
      content: Container(
        decoration: BoxDecoration(
          color: theme.secondary,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _buildCurrentPage(
            context,
            deviceManager.addedDevices,
            selectedIndex,
          ),
        ),
      ),
    );
  }

  Widget _buildLeftSidebar(
    BuildContext context,
    List<String> addedDevices,
    int selectedIndex,
  ) {
    final theme = context.read<ThemeProvider>().themeData;

    return ColoredBox(
      color: theme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 24),
            child: Row(
              children: [
                // 品牌图标暂用正方形占位，后续替换为正式资源。
                Container(width: 28, height: 28, color: theme.basePrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'LilygoBox',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: theme.textColorPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SidebarNavigationItem(
            icon: Symbols.home,
            label: context.l10n.sidebarHome,
            onPressed: () => _selectItem(0),
            isSelected: selectedIndex == 0,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: addedDevices.length,
              itemBuilder: (context, index) {
                final deviceIndex = index + 1;
                final deviceName = addedDevices[index];
                return SidebarNavigationItem(
                  icon: DevicePresentationCatalog.iconFor(deviceName),
                  label: deviceName,
                  onPressed: () => _selectItem(deviceIndex),
                  isSelected: selectedIndex == deviceIndex,
                );
              },
            ),
          ),
          const SidebarAccountButton(),
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
