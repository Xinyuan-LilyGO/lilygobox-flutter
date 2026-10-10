/*
 * @Description: 集中管理设备特色卡片及电池图形的亮暗主题配色，随全局主题平滑过渡。
 * @Author: LILYGO_L
 * @Date: 2026-10-09 10:00:00
 * @LastEditTime: 2026-10-09 10:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';

import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';

/// 电池专用颜色独立于应用公共主题，避免改变其他卡片的配色。
class DeviceBatteryColors {
  const DeviceBatteryColors(this.theme);

  final AppTheme theme;

  Color get background => theme.primary;
  Color get foreground => theme.textColorPrimary;
  Color get muted => theme.textColorTertiary;
  Color get fill => theme.batteryFillColor;
  Color get empty => theme.materialColors.primaryContainer;
}

/// 我的设备使用独立的特色配色；暗色背景与亮色背景分别维护。
class DeviceIdentityColors {
  const DeviceIdentityColors(this.theme);

  final AppTheme theme;

  Color get background => theme.adaptiveColor(
    dark: const Color(0xFFE5ECF3),
    light: const Color(0xFF151E25),
  );
  Color get foreground => theme.adaptiveColor(
    dark: const Color(0xFF192632),
    light: const Color(0xFFF5F8FA),
  );
  Color get muted => theme.adaptiveColor(
    dark: const Color(0xFF43515E),
    light: const Color(0xFFADB8C2),
  );
}
