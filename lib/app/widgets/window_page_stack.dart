/*
 * @Description: 根据导航状态切换主窗口外壳、设置及设备设置页面。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-02 13:35:30
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/devices/presentation/catalog.dart';
import '../../features/settings/presentation/pages/page.dart';
import '../navigation/provider.dart';
import '../shell/pages/page.dart';

/// 主窗口内容栈。
///
/// 添加设备由主外壳内容区承载，设置页面覆盖主外壳。
class WindowPageStack extends StatelessWidget {
  const WindowPageStack({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppNavigationProvider>(
      builder: (context, navigationProvider, child) {
        final currentPage = navigationProvider.currentPage;

        // 设置页和设备设置页替换主外壳，添加设备时保留侧栏。
        final isStandalonePage =
            currentPage == AppPage.settings ||
            currentPage == AppPage.deviceSettings;
        final basePageKey = isStandalonePage ? currentPage : AppPage.home;

        // base page 负责主内容切换动画，保留主外壳内部选择状态。
        final baseContent = AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final key = (child.key as ValueKey<AppPage>).value;

            if (key == AppPage.settings || key == AppPage.deviceSettings) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 1.0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              );
            }

            return FadeTransition(opacity: animation, child: child);
          },
          child: SizedBox.expand(
            key: ValueKey(basePageKey),
            child: _buildBasePage(basePageKey, navigationProvider),
          ),
        );

        return Expanded(child: baseContent);
      },
    );
  }

  // 将导航枚举映射到具体页面组件。
  // 新增顶层页面时优先在这里注册，保持导航入口集中。
  Widget _buildBasePage(AppPage pageKey, AppNavigationProvider navigation) {
    switch (pageKey) {
      case AppPage.settings:
        return const SettingsPage();
      case AppPage.deviceSettings:
        return DevicePresentationCatalog.settingsPageFor(
          navigation.settingsDeviceName!,
          onClose: navigation.goHome,
        );
      case AppPage.home:
      default:
        return const AppShell();
    }
  }
}
