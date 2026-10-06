/*
 * @Description: 验证 MAC 标识格式、旧设备记录去重和安全存储授权迁移。
 * @Author: LILYGO_L
 * @Date: 2026-10-06 15:00:00
 * @LastEditTime: 2026-10-06 15:00:00
 * @License: GPL 3.0
 */
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/storage/preferences.dart';
import 'package:lilygobox/features/devices/data/lan_discovery.dart';
import 'package:lilygobox/features/devices/data/pairing_store.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';

import '../../core/storage/preferences_test.dart' show MemoryPreferencesStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = 'aabbccddeeff';
  const legacyId = 'lgb-$id';
  const record = {
    'id': legacyId,
    'name': 'Desk P4',
    'address': '192.168.1.8',
    'port': 18464,
    'model': 'T-Display-P4',
  };

  test('legacy and new IDs share MAC but retain exact wire identity', () {
    final old = LanDevice.fromJson(record)!;
    final current = LanDevice.fromJson({...record, 'id': id})!;
    expect(old.id, current.id);
    expect(old.macAddress, 'AA:BB:CC:DD:EE:FF');
    expect(current.macAddress, old.macAddress);
    expect(old.protocolId, legacyId);
    expect(current.protocolId, id);
    expect(LanDevice.fromJson(old.toJson())!.protocolId, legacyId);
    expect(LanDevice.fromJson({...record, 'id': 'not-a-mac'}), isNull);
    expect(
      LanDevice.fromJson({...record, 'protocolId': '001122334455'}),
      isNull,
    );
  });

  test(
    'migration deduplicates IDs and retains unrelated preferences',
    () async {
      final storage = MemoryPreferencesStorage()
        ..value = jsonEncode({
          'devices': [legacyId, id, 'T-Glasses-P4'],
          'devices.lan.v1': jsonEncode([record]),
          'language': 'zh',
        });
      final preferences = await AppPreferences.load(storage: storage);
      addTearDown(preferences.dispose);
      final manager = DeviceManagerProvider(preferences: preferences);
      addTearDown(manager.dispose);
      expect(manager.addedDevices, [id, 'T-Glasses-P4']);
      expect(manager.lanDevice(id)!.protocolId, legacyId);
      await preferences.flush();
      final saved = jsonDecode(storage.value!);
      expect(saved['devices'], [id, 'T-Glasses-P4']);
      expect(saved['language'], 'zh');
      expect(jsonDecode(saved['devices.lan.v1'])[0]['id'], id);

      // 同一块板升级固件后，更新协议 ID，不能新增一张重复设备卡片。
      manager.addLanDevice(LanDevice.fromJson({...record, 'id': id})!);
      expect(manager.addedDevices, [id, 'T-Glasses-P4']);
      expect(manager.lanDevice(id)!.protocolId, id);
      await preferences.flush();
      final restoredPreferences = await AppPreferences.load(storage: storage);
      addTearDown(restoredPreferences.dispose);
      final restored = DeviceManagerProvider(preferences: restoredPreferences);
      addTearDown(restored.dispose);
      expect(restored.addedDevices, manager.addedDevices);
      expect(restored.lanDevice(id)!.protocolId, id);
    },
  );

  test(
    'secure token migrates without re-pairing and deletion removes aliases',
    () async {
      const oldKey = 'lilygobox.device.$legacyId.pairing.v1';
      const newKey = 'lilygobox.device.$id.pairing.v1';
      FlutterSecureStorage.setMockInitialValues({oldKey: 'existing-token'});
      final store = SecureDevicePairingStore();
      const storage = FlutterSecureStorage();
      expect(await store.read(id), 'existing-token');
      expect(await storage.read(key: newKey), 'existing-token');
      expect(await storage.read(key: oldKey), isNull);
      await storage.write(key: oldKey, value: 'stale-token');
      expect(await store.read(id), 'existing-token');
      await store.delete(id);
      expect(await store.read(id), isNull);
      expect(await storage.read(key: oldKey), isNull);
      expect(await storage.read(key: newKey), isNull);
    },
  );
}
