/*
 * @Description: 在应用数据目录保存普通配置，串行合并写入并报告读写失败。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 20:29:43
 * @LastEditTime: 2026-10-03 20:29:43
 * @License: GPL 3.0
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PreferencesStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesStorage implements PreferencesStorage {
  static const key = 'lilygobox.preferences.v1';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(key, value)) {
      throw StateError('Unable to save application preferences');
    }
  }
}

enum PreferencesError { read, write }

class AppPreferences extends ChangeNotifier {
  AppPreferences._(this._storage);

  final PreferencesStorage _storage;
  Map<String, dynamic> _values = {};
  final Map<String, dynamic> _pending = {};
  Future<void>? _writing;
  Timer? _saveTimer;
  bool _loaded = false;
  bool _disposed = false;
  PreferencesError? error;

  static Future<AppPreferences> load({PreferencesStorage? storage}) async {
    final preferences = AppPreferences._(storage ?? SharedPreferencesStorage());
    await preferences._read();
    return preferences;
  }

  Future<void> _read() async {
    try {
      final raw = await _storage.read();
      final decoded = raw == null ? <String, dynamic>{} : jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      _values = {...decoded, ..._pending};
      _loaded = true;
      error = null;
    } catch (_) {
      // 读取失败时先使用默认值；禁止将默认值覆盖到原配置上。
      error = PreferencesError.read;
    }
    _notify();
  }

  String stringValue(String key, String fallback) =>
      _values[key] is String ? _values[key] as String : fallback;

  bool boolValue(String key, bool fallback) =>
      _values[key] is bool ? _values[key] as bool : fallback;

  double doubleValue(String key, double fallback, double min, double max) {
    final value = _values[key];
    if (value is! num || !value.isFinite) return fallback;
    return value.toDouble().clamp(min, max);
  }

  List<String> stringList(String key) {
    final value = _values[key];
    if (value is! List) return [];
    return value
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList();
  }

  void setValue(String key, Object value) {
    if (_disposed || (_values[key] == value && !_pending.containsKey(key))) {
      return;
    }
    final snapshot = value is List<String> ? List<String>.of(value) : value;
    _values[key] = snapshot;
    _pending[key] = snapshot;
    _notify();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () {
      _saveTimer = null;
      unawaited(flush());
    });
  }

  // 快速拖动或连续修改时合并等待中的值，始终按顺序写入最新配置。
  Future<bool> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_pending.isEmpty && _writing == null) return true;
    if (!_loaded) return false;
    while (_pending.isNotEmpty || _writing != null) {
      _writing ??= _drain();
      final writing = _writing!;
      await writing;
      if (identical(_writing, writing)) _writing = null;
      if (error != null) return false;
    }
    return true;
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final changes = Map<String, dynamic>.of(_pending);
      _pending.clear();
      try {
        await _storage.write(jsonEncode(_values));
        error = null;
      } catch (_) {
        _pending.addAll({...changes, ..._pending});
        error = PreferencesError.write;
        _notify();
        return;
      }
    }
    _notify();
  }

  Future<void> retry() async {
    if (!_loaded) await _read();
    await flush();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(flush());
    super.dispose();
  }
}
