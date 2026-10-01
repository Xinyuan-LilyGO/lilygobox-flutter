/*
 * @Description: 将设备名称映射为导航图标和对应的设备页面。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/catalog.dart';
import '../t_glasses_p4/presentation/pages/page.dart';
import '../t_glasses_p4/presentation/pages/settings_page.dart';
import 'widgets/generic_page_content.dart';
import 'widgets/unsupported_settings.dart';

/// 设备展示层目录。
///
/// 负责把领域层设备名称映射为图标和页面，避免 App Shell 直接依赖具体设备页面。
class DevicePresentationCatalog {
  const DevicePresentationCatalog._();

  static IconData iconFor(String deviceName) {
    return deviceName == DeviceCatalog.tGlassesP4Name
        ? Symbols.developer_board
        : Symbols.developer_board_rounded;
  }

  /// 根据设备名称返回对应页面。
  ///
  /// 未适配的设备落到通用页面，方便后续先接入设备列表再逐步补齐专属页面。
  static Widget pageFor(String deviceName) {
    return deviceName == DeviceCatalog.tGlassesP4Name
        ? const DevicePageContentTGlassesP4(
            key: ValueKey<String>(DeviceCatalog.tGlassesP4Name),
          )
        : GenericDevicePageContent(
            key: ValueKey<String>(deviceName),
            deviceName: deviceName,
          );
  }

  /// 根据目标设备创建设置页，未适配的设备显示说明和返回入口。
  static Widget settingsPageFor(
    String deviceName, {
    required VoidCallback onClose,
  }) {
    return deviceName == DeviceCatalog.tGlassesP4Name
        ? DeviceSettingsTGlassesP4(
            key: ValueKey<String>(deviceName),
            onClose: onClose,
          )
        : UnsupportedDeviceSettings(
            key: ValueKey<String>(deviceName),
            deviceName: deviceName,
            onClose: onClose,
          );
  }
}
