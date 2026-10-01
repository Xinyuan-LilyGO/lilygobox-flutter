/*
 * @Description: 构建主窗口标题栏、侧栏开关、设置入口和窗口控制按钮。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-01 17:19:32
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
  const AppTitleBar({super.key});

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
      (provider) => provider.currentPage == AppPage.home,
    );

    return Container(
      height: height,
      color: theme.primary,
      child: Row(
        children: [
          if (showSidebarToggle)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: AppTooltip(
                verticalOffset: 16,
                message: isSidebarVisible
                    ? context.l10n.hideSidebar
                    : context.l10n.showSidebar,
                child: TitleBarIconButton(
                  key: const ValueKey('toggle-sidebar'),
                  icon: Symbols.dock_to_right,
                  onPressed: context.read<AppShellProvider>().toggleSidebar,
                  isFocused: isFocused,
                  theme: theme,
                ),
              ),
            ),
          Expanded(
            child: DragToMoveArea(
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
                child: showSidebarToggle
                    ? null
                    : Text(
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
          Center(
            child: AppTooltip(
              verticalOffset: 16,
              message: context.l10n.settings,
              child: TitleBarIconButton(
                icon: Symbols.settings,
                onPressed: () => navigationProvider.setPage(AppPage.settings),
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
      children: [
        AppTitleBarControlsButtonTemplate(
          icon: Symbols.remove_rounded,
          onPressed: () => unawaited(windowProvider.minimize()),
          hoverColor: theme.primaryTextHoverColor,
          iconColor: iconColor,
        ),
        AppTitleBarControlsButtonTemplate(
          icon: isMaximized ? Symbols.filter_none : Symbols.crop_square_rounded,
          onPressed: () => unawaited(windowProvider.handleMaximizeRestore()),
          hoverColor: theme.primaryTextHoverColor,
          iconSize: isMaximized ? 13.5 : 14,
          iconWeight: 510.0,
          rotateAngle: isMaximized ? 180 : 0,
          iconColor: iconColor,
        ),
        AppTitleBarControlsButtonTemplate(
          icon: Symbols.close_rounded,
          onPressed: () => unawaited(windowProvider.close()),
          hoverColor: Colors.red.shade600,
          iconColor: iconColor,
        ),
      ],
    );
  }
}
