/*
 * @Description: 管理设备发现、去重、连接、超时及离开页面后的取消行为。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 13:35:30
 * @LastEditTime: 2026-10-06 14:21:20
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/discovery_service.dart';

enum DiscoveryPhase {
  searching,
  found,
  empty,
  unavailable,
  failed,
  connecting,
  connected,
  connectionFailed,
}

class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required this.service,
    this.includeDevice,
    this.searchTimeout = const Duration(seconds: 12),
    this.connectionTimeout = const Duration(seconds: 20),
  });

  final DeviceDiscoveryService service;
  final bool Function(DiscoveredDevice device)? includeDevice;
  final Duration searchTimeout;
  final Duration connectionTimeout;
  final Map<String, DiscoveredDevice> _devices = {};
  StreamSubscription<DiscoveredDevice>? _subscription;
  Timer? _timer;
  Completer<bool>? _connectionResult;
  int _generation = 0;
  bool _disposed = false;
  bool _connecting = false;
  Future<void> _cleanup = Future.value();

  DiscoveryPhase phase = DiscoveryPhase.searching;
  DiscoveredDevice? selectedDevice;
  List<DiscoveredDevice> get devices => List.unmodifiable(_devices.values);
  bool get isSearching => phase == DiscoveryPhase.searching;
  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  /// 已添加列表变化时同步发现结果，不干扰正在连接或已完成的确认页面。
  void refreshDevices() {
    if (_disposed ||
        (phase != DiscoveryPhase.searching &&
            phase != DiscoveryPhase.found &&
            phase != DiscoveryPhase.empty)) {
      return;
    }
    final previousCount = _devices.length;
    _devices.removeWhere((_, device) => includeDevice?.call(device) == false);
    if (previousCount == _devices.length) return;
    if (phase == DiscoveryPhase.found && _devices.isEmpty) {
      phase = DiscoveryPhase.empty;
    }
    notifyListeners();
  }

  // 串行清理旧任务，防止快速重试时旧连接的取消影响新连接。
  Future<void> _stopOperations() {
    _timer?.cancel();
    _timer = null;
    final result = _connectionResult;
    _connectionResult = null;
    if (result != null && !result.isCompleted) result.complete(false);
    final subscription = _subscription;
    _subscription = null;
    final cancelConnection = _connecting;
    _connecting = false;
    return _cleanup = _cleanup.then((_) async {
      try {
        await subscription?.cancel();
      } catch (error) {
        debugPrint('Device discovery cleanup failed: $error');
      }
      if (cancelConnection) {
        try {
          await service.cancelConnection();
        } catch (error) {
          debugPrint('Device connection cleanup failed: $error');
        }
      }
    });
  }

  Future<void> search() async {
    if (_disposed) return;
    final generation = ++_generation;
    final cleanup = _stopOperations();
    _devices.clear();
    selectedDevice = null;
    phase = DiscoveryPhase.searching;
    notifyListeners();
    await cleanup;
    if (!_isCurrent(generation)) return;
    try {
      _subscription = service.discover().listen(
        (device) {
          if (!_isCurrent(generation) || !isSearching) return;
          if (device.id.isEmpty || device.name.isEmpty) return;
          if (includeDevice?.call(device) == false) return;
          _devices[device.id] = device;
          notifyListeners();
        },
        onError: (Object error) {
          if (!_isCurrent(generation) || !isSearching) return;
          _finishSearch(error: error);
        },
        onDone: () {
          if (_isCurrent(generation) && isSearching) _finishSearch();
        },
      );
      _timer = Timer(searchTimeout, () {
        if (_isCurrent(generation) && isSearching) _finishSearch();
      });
    } catch (error) {
      if (_isCurrent(generation)) _finishSearch(error: error);
    }
  }

  void _finishSearch({Object? error}) {
    phase = error is DiscoveryUnavailableException
        ? DiscoveryPhase.unavailable
        : error != null
        ? DiscoveryPhase.failed
        : _devices.isEmpty
        ? DiscoveryPhase.empty
        : DiscoveryPhase.found;
    unawaited(_stopOperations());
    notifyListeners();
  }

  Future<void> connect(DiscoveredDevice device) async {
    if (_disposed ||
        phase == DiscoveryPhase.connecting ||
        phase == DiscoveryPhase.connected) {
      return;
    }
    // 已确认过的设备断线后允许主动重试，即使它已被已添加列表过滤。
    final retryingSelected =
        phase == DiscoveryPhase.connectionFailed &&
        selectedDevice?.id == device.id;
    if (!retryingSelected &&
        (!_devices.containsKey(device.id) ||
            includeDevice?.call(device) == false)) {
      return;
    }
    final generation = ++_generation;
    final cleanup = _stopOperations();
    selectedDevice = device;
    phase = DiscoveryPhase.connecting;
    notifyListeners();
    await cleanup;
    if (!_isCurrent(generation)) return;
    _connecting = true;
    final result = Completer<bool>();
    _connectionResult = result;
    _timer = Timer(connectionTimeout, () {
      if (!result.isCompleted) result.complete(false);
    });
    try {
      unawaited(
        service
            .connect(device)
            .then(
              (connected) {
                if (!result.isCompleted) result.complete(connected);
              },
              onError: (Object error, StackTrace stack) {
                if (!result.isCompleted) result.completeError(error, stack);
              },
            ),
      );
      final connected = await result.future;
      if (!_isCurrent(generation)) return;
      if (connected) {
        _connecting = false;
        unawaited(_stopOperations());
        phase = DiscoveryPhase.connected;
      } else {
        phase = DiscoveryPhase.connectionFailed;
        await _stopOperations();
      }
    } catch (_) {
      if (!_isCurrent(generation)) return;
      phase = DiscoveryPhase.connectionFailed;
      await _stopOperations();
    }
    if (_isCurrent(generation)) notifyListeners();
  }

  Future<void> cancelConnection() => search();

  /// 同步服务在后台确认建立的连接，停止本轮查找，防止超时覆盖成功页面。
  void reportConnectionEstablished(DiscoveredDevice device) {
    if (_disposed) return;
    if (phase == DiscoveryPhase.connected && selectedDevice?.id == device.id) {
      return;
    }
    ++_generation;
    selectedDevice = device;
    phase = DiscoveryPhase.connected;
    // 会话已成功，清理页面的发现任务时不能再取消这个连接。
    _connecting = false;
    unawaited(_stopOperations());
    notifyListeners();
  }

  // 连接服务独立于页面；页面可见期间仍需反映已建立会话的断开。
  void reportConnectionLost() {
    if (_disposed || phase != DiscoveryPhase.connected) return;
    phase = DiscoveryPhase.connectionFailed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_stopOperations());
    super.dispose();
  }
}
