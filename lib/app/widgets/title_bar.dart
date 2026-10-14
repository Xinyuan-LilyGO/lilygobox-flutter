/*
 * @Description: 构建主窗口标题栏，提供标题淡入淡出、侧栏开关及窗口控制。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-14 00:00:00
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_info/package_info_provider.dart';
import '../../core/l10n/language_provider.dart';
import '../../core/theme/provider.dart';
import '../../core/widgets/app_tooltip.dart';
import '../../core/widgets/title_bar_icon_button.dart';
import '../../core/window/provider.dart';
import '../navigation/provider.dart';
import '../shell/state/provider.dart';
import 'title_bar_control_button.dart';

class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key, this.navigationEnabled = true});

  final bool navigationEnabled;

  static const double height = 30.0;

  @override
  Widget build(BuildContext context) {
    final windowProvider = context.watch<WindowProvider>();
    final navigationProvider = context.read<AppNavigationProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final packageInfoProvider = context.watch<PackageInfoProvider>();
    final theme = themeProvider.themeData;
    final isFocused = windowProvider.isFocused;
    final appName = packageInfoProvider.appName == 'Unknown'
        ? 'LilygoBox'
        : packageInfoProvider.appName;
    final isSidebarVisible = context.select<AppShellProvider, bool>(
      (provider) => provider.isSidebarVisible,
    );
    final showSidebarToggle = context.select<AppNavigationProvider, bool>(
      (provider) =>
          provider.currentPage == AppPage.home ||
          provider.currentPage == AppPage.addDevice,
    );
    final fadeDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    // 底边对齐完整物理像素，避免非整数缩放下悬停背景露出浅色细线。
    final alignedHeight = (height * pixelRatio).ceilToDouble() / pixelRatio;
    return Container(
      height: alignedHeight,
      color: theme.primary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DragToMoveArea(
                  child: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 12),
                    child: AnimatedOpacity(
                      opacity: showSidebarToggle ? 0 : 1,
                      duration: fadeDuration,
                      curve: Curves.easeInOut,
                      child: Text(
                        appName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: isFocused
                              ? theme.appTitleTextColor
                              : theme.inactiveTextColor,
                        ),
                      ),
                    ),
                  ),
                ),
                // 固定两者的位置，切换时只改变透明度，避免标题横向跳动。
                Positioned(
                  left: 10,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !showSidebarToggle,
                    child: ExcludeFocus(
                      excluding: !showSidebarToggle,
                      child: ExcludeSemantics(
                        excluding: !showSidebarToggle,
                        child: AnimatedOpacity(
                          opacity: showSidebarToggle ? 1 : 0,
                          duration: fadeDuration,
                          curve: Curves.easeInOut,
                          child: Center(
                            child: AppTooltip(
                              verticalOffset: 16,
                              message: isSidebarVisible
                                  ? context.l10n.hideSidebar
                                  : context.l10n.showSidebar,
                              child: TitleBarIconButton(
                                key: const ValueKey('toggle-sidebar'),
                                icon: Symbols.dock_to_right,
                                onPressed: navigationEnabled
                                    ? context
                                          .read<AppShellProvider>()
                                          .toggleSidebar
                                    : null,
                                isFocused: isFocused,
                                theme: theme,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: AppTooltip(
              verticalOffset: 16,
              message: context.l10n.settings,
              child: TitleBarIconButton(
                key: const ValueKey('titlebar-settings'),
                icon: Symbols.settings,
                onPressed: navigationEnabled
                    ? () => navigationProvider.setPage(AppPage.settings)
                    : null,
                isFocused: isFocused,
                theme: theme,
              ),
            ),
          ),
          const SizedBox(width: 5.0),
          const AppTitleBarControls(),
        ],
      ),
    );
  }
}

class AppTitleBarControls extends StatelessWidget {
  const AppTitleBarControls({super.key});

  @override
  Widget build(BuildContext context) {
    final windowProvider = context.watch<WindowProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final theme = themeProvider.themeData;
    final isFocused = windowProvider.isFocused;
    final isMaximized = windowProvider.isMaximized;
    final iconColor = isFocused ? theme.iconColor : theme.inactiveIconColor;

    return Row(
      // 窗口按钮随标题栏填满高度，不在底部留下未覆盖的像素。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTooltip(
          message: context.l10n.minimizeWindow,
          verticalOffset: 16,
          child: AppTitleBarControlsButtonTemplate(
            theme: theme,
            icon: Symbols.remove_rounded,
            onPressed: () => unawaited(windowProvider.minimize()),
            iconColor: iconColor,
          ),
        ),
        AppTooltip(
          message: isMaximized
              ? context.l10n.restoreWindow
              : context.l10n.maximizeWindow,
          verticalOffset: 16,
          child: AppTitleBarControlsButtonTemplate(
            theme: theme,
            icon: isMaximized
                ? Symbols.filter_none
                : Symbols.crop_square_rounded,
            onPressed: () => unawaited(windowProvider.handleMaximizeRestore()),
            iconSize: isMaximized ? 13.5 : 14,
            iconWeight: 510.0,
            rotateAngle: isMaximized ? 180 : 0,
            iconColor: iconColor,
          ),
        ),
        AppTooltip(
          message: context.l10n.closeWindow,
          verticalOffset: 16,
          child: AppTitleBarControlsButtonTemplate(
            theme: theme,
            icon: Symbols.close_rounded,
            onPressed: () => unawaited(windowProvider.close()),
            hoverColor: Colors.red.shade600,
            hoverIconColor: Colors.white,
            iconColor: iconColor,
          ),
        ),
      ],
    );
  }
}
