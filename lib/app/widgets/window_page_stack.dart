import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/devices/presentation/pages/add_device_page.dart';
import '../../features/devices/t_glasses_p4/presentation/pages/device_settings_t_glasses_p4.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../navigation/app_navigation_provider.dart';
import '../shell/pages/app_shell.dart';

/// 主窗口内容栈。
///
/// 普通页面以 base page 的形式切换；“添加设备”作为模态层叠在当前页面之上。
class WindowPageStack extends StatelessWidget {
  const WindowPageStack({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppNavigationProvider>(
      builder: (context, navigationProvider, child) {
        final currentPage = navigationProvider.currentPage;

        // 设置页和设备设置页会替换主内容区域；添加设备页则保持主页在底层。
        final isStandalonePage =
            currentPage == AppPage.settings ||
            currentPage == AppPage.deviceSettings;
        final basePageKey = isStandalonePage ? currentPage : AppPage.home;

        // base page 负责主内容切换动画，避免弹层状态影响主页内部选择状态。
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
            child: _buildBasePage(basePageKey),
          ),
        );

        // 模态遮罩和模态内容分开做动画，便于以后调整遮罩透明度或弹层动效。
        final modalBarrier = AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: currentPage == AppPage.addDevice
              ? const ModalBarrier(
                  key: ValueKey('modal_barrier_active'),
                  color: Color.fromARGB(100, 0, 0, 0),
                )
              : Container(key: const ValueKey('modal_barrier_inactive')),
        );

        final modalContent = AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
          child: currentPage == AppPage.addDevice
              ? const AddDevicePage(key: ValueKey(AppPage.addDevice))
              : Container(key: const ValueKey('empty_modal_content')),
        );

        return Expanded(
          child: Stack(
            children: [
              baseContent,
              modalBarrier,
              modalContent,
            ],
          ),
        );
      },
    );
  }

  /// 将导航枚举映射到具体页面组件。
  ///
  /// 新增顶层页面时优先在这里注册，保持导航入口集中。
  Widget _buildBasePage(AppPage pageKey) {
    switch (pageKey) {
      case AppPage.settings:
        return const SettingsPage();
      case AppPage.deviceSettings:
        return const DeviceSettingsTGlassesP4();
      case AppPage.home:
      default:
        return const AppShell();
    }
  }
}
