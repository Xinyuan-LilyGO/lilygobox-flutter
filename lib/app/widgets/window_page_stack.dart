/*
 * @Description: 根据导航状态切换主窗口外壳、设置及设备设置页面。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-03 20:29:43
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/devices/presentation/catalog.dart';
import '../../features/settings/presentation/pages/page.dart';
import '../navigation/provider.dart';
import '../shell/pages/page.dart';

/// 设置覆盖主外壳，关闭后原页面继续使用同一个 State。
class WindowPageStack extends StatefulWidget {
  const WindowPageStack({super.key});

  @override
  State<WindowPageStack> createState() => _WindowPageStackState();
}

class _WindowPageStackState extends State<WindowPageStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  AppPage? _overlay;
  String? _deviceName;

  @override
  Widget build(BuildContext context) {
    final navigation = context.watch<AppNavigationProvider>();
    final current = navigation.currentPage;
    final covered =
        current == AppPage.settings || current == AppPage.deviceSettings;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (covered) {
      _overlay = current;
      _deviceName = navigation.settingsDeviceName;
      if (reducedMotion) {
        _animation.value = 1;
      } else if (_animation.status != AnimationStatus.forward &&
          !_animation.isCompleted) {
        _animation.forward();
      }
    } else if (reducedMotion) {
      _animation.value = 0;
    } else if (_animation.status != AnimationStatus.reverse &&
        !_animation.isDismissed) {
      _animation.reverse();
    }

    return Expanded(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final overlayVisible = covered || !_animation.isDismissed;
          return Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: covered && _animation.isCompleted,
                child: TickerMode(
                  enabled: !overlayVisible,
                  child: ExcludeFocus(
                    excluding: overlayVisible,
                    child: ExcludeSemantics(
                      excluding: overlayVisible,
                      child: IgnorePointer(
                        ignoring: overlayVisible,
                        child: const AppShell(),
                      ),
                    ),
                  ),
                ),
              ),
              if (overlayVisible)
                ExcludeFocus(
                  excluding: !covered,
                  child: IgnorePointer(
                    ignoring: !covered,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(_curve),
                      child: _overlay == AppPage.settings
                          ? const SettingsPage()
                          : DevicePresentationCatalog.settingsPageFor(
                              _deviceName!,
                              onClose: navigation.closeSettings,
                            ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }
}
