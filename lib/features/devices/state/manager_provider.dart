/*
 * @Description: 管理已添加设备列表及设备的添加、删除和清空操作。
 */

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../../core/storage/preferences.dart';
import '../data/lan_discovery.dart';

class DeviceManagerProvider extends ChangeNotifier {
  DeviceManagerProvider({AppPreferences? preferences})
    : _preferences = preferences,
      _addedDevices = List.of(preferences?.stringList('devices') ?? []) {
    try {
      final records = jsonDecode(
        preferences?.stringValue('devices.lan.v1', '[]') ?? '[]',
      );
      if (records is List) {
        for (final record in records) {
          final device = LanDevice.fromJson(record);
          if (device != null) _lanDevices[device.id] = device;
        }
      }
    } on FormatException {
      // 损坏的局域网记录不影响设备列表和其他配置。
    }
  }

  final AppPreferences? _preferences;
  final List<String> _addedDevices;
  final Map<String, LanDevice> _lanDevices = {};
  bool _disposed = false;

  LanDevice? lanDevice(String id) => _lanDevices[id];
  String displayName(String id) => _lanDevices[id]?.name ?? id;

  void addLanDevice(LanDevice device) {
    final previous = _lanDevices[device.id];
    if (_addedDevices.contains(device.id) &&
        previous?.name == device.name &&
        previous?.address == device.address &&
        previous?.port == device.port &&
        previous?.model == device.model &&
        previous?.modelVersion == device.modelVersion &&
        previous?.protocolId == device.protocolId) {
      return;
    }
    _lanDevices[device.id] = device;
    if (!_addedDevices.contains(device.id)) _addedDevices.add(device.id);
    _saveLanDevices();
    _preferences?.setValue('devices', _addedDevices);
    notifyListeners();
  }

  void _saveLanDevices() => _preferences?.setValue(
    'devices.lan.v1',
    jsonEncode(_lanDevices.values.map((device) => device.toJson()).toList()),
  );

  List<String> get addedDevices => List.unmodifiable(_addedDevices);

  void addDevice(String deviceName) {
    if (deviceName.trim().isEmpty || _addedDevices.contains(deviceName)) return;
    _addedDevices.add(deviceName);
    _preferences?.setValue('devices', _addedDevices);
    notifyListeners();
  }

  void removeDevice(String deviceName) {
    _lanDevices.remove(deviceName);
    _saveLanDevices();
    _addedDevices.remove(deviceName);
    _preferences?.setValue('devices', _addedDevices);
    notifyListeners();
  }

  /// 删除设备资料并立即保存；写入失败时恢复卡片，便于用户再次删除。
  Future<bool> removeDeviceAndSave(String id) async {
    if (_disposed) return false;
    final index = _addedDevices.indexOf(id);
    final saved = _lanDevices[id];
    removeDevice(id);
    if (await _preferences?.flush() ?? true) return true;
    if (index >= 0 && !_addedDevices.contains(id)) {
      _addedDevices.insert(index.clamp(0, _addedDevices.length), id);
    }
    if (saved != null) _lanDevices.putIfAbsent(id, () => saved);
    _saveLanDevices();
    _preferences?.setValue('devices', _addedDevices);
    if (!_disposed) notifyListeners();
    return false;
  }

  void clearDevices() {
    _lanDevices.clear();
    _saveLanDevices();
    _addedDevices.clear();
    _preferences?.setValue('devices', _addedDevices);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
