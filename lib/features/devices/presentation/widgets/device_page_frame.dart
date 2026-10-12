/*
 * @Description: 为主页进入的设备详情提供统一返回入口，保留后台连接和页面状态。
 * @Author: LILYGO_L
 * @Date: 2026-10-06 14:00:00
 * @LastEditTime: 2026-10-08 18:14:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import 'device_connection_help.dart';

class DevicePageFrame extends StatelessWidget {
  const DevicePageFrame({
    super.key,
    required this.child,
    required this.onBack,
    required this.active,
    this.pageTitle,
    this.deviceId,
  });

  final Widget child;
  final VoidCallback onBack;
  final bool active;
  final ValueNotifier<String?>? pageTitle;
  final String? deviceId;

  Widget _title(BuildContext context, AppTheme theme) {
    final title = pageTitle;
    if (title == null) {
      return Text(
        context.l10n.deviceDetails,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: theme.textColorPrimary,
        ),
      );
    }
    return ValueListenableBuilder<String?>(
      valueListenable: title,
      builder: (context, value, _) => Text(
        value ?? context.l10n.deviceDetails,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: theme.textColorPrimary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final isCurrent =
        active &&
        context.watch<AppNavigationProvider>().currentPage == AppPage.home;
    return PopScope(
      canPop: !isCurrent,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isCurrent) onBack();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (isCurrent) onBack();
          },
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    AppTooltip(
                      message: context.l10n.back,
                      verticalOffset: 16,
                      child: Semantics(
                        label: context.l10n.back,
                        button: true,
                        child: TitleBarIconButton(
                          key: const ValueKey('device-back-home'),
                          theme: theme,
                          backgroundColor: theme.secondary,
                          isFocused: true,
                          icon: Symbols.arrow_back_rounded,
                          size: 28,
                          iconSize: 18,
                          onPressed: onBack,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _title(context, theme)),
                    DeviceHelpMenu(deviceId: deviceId),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
