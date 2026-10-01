/*
 * @Description: 定义应用支持的设备名称及领域层设备目录。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

/// 设备领域层目录。
///
/// 只维护“支持哪些设备”的稳定标识，不依赖任何 Flutter UI 类型。
class DeviceCatalog {
  const DeviceCatalog._();

  static const String tGlassesP4Name = 'T-Glasses-P4';

  static const List<String> supportedDeviceNames = [tGlassesP4Name];
}
