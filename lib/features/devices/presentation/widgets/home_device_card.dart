/*
 * @Description: 展示主页设备卡片与真实连接状态，预留产品图片并以谷歌连接图标占位。
 * @Author: LILYGO_L
 * @Date: 2026-10-06 14:00:00
 * @LastEditTime: 2026-10-06 14:40:14
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/context_menu/right_click_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../catalog.dart';

class HomeDeviceCard extends StatefulWidget {
  const HomeDeviceCard({
    super.key,
    required this.name,
    required this.model,
    required this.connected,
    required this.connecting,
    required this.onPressed,
    this.usesWifi = false,
    this.macAddress,
    this.onDelete,
  });

  final String name;
  final String model;
  final bool connected;
  final bool connecting;
  final VoidCallback onPressed;
  final bool usesWifi;
  final String? macAddress;
  final VoidCallback? onDelete;

  @override
  State<HomeDeviceCard> createState() => _HomeDeviceCardState();
}

class _HomeDeviceCardState extends State<HomeDeviceCard> {
  final _menu = RightClickMenuController();

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final model = widget.model;
    final connected = widget.connected;
    final connecting = widget.connecting;
    final usesWifi = widget.usesWifi;
    final macAddress = widget.macAddress;
    final theme = context.watch<ThemeProvider>().themeData;
    final l10n = context.l10n;
    final status = connected
        ? l10n.homeDeviceOnline
        : connecting
        ? l10n.homeDeviceConnecting
        : l10n.homeDeviceOffline;
    final card = Semantics(
      button: true,
      child: MenuItemSurface(
        theme: theme,
        onPressed: () {
          // 首页会保留在页面栈中，进入详情前主动移除其菜单浮层。
          _menu.close();
          widget.onPressed();
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected
                          ? theme.adaptiveColor(
                              dark: const Color(0xFF7CBD94),
                              light: const Color(0xFF4B9565),
                            )
                          : connecting
                          ? theme.baseTertiary
                          : theme.textColorTertiary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textColorTertiary,
                      ),
                    ),
                  ),
                  if (usesWifi) ...[
                    const SizedBox(width: 12),
                    Icon(
                      connected || connecting ? Symbols.wifi : Symbols.wifi_off,
                      size: 14,
                      color: theme.textColorTertiary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Wi-Fi',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textColorTertiary,
                      ),
                    ),
                  ],
                ],
              ),
              // 预留正式产品图片区域，当前仅使用 Material Symbols 连接图标占位。
              SizedBox(
                height: 116,
                child: Center(
                  child: Icon(
                    DevicePresentationCatalog.iconFor(model),
                    size: 64,
                    fill: 1,
                    weight: 400,
                    color: theme.textColorTertiary,
                  ),
                ),
              ),
              AppTooltip(
                message: name,
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: theme.textColorTertiary),
              ),
              if (macAddress != null) ...[
                const SizedBox(height: 4),
                Text(
                  'MAC $macAddress',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorTertiary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: .2),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.openDevice,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textColorSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    Symbols.chevron_right,
                    size: 18,
                    color: theme.textColorTertiary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return RightClickMenuBuilder.buildMenuAnchor(
      context: context,
      controller: _menu,
      theme: theme,
      onSecondaryTap: () {},
      menuItems: [
        RightClickMenuItem(
          label: l10n.deleteDevice,
          icon: Symbols.delete_rounded,
          isEnabled: widget.onDelete != null,
          onTap: () {
            _menu.close();
            widget.onDelete?.call();
          },
        ),
      ],
      child: card,
    );
  }
}
