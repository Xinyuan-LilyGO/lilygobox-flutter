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
  hapticStrength('hapticStrength', 'haptic'),
  batteryCapacityMah('batteryCapacityMah', 'battery');

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
    batteryCapacityMah => value is int && value >= 1 && value <= 65535,
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
    this.healthPercent,
    this.timeToFullMinutes,
    this.timeToEmptyMinutes,
  });

  final int percent;
  final bool charging;
  final bool full;
  final int voltageMv;
  final int currentMa;
  final double? temperatureC;
  final int? healthPercent;
  final int? timeToFullMinutes;
  final int? timeToEmptyMinutes;

  static DeviceBatteryState? parse(Object? source) {
    final data = _object(source);
    if (!_boolean(data['available'])) return null;
    final temperature = data['temperatureC'];
    if (temperature != null && (temperature is! num || !temperature.isFinite)) {
      throw const FormatException('Invalid battery temperature');
    }
    final current = _integer(data['currentMa'], -100000, 100000);
    // 兼容旧固件的矛盾状态：统一净电流正值充电、负值放电。
    final charging = _boolean(data['charging']) && current >= 0;
    final full = _boolean(data['full']);
    final toFull = _optionalInteger(data['timeToFullMinutes'], 1, 43199);
    final toEmpty = _optionalInteger(data['timeToEmptyMinutes'], 1, 43199);
    return DeviceBatteryState(
      percent: _integer(data['percent'], 0, 100),
      charging: charging,
      full: full,
      voltageMv: _integer(data['voltageMv'], 0, 100000),
      currentMa: current,
      temperatureC: (temperature as num?)?.toDouble(),
      healthPercent: _optionalInteger(data['healthPercent'], 1, 100),
      timeToFullMinutes: charging && !full && current > 0 ? toFull : null,
      timeToEmptyMinutes: !charging && current < 0 ? toEmpty : null,
    );
  }
}

class DeviceControlState {
  DeviceControlState._(
    this.ready,
    this.capabilities,
    this.values,
    this.battery,
    this.batteryCapacityMinimumMah,
    this.batteryCapacityMaximumMah,
  );

  factory DeviceControlState.parse(Object? source) {
    final data = _object(source);
    final capabilities = _object(data['capabilities']);
    final supported = <String>{
      for (final key in ['screen', 'audio', 'haptic', 'battery'])
        if (key != 'battery' || capabilities.containsKey(key))
          if (_boolean(capabilities[key])) key,
    };
    final values = <DeviceControlField, Object>{};
    for (final field in DeviceControlField.values) {
      // 旧固件没有新增设置字段，保留其他控制并禁用未支持的设置。
      if ((field == DeviceControlField.lockTimeoutSeconds ||
              field == DeviceControlField.batteryCapacityMah) &&
          !data.containsKey(field.wireName)) {
        continue;
      }
      final value = data[field.wireName];
      if (value == null || !field.accepts(value)) {
        throw FormatException('Invalid ${field.wireName}');
      }
      values[field] = value;
    }
    final minimum = data['batteryCapacityMinimumMah'] == null
        ? 1
        : _integer(data['batteryCapacityMinimumMah'], 1, 65535);
    final maximum = data['batteryCapacityMaximumMah'] == null
        ? 65535
        : _integer(data['batteryCapacityMaximumMah'], minimum, 65535);
    final capacity = values[DeviceControlField.batteryCapacityMah];
    if (capacity is int && (capacity < minimum || capacity > maximum)) {
      throw const FormatException('Invalid battery capacity range');
    }
    return DeviceControlState._(
      _boolean(data['ready']),
      Set.unmodifiable(supported),
      Map.unmodifiable(values),
      DeviceBatteryState.parse(data['battery']),
      minimum,
      maximum,
    );
  }

  final bool ready;
  final Set<String> capabilities;
  final Map<DeviceControlField, Object> values;
  final DeviceBatteryState? battery;
  final int batteryCapacityMinimumMah;
  final int batteryCapacityMaximumMah;
  bool accepts(DeviceControlField field, Object value) =>
      field.accepts(value) &&
      (field != DeviceControlField.batteryCapacityMah ||
          value is int &&
              value >= batteryCapacityMinimumMah &&
              value <= batteryCapacityMaximumMah);
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
        batteryCapacityMinimumMah,
        batteryCapacityMaximumMah,
      );
}

int? _optionalInteger(Object? value, int minimum, int maximum) =>
    value == null ? null : _integer(value, minimum, maximum);

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
