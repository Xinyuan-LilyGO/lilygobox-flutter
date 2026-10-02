/*
 * @Description: 定义不暴露连接方式的设备发现及连接接口。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 13:35:30
 * @LastEditTime: 2026-10-02 13:35:30
 * @License: GPL 3.0
 */

class DiscoveredDevice {
  const DiscoveredDevice({required this.id, required this.name});

  // 同一台设备经不同连接路径发现时，服务必须提供一致的稳定标识。
  final String id;
  final String name;
}

abstract class DeviceDiscoveryService {
  const DeviceDiscoveryService();

  /// 取消订阅必须停止本轮发现；正常结束表示本轮查找完成。
  Stream<DiscoveredDevice> discover();

  /// 只有确认设备已建立连接时才能返回 true，不能仅依据发现结果返回。
  Future<bool> connect(DiscoveredDevice device);

  /// 取消仍在进行的连接，并释放其占用的资源；允许重复调用。
  Future<void> cancelConnection();
}

class DiscoveryUnavailableException implements Exception {
  const DiscoveryUnavailableException();
}

/// 当前仓库尚未实现发现协议，明确报告不可用，不生成演示设备。
class UnavailableDeviceDiscoveryService extends DeviceDiscoveryService {
  const UnavailableDeviceDiscoveryService();

  @override
  Stream<DiscoveredDevice> discover() =>
      Stream.error(const DiscoveryUnavailableException());

  @override
  Future<bool> connect(DiscoveredDevice device) async =>
      throw const DiscoveryUnavailableException();

  @override
  Future<void> cancelConnection() async {}
}
