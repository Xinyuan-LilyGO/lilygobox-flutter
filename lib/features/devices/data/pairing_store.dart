/*
 * @Description: 按设备 ID 在系统安全存储中保存应用连接授权，避免写入普通配置。
 */
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'lan_discovery.dart';

abstract class DevicePairingStore {
  Future<String?> read(String deviceId);
  Future<void> write(String deviceId, String token);
  Future<void> delete(String deviceId);
  Future<String?> readFingerprint(String deviceId);
  Future<void> writeFingerprint(String deviceId, String fingerprint);
  Future<void> deleteFingerprint(String deviceId);
}

class SecureDevicePairingStore implements DevicePairingStore {
  final _storage = const FlutterSecureStorage();
  static const _clientIdKey = 'lilygobox.app.client-id.v1';
  static Future<String>? _clientIdOperation;

  /// 获取安装级公开标识；删除单个设备仅撤销授权，不重置此标识。
  Future<String> getClientId() => _clientIdOperation ??= _loadClientId()
      .whenComplete(() => _clientIdOperation = null);

  Future<String> _loadClientId() async {
    final existing = await _storage.read(key: _clientIdKey);
    if (existing != null) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) {
        throw const FormatException('Invalid application identity');
      }
      return existing;
    }
    final random = Random.secure();
    final id = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    // 持久化成功后才参与握手，防止存储失败时每次创建不同的身份。
    await _storage.write(key: _clientIdKey, value: id);
    return id;
  }

  String _key(String id) => 'lilygobox.device.$id.pairing.v1';
  String _fingerprintKey(String id) =>
      'lilygobox.device.${LanDevice.normalizeId(id)}.tls.v1';

  @override
  Future<String?> readFingerprint(String deviceId) =>
      _storage.read(key: _fingerprintKey(deviceId));

  @override
  Future<void> writeFingerprint(String deviceId, String fingerprint) =>
      _storage.write(key: _fingerprintKey(deviceId), value: fingerprint);

  // 撤销应用授权不删除设备身份；仅由用户明确确认重新配对时清除。
  @override
  Future<void> deleteFingerprint(String deviceId) =>
      _storage.delete(key: _fingerprintKey(deviceId));

  @override
  Future<String?> read(String deviceId) =>
      _storage.read(key: _key(LanDevice.normalizeId(deviceId)));

  @override
  Future<void> write(String deviceId, String token) =>
      _storage.write(key: _key(LanDevice.normalizeId(deviceId)), value: token);

  @override
  Future<void> delete(String deviceId) =>
      _storage.delete(key: _key(LanDevice.normalizeId(deviceId)));
}
