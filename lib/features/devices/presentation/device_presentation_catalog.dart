import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/device_catalog.dart';
import '../t_glasses_p4/presentation/pages/device_page_content_t_glasses_p4.dart';
import 'widgets/generic_device_page_content.dart';

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
}
