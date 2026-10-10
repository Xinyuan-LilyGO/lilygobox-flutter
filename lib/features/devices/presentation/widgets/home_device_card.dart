/*
 * @Description: 展示主页设备卡片与真实连接状态，预留产品图片并以灰色 Blur On 图标占位。
 * @Author: LILYGO_L
 * @Date: 2026-10-06 14:00:00
 * @LastEditTime: 2026-10-08 18:25:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/context_menu/right_click_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/menu_item_surface.dart';

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
        backgroundColor: theme.primary,
        hoverColor: theme.primary,
        onPressed: () {
          // 首页会保留在页面栈中，进入详情前主动移除其菜单浮层。
          _menu.close();
          widget.onPressed();
        },
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.homeDeviceCardLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textColorTertiary,
                      ),
                    ),
                  ),
                  _statusBadge(
                    theme,
                    label: status,
                    connected: connected,
                    connecting: connecting,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 112,
                child: Center(
                  child: Icon(
                    Symbols.blur_on,
                    size: 80,
                    fill: 1,
                    weight: 400,
                    color: theme.textColorTertiary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: theme.textColorPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: theme.textColorTertiary),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(
                    usesWifi && (connected || connecting)
                        ? Symbols.wifi
                        : Symbols.wifi_off,
                    size: 20,
                    color: theme.basePrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    usesWifi ? 'Wi-Fi' : l10n.homeDeviceOffline,
                    style: TextStyle(fontSize: 13, color: theme.basePrimary),
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

  Widget _statusBadge(
    AppTheme theme, {
    required String label,
    required bool connected,
    required bool connecting,
  }) {
    final statusColor = connected
        ? theme.adaptiveColor(
            dark: const Color(0xFF83B69A),
            light: const Color(0xFF438063),
          )
        : connecting
        ? theme.baseTertiary
        : theme.textColorTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: theme.textColorTertiary),
          ),
        ],
      ),
    );
  }
}
