/*
 * @Description: 主页与设备概览共用连接状态徽标及悬停说明。
 * @Author: LILYGO_L
 * @Date: 2026-10-10 10:00:00
 * @LastEditTime: 2026-10-10 10:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/app_tooltip.dart';

/// 用圆点和文字展示连接状态，说明复用公共悬停提示。
class DeviceStatusBadge extends StatelessWidget {
  const DeviceStatusBadge({
    super.key,
    required this.theme,
    required this.label,
    required this.connected,
    required this.connecting,
    this.tooltipMessage,
  });

  final AppTheme theme;
  final String label;
  final bool connected;
  final bool connecting;
  final String? tooltipMessage;

  @override
  Widget build(BuildContext context) {
    final statusColor = connected
        ? theme.adaptiveColor(
            dark: const Color(0xFF83B69A),
            light: const Color(0xFF438063),
          )
        : connecting
        ? theme.baseTertiary
        : theme.textColorTertiary;
    final badge = Container(
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
    final message = tooltipMessage;
    if (message == null || message.isEmpty) return badge;
    return AppTooltip(message: message, verticalOffset: 16, child: badge);
  }
}
