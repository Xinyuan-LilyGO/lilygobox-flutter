/*
 * @Description: 展示单页设备首页、默认空状态和添加设备入口。
 * @Author: LILYGO_L
 * @Date: 2025-11-07 11:23:45
 * @LastEditTime: 2026-10-03 18:10:36
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/provider.dart';
import '../../../core/widgets/action_button.dart';
import '../../../features/devices/state/manager_provider.dart';
import '../../navigation/provider.dart';
import '../widgets/home_device_illustration.dart';

class HomePageContent extends StatelessWidget {
  const HomePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final hasDevices = context.select<DeviceManagerProvider, bool>(
      (devices) => devices.addedDevices.isNotEmpty,
    );
    final l10n = context.l10n;
    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
      child: ColoredBox(
        color: theme.secondary,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final inset = compact ? 20.0 : 32.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, 24, inset, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.home,
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: theme.textColorPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.homeDevicesSubtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textColorTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, bodyConstraints) =>
                        SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: bodyConstraints.maxHeight,
                            ),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                inset,
                                24,
                                inset,
                                // 补偿顶部标题高度，使主体相对整个内容页居中。
                                24 +
                                    constraints.maxHeight -
                                    bodyConstraints.maxHeight,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 380,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      HomeDeviceIllustration(theme: theme),
                                      const SizedBox(height: 4),
                                      Text(
                                        hasDevices
                                            ? l10n.homeDevicesReady
                                            : l10n.homeDevicesEmpty,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: theme.textColorPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        hasDevices
                                            ? l10n.homeDevicesReadyDescription
                                            : l10n.homeDevicesEmptyDescription,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.35,
                                          color: theme.textColorTertiary,
                                        ),
                                      ),
                                      const SizedBox(height: 26),
                                      AppActionButton(
                                        theme: theme,
                                        label: l10n.addDevice,
                                        icon: Symbols.add_rounded,
                                        primary: true,
                                        onPressed: () => context
                                            .read<AppNavigationProvider>()
                                            .setPage(AppPage.addDevice),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
