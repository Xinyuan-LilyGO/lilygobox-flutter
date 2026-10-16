import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 根据设备报告的 RSSI 选择与 ESP-IDF 状态栏一致的 Wi-Fi 图标。
IconData deviceWifiIconForRssi(int? rssi) {
  if (rssi == null) return Symbols.wifi;
  if (rssi >= -50) return Symbols.signal_wifi_4_bar;
  if (rssi >= -60) return Symbols.network_wifi;
  if (rssi >= -67) return Symbols.network_wifi_3_bar;
  if (rssi >= -75) return Symbols.network_wifi_2_bar;
  return Symbols.network_wifi_1_bar;
}
