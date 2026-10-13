/*
 * @Description: 设备控制协议类型、能力校验与真实电池状态。
 * @Author: LILYGO_L
 * @Date: 2026-10-12 00:00:00
 * @LastEditTime: 2026-10-12 00:00:00
 * @License: GPL 3.0
 */

/// 与设备端锁屏设置共用的秒数选项，0 表示永不自动锁屏。
const deviceLockTimeoutOptions = [15, 30, 60, 120, 300, 600, 0];

enum DeviceControlField {
  screenEnabled('screenEnabled', 'screen'),
  brightness('brightness', 'screen'),
  rotation('rotation', 'screen'),
  lockTimeoutSeconds('lockTimeoutSeconds', 'screen'),
  soundEnabled('soundEnabled', 'audio'),
  volume('volume', 'audio'),
  hapticEnabled('hapticEnabled', 'haptic'),
  hapticStrength('hapticStrength', 'haptic');

  const DeviceControlField(this.wireName, this.capability);
  final String wireName;
  final String capability;

  bool accepts(Object value) => switch (this) {
    screenEnabled || soundEnabled || hapticEnabled => value is bool,
    rotation => value is int && const [0, 90, 180, 270].contains(value),
    lockTimeoutSeconds =>
      value is int && deviceLockTimeoutOptions.contains(value),
    brightness => value is int && value >= 10 && value <= 100,
    volume || hapticStrength => value is int && value >= 0 && value <= 100,
  };
}

class DeviceBatteryState {
  const DeviceBatteryState({
    required this.percent,
    required this.charging,
    required this.full,
    required this.voltageMv,
    required this.currentMa,
    required this.temperatureC,
  });

  final int percent;
  final bool charging;
  final bool full;
  final int voltageMv;
  final int currentMa;
  final double temperatureC;

  static DeviceBatteryState? parse(Object? source) {
    final data = _object(source);
    if (!_boolean(data['available'])) return null;
    final temperature = data['temperatureC'];
    if (temperature is! num || !temperature.isFinite) {
      throw const FormatException('Invalid battery temperature');
    }
    return DeviceBatteryState(
      percent: _integer(data['percent'], 0, 100),
      charging: _boolean(data['charging']),
      full: _boolean(data['full']),
      voltageMv: _integer(data['voltageMv'], 0, 100000),
      currentMa: _integer(data['currentMa'], -100000, 100000),
      temperatureC: temperature.toDouble(),
    );
  }
}

class DeviceControlState {
  DeviceControlState._(
    this.ready,
    this.capabilities,
    this.values,
    this.battery,
  );

  factory DeviceControlState.parse(Object? source) {
    final data = _object(source);
    final capabilities = _object(data['capabilities']);
    final supported = <String>{
      for (final key in ['screen', 'audio', 'haptic'])
        if (_boolean(capabilities[key])) key,
    };
    final values = <DeviceControlField, Object>{};
    for (final field in DeviceControlField.values) {
      // 旧固件没有自动锁屏字段，保留其他控制并禁用新增设置。
      if (field == DeviceControlField.lockTimeoutSeconds &&
          !data.containsKey(field.wireName)) {
        continue;
      }
      final value = data[field.wireName];
      if (value == null || !field.accepts(value)) {
        throw FormatException('Invalid ${field.wireName}');
      }
      values[field] = value;
    }
    return DeviceControlState._(
      _boolean(data['ready']),
      Set.unmodifiable(supported),
      Map.unmodifiable(values),
      DeviceBatteryState.parse(data['battery']),
    );
  }

  final bool ready;
  final Set<String> capabilities;
  final Map<DeviceControlField, Object> values;
  final DeviceBatteryState? battery;
  bool supports(DeviceControlField field) =>
      ready &&
      capabilities.contains(field.capability) &&
      values.containsKey(field);
  int number(DeviceControlField field) => values[field]! as int;
  bool enabled(DeviceControlField field) => values[field]! as bool;

  /// 拖动时立即显示目标值；执行失败后去掉覆盖即可恢复设备确认值。
  DeviceControlState withTargets(Map<DeviceControlField, Object> targets) =>
      DeviceControlState._(
        ready,
        capabilities,
        Map.unmodifiable({...values, ...targets}),
        battery,
      );
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException();
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException();
  return value;
}

int _integer(Object? value, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException();
  }
  return value;
}
