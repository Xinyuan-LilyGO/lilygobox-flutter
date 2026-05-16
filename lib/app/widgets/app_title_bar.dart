import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_info/package_info_provider.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/window/window_provider.dart';
import '../navigation/app_navigation_provider.dart';
import 'app_title_bar_control_button.dart';
import 'settings_button_with_animation.dart';

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

    return Container(
      height: height,
      color: theme.primary,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
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
          Center(
            child: SettingsButtonWithAnimation(
              onPressed: () => navigationProvider.setPage(AppPage.settings),
              isFocused: isFocused,
              theme: theme,
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
          hoverColor: theme.appTitleBarIconBackgroundColor,
          iconColor: iconColor,
        ),
        AppTitleBarControlsButtonTemplate(
          icon: isMaximized ? Symbols.filter_none : Symbols.crop_square_rounded,
          onPressed: () => unawaited(
            windowProvider.handleMaximizeRestore(),
          ),
          hoverColor: theme.appTitleBarIconBackgroundColor,
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
