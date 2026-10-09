/*
 * @Description: 构建品牌侧栏、主页设备入口、账号入口和保留状态的内容页。
 * @Author: LILYGO_L
 * @Date: 2025-11-06 14:22:51
 * @LastEditTime: 2026-10-08 18:14:00
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
import '../../../core/widgets/retained_page_stack.dart';
import '../../../features/devices/presentation/catalog.dart';
import '../../../features/devices/presentation/pages/add_page.dart';
import '../../../features/devices/presentation/pages/connected_page.dart';
import '../../../features/devices/presentation/widgets/device_page_frame.dart';
import '../../../features/devices/state/manager_provider.dart';
import '../../navigation/provider.dart';
import '../state/provider.dart';
import '../widgets/resizable_sidebar.dart';
import '../widgets/sidebar_account_button.dart';
import '../widgets/sidebar_navigation_item.dart';
import 'home_page_content.dart';

/// 应用主外壳。
///
/// 左侧保留全局导航，设备从主页卡片进入独立详情页。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final Map<String, ValueNotifier<bool>> _nestedDeviceViews = {};
  final Map<String, ValueNotifier<String?>> _devicePageTitles = {};

  ValueNotifier<bool> _nestedViewFor(String deviceId) =>
      _nestedDeviceViews.putIfAbsent(deviceId, () => ValueNotifier(false));

  ValueNotifier<String?> _devicePageTitleFor(String deviceId) =>
      _devicePageTitles.putIfAbsent(deviceId, () => ValueNotifier(null));

  @override
  void dispose() {
    for (final notifier in _nestedDeviceViews.values) {
      notifier.dispose();
    }
    for (final title in _devicePageTitles.values) {
      title.dispose();
    }
    super.dispose();
  }

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
        context.watch<AppNavigationProvider>().contentPage == AppPage.addDevice;
    final selectedIndex = context.select<AppShellProvider, int>(
      (provider) => provider.selectedIndex,
    );

    return ResizableSidebar(
      sidebar: _buildLeftSidebar(
        context,
        isOverview: !addingDevice && selectedIndex == 0,
      ),
      content: Container(
        decoration: BoxDecoration(
          color: theme.secondary,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
        ),
        child: RetainedPageStack(
          activeKey: addingDevice
              ? AppPage.addDevice
              : selectedIndex > 0 &&
                    selectedIndex <= deviceManager.addedDevices.length
              ? deviceManager.addedDevices[selectedIndex - 1]
              : AppPage.home,
          pages: {
            AppPage.home: const HomePageContent(),
            for (final name in deviceManager.addedDevices)
              name: _buildDevicePage(
                name,
                active:
                    !addingDevice &&
                    selectedIndex ==
                        deviceManager.addedDevices.indexOf(name) + 1,
              ),
            if (addingDevice) AppPage.addDevice: const AddDevicePage(),
          },
        ),
      ),
    );
  }

  Widget _buildDevicePage(String name, {required bool active}) {
    final nestedView = _nestedViewFor(name);
    final pageTitle = _devicePageTitleFor(name);
    return DevicePageFrame(
      active: active,
      pageTitle: pageTitle,
      onBack: () {
        if (nestedView.value) {
          nestedView.value = false;
        } else {
          _selectItem(0);
        }
      },
      child: context.read<DeviceManagerProvider>().lanDevice(name) != null
          ? ConnectedDevicePage(
              deviceId: name,
              nestedView: nestedView,
              pageTitle: pageTitle,
            )
          : DevicePresentationCatalog.pageFor(name),
    );
  }

  Widget _buildLeftSidebar(BuildContext context, {required bool isOverview}) {
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
            isSelected: true,
            disableWhenSelected: isOverview,
          ),
          const Spacer(),
          const SidebarAccountButton(),
        ],
      ),
    );
  }
}
