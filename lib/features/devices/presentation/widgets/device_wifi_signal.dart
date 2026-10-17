import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 按 RSSI 显示连续扇形 Wi-Fi 图标，保持 Signal Wifi 的视觉风格。
/// network_wifi 分级同为连续扇形，不使用 wifi 或 android_wifi 的分段弧线。
IconData deviceWifiIconForRssi(int? rssi, {required bool online}) {
  if (!online) return Symbols.signal_wifi_off;
  if (rssi == null || rssi >= -50) return Symbols.signal_wifi_4_bar;
  if (rssi >= -60) return Symbols.network_wifi;
  if (rssi >= -67) return Symbols.network_wifi_3_bar;
  if (rssi >= -75) return Symbols.network_wifi_2_bar;
  return Symbols.network_wifi_1_bar;
}
