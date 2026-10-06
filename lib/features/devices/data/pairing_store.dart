/*
 * @Description: 按设备 ID 在系统安全存储中保存应用连接授权，避免写入普通配置。
 * @Author: LILYGO_L
 * @Date: 2026-10-06 09:01:38
 * @LastEditTime: 2026-10-06 09:01:38
 * @License: GPL 3.0
 */
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
  Future<String?> read(String deviceId) async {
    final id = LanDevice.normalizeId(deviceId);
    final token = await _storage.read(key: _key(id));
    if (token != null) return token;
    final legacy = await _storage.read(key: _key('lgb-$id'));
    if (legacy != null) {
      // 新键保存成功后才移除旧键，避免迁移失败导致授权丢失。
      await write(id, legacy);
    }
    return legacy;
  }

  @override
  Future<void> write(String deviceId, String token) async {
    final id = LanDevice.normalizeId(deviceId);
    await _storage.write(key: _key(id), value: token);
    await _storage.delete(key: _key('lgb-$id'));
  }

  @override
  Future<void> delete(String deviceId) async {
    final id = LanDevice.normalizeId(deviceId);
    // 先删除旧键，避免撤销授权后旧令牌被再次迁移。
    await _storage.delete(key: _key('lgb-$id'));
    await _storage.delete(key: _key(id));
  }
}
