/*
 * @Description: 将设备型号映射为连接方式图标和对应的设备页面。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-06 14:02:45
 * @License: GPL 3.0
 */

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'widgets/generic_page_content.dart';
import 'widgets/unsupported_settings.dart';

/// 设备展示层目录。
///
/// 负责把设备名称映射为图标和页面，避免 App Shell 直接依赖具体设备页面。
class DevicePresentationCatalog {
  const DevicePresentationCatalog._();

  static IconData iconFor(String deviceName) {
    return deviceName == 'T-Display-P4'
        ? Symbols.signal_wifi_4_bar
        : Symbols.link;
  }

  /// 根据设备名称返回对应页面。
  ///
  /// 未适配的设备落到通用页面，方便后续先接入设备列表再逐步补齐专属页面。
  static Widget pageFor(String deviceName) {
    return GenericDevicePageContent(
      key: ValueKey<String>(deviceName),
      deviceName: deviceName,
      icon: iconFor(deviceName),
    );
  }

  /// 根据目标设备创建设置页，未适配的设备显示说明和返回入口。
  static Widget settingsPageFor(
    String deviceName, {
    required VoidCallback onClose,
  }) {
    return UnsupportedDeviceSettings(
      key: ValueKey<String>(deviceName),
      deviceName: deviceName,
      onClose: onClose,
    );
  }
}
