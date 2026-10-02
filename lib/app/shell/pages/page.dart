/*
 * @Description: 构建品牌侧栏、设备导航、账号入口和当前页面内容。
 * @Author: LILYGO_L
 * @Date: 2025-11-06 14:22:51
 * @LastEditTime: 2026-10-02 14:08:15
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:vector_graphics/vector_graphics_compat.dart'
    show RenderingStrategy;

import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/provider.dart';
import '../../../features/devices/presentation/catalog.dart';
import '../../../features/devices/presentation/pages/add_page.dart';
import '../../../features/devices/state/manager_provider.dart';
import '../../navigation/provider.dart';
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
    context.read<AppNavigationProvider>().goHome();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;
    final deviceManager = Provider.of<DeviceManagerProvider>(context);
    final addingDevice =
        context.watch<AppNavigationProvider>().currentPage == AppPage.addDevice;
    final selectedIndex = context.select<AppShellProvider, int>(
      (provider) => provider.selectedIndex,
    );

    return ResizableSidebar(
      sidebar: _buildLeftSidebar(
        context,
        deviceManager.addedDevices,
        addingDevice ? 0 : selectedIndex,
        addingDevice: addingDevice,
      ),
      content: Container(
        decoration: BoxDecoration(
          color: theme.secondary,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
        ),
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: addingDevice
              ? const AddDevicePage(key: ValueKey(AppPage.addDevice))
              : _buildCurrentPage(
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
    int selectedIndex, {
    required bool addingDevice,
  }) {
    final theme = context.read<ThemeProvider>().themeData;

    return ColoredBox(
      color: theme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: SvgPicture.asset(
                    'assets/images/branding/lilygobox_logo.svg',
                    width: 44,
                    height: 44,
                    // 按当前尺寸和像素比缓存绘制，避免桌面首帧矢量描边异常。
                    renderingStrategy: RenderingStrategy.raster,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(
                      theme.textColorPrimary,
                      BlendMode.srcIn,
                    ),
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'LilygoBox',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: theme.textColorPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SidebarNavigationItem(
            icon: Symbols.home,
            iconFill: 1,
            iconColor: theme.textColorSecondary,
            label: context.l10n.sidebarHome,
            onPressed: () => _selectItem(0),
            isSelected: selectedIndex == 0,
            disableWhenSelected: !addingDevice,
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
