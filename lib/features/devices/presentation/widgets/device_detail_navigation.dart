/*
 * @Description: 设备详情底部悬浮导航，统一控制、连接和信息入口及选中动画。
 * @Author: LILYGO_L
 * @Date: 2026-10-07 18:00:00
 * @LastEditTime: 2026-10-07 18:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/menu_item_surface.dart';

enum DeviceDetailTab { control, connection, info }

class DeviceDetailNavigation extends StatelessWidget {
  const DeviceDetailNavigation({
    super.key,
    required this.theme,
    required this.selected,
    required this.onSelected,
  });

  final AppTheme theme;
  final DeviceDetailTab selected;
  final ValueChanged<DeviceDetailTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = [
      l10n.deviceControlTab,
      l10n.deviceConnectionTab,
      l10n.deviceInfoTab,
    ];
    const icons = [Symbols.tune, Symbols.link, Symbols.info];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.primary,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .09),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            height: 40 + MediaQuery.textScalerOf(context).scale(13),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment(selected.index - 1.0, 0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / 3,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.basePrimary.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(32),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final tab in DeviceDetailTab.values)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: selected == tab,
                          label: labels[tab.index],
                          excludeSemantics: true,
                          onTap: () => onSelected(tab),
                          child: MenuItemSurface(
                            key: ValueKey('device-tab-${tab.name}'),
                            theme: theme,
                            backgroundColor: Colors.transparent,
                            hoverColor: theme.basePrimary.withValues(
                              alpha: .08,
                            ),
                            borderRadius: BorderRadius.circular(32),
                            onPressed: () {
                              if (selected != tab) onSelected(tab);
                            },
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icons[tab.index],
                                    fill: 1,
                                    size: 23,
                                    color: selected == tab
                                        ? theme.baseTertiary
                                        : theme.textColorSecondary,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    labels[tab.index],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selected == tab
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: selected == tab
                                          ? theme.baseTertiary
                                          : theme.textColorSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
