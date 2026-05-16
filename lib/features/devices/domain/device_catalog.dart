/// 设备领域层目录。
///
/// 只维护“支持哪些设备”的稳定标识，不依赖任何 Flutter UI 类型。
class DeviceCatalog {
  const DeviceCatalog._();

  static const String tGlassesP4Name = 'T-Glasses-P4';

  static const List<String> supportedDeviceNames = [tGlassesP4Name];
}
