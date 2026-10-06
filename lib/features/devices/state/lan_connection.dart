/*
 * @Description: 应用级局域网会话，管理设备确认、心跳、取消和真实在线状态。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 18:37:01
 * @LastEditTime: 2026-10-06 14:12:27
 * @License: GPL 3.0
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/lan_discovery.dart';
import '../data/pairing_store.dart';
import '../domain/discovery_service.dart';

enum LanConnectionPhase {
  offline,
  connecting,
  awaitingApproval,
  connected,
  failed,
}

class LanConnection extends ChangeNotifier implements DeviceDiscoveryService {
  LanConnection({
    this.discovery = const LanDiscovery(),
    this.approvalTimeout = const Duration(seconds: 60),
    this.heartbeatInterval = const Duration(seconds: 5),
    this.heartbeatTimeout = const Duration(seconds: 15),
    this.pairingStore,
    this.reconnectDelay = const Duration(seconds: 3),
  });

  final LanDiscovery discovery;
  final Duration approvalTimeout;
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;
  final DevicePairingStore? pairingStore;
  final Duration reconnectDelay;
  final Map<String, String> _tokens = {};
  Timer? _reconnect;
  StreamSubscription<LanDevice>? _autoScan;
  int _scanGeneration = 0;
  bool _manualDisconnect = false;
  String? _sessionToken;
  bool _serverVerified = false;

  String _proof(String role, String challenge) => Hmac(
    sha256,
    utf8.encode(_sessionToken!),
  ).convert(utf8.encode('$role|${device!.protocolId}|$challenge')).toString();

  Future<void> restorePairings(Iterable<LanDevice> devices) async {
    for (final target in devices) {
      try {
        final token = await pairingStore?.read(target.id);
        if (_disposed) return;
        if (token != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
          _tokens[target.id] = token;
        }
      } catch (_) {
        debugPrint('Device authorization could not be restored.');
      }
    }
    _scheduleReconnect();
  }

  void _stopAutoScan() {
    ++_scanGeneration;
    _reconnect?.cancel();
    final scan = _autoScan;
    _autoScan = null;
    if (scan != null) unawaited(scan.cancel());
  }

  void _scheduleReconnect() {
    if (_disposed ||
        _manualDisconnect ||
        connected ||
        busy ||
        _tokens.isEmpty) {
      return;
    }
    _stopAutoScan();
    _reconnect = Timer(reconnectDelay, () {
      final generation = ++_scanGeneration;
      // 重新发现地址，设备 IP 变化后仍按稳定 ID 找回已授权设备。
      _autoScan = discovery.discover().listen(
        (target) {
          if (generation != _scanGeneration ||
              !_tokens.containsKey(target.id)) {
            return;
          }
          unawaited(_connect(target, automatic: true));
        },
        onError: (Object _) {
          if (generation == _scanGeneration) _scheduleReconnect();
        },
        onDone: () {
          if (generation == _scanGeneration) _scheduleReconnect();
        },
      );
    });
  }

  LanConnectionPhase phase = LanConnectionPhase.offline;
  LanDevice? device;
  String firmware = '';
  int uptimeMs = 0;
  DateTime? lastSeen;
  final Stopwatch _sinceReply = Stopwatch();
  WebSocket? _socket;
  HttpClient? _client;
  Timer? _poll;
  Timer? _deadline;
  Timer? _heartbeat;
  Completer<bool>? _result;
  int _generation = 0;
  bool _disposed = false;

  bool get connected => phase == LanConnectionPhase.connected;
  bool get busy =>
      phase == LanConnectionPhase.connecting ||
      phase == LanConnectionPhase.awaitingApproval;

  @override
  Stream<DiscoveredDevice> discover() async* {
    _stopAutoScan();
    try {
      // 添加设备时按稳定标识排除当前会话，不影响同名设备和断开后的重新发现。
      yield* discovery.discover().where(
        (candidate) => !connected || candidate.id != device?.id,
      );
    } finally {
      _scheduleReconnect();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _close() {
    ++_generation;
    _poll?.cancel();
    _poll = null;
    _deadline?.cancel();
    _heartbeat?.cancel();
    _sinceReply.stop();
    _client?.close(force: true);
    _client = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close());
    final result = _result;
    _result = null;
    if (result != null && !result.isCompleted) result.complete(false);
  }

  void _fail(int generation) {
    if (_disposed || generation != _generation) return;
    final wasConnected = connected;
    _close();
    phase = wasConnected
        ? LanConnectionPhase.offline
        : LanConnectionPhase.failed;
    _notify();
    _scheduleReconnect();
  }

  @override
  Future<bool> connect(DiscoveredDevice target) => _connect(target);

  Future<bool> _connect(
    DiscoveredDevice target, {
    bool automatic = false,
  }) async {
    if (_disposed || target is! LanDevice) return false;
    if (connected && device?.id == target.id) return true;
    _stopAutoScan();
    if (!automatic) _manualDisconnect = false;
    _close();
    final generation = _generation;
    device = target;
    firmware = '';
    uptimeMs = 0;
    lastSeen = null;
    phase = LanConnectionPhase.connecting;
    final result = Completer<bool>();
    _result = result;
    _notify();
    _deadline = Timer(approvalTimeout, () => _fail(generation));
    try {
      final token = _tokens[target.id] ?? await pairingStore?.read(target.id);
      if (_disposed || generation != _generation) return false;
      _sessionToken = token;
      _serverVerified = false;
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      // 局域网设备不经过系统 HTTP 代理，避免 VPN/代理把本地请求发送到外网。
      client.findProxy = (_) => 'DIRECT';
      _client = client;
      final socket = await WebSocket.connect(
        Uri(
          scheme: 'ws',
          host: target.address,
          port: target.port,
          path: '/api/v1/ws',
        ).toString(),
        customClient: client,
        compression: CompressionOptions.compressionOff,
      );
      if (_disposed || generation != _generation) {
        await socket.close();
        return false;
      }
      _socket = socket;
      socket
          .asyncMap((message) => _receive(message, generation))
          .listen(
            (_) {},
            onError: (Object _) => _fail(generation),
            onDone: () => _fail(generation),
          );
      final hostname = Platform.localHostname
          .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
          .trim();
      _send({
        'type': 'hello',
        'pairingVersion': 2,
        'deviceId': target.protocolId,
        'automatic': automatic,
        if (token != null) 'resume': true,
        if (token != null)
          'pairingId': sha256.convert(utf8.encode(token)).toString(),
        'clientName': hostname.isEmpty
            ? 'LilygoBox app'
            : hostname.substring(0, hostname.length.clamp(0, 48)),
      });
    } catch (_) {
      _fail(generation);
    }
    return result.future;
  }

  void _send(Map<String, Object> message) {
    try {
      _socket?.add(jsonEncode({'v': 1, ...message}));
    } catch (_) {
      _fail(_generation);
    }
  }

  Future<void> _receive(Object? message, int generation) async {
    if (_disposed || generation != _generation) return;
    try {
      if (message is! String || message.length > 8192) {
        throw const FormatException();
      }
      final data = jsonDecode(message);
      if (data is! Map<String, dynamic> ||
          data['v'] != 1 ||
          data['deviceId'] != device?.protocolId) {
        throw const FormatException();
      }
      final type = data['type'];
      if (type == 'challenge' && busy && _sessionToken != null) {
        final challenge = data['challenge'];
        if (challenge is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(challenge) ||
            data['proof'] != _proof('server', challenge)) {
          throw const FormatException();
        }
        _serverVerified = true;
        _send({'type': 'authenticate', 'proof': _proof('client', challenge)});
      } else if (type == 'queued' && busy && _serverVerified) {
        // 设备统一按优先级选择控制端；等待期间保留授权，不弹出首次确认。
        _poll ??= Timer.periodic(
          const Duration(seconds: 1),
          (_) => _send({'type': 'poll'}),
        );
      } else if (type == 'disconnected' && (connected || _serverVerified)) {
        // 设备上的主动断开保留凭证，并停止后台重连；手动连接可再次恢复。
        disconnect();
      } else if (type == 'upgrade_required') {
        // 协议不兼容不等于凭证撤销，保留密钥，更新两端后再手动重试。
        debugPrint(
          'Device pairing protocol mismatch; update both applications.',
        );
        _manualDisconnect = true;
        _fail(generation);
      } else if (type == 'busy' || type == 'pairing_full') {
        // 被其他控制端占用或授权名额已满不代表现有凭证失效。
        _fail(generation);
      } else if (type == 'authorization_revoked') {
        final id = device!.id;
        _tokens.remove(id);
        await pairingStore?.delete(id);
        _fail(generation);
      } else if (type == 'waiting' && busy) {
        // 自动恢复不产生新的授权请求；设备清除授权后需用户重新添加。
        if (_sessionToken != null) {
          _tokens.remove(device!.id);
          await pairingStore?.delete(device!.id);
          _fail(generation);
          return;
        }
        phase = LanConnectionPhase.awaitingApproval;
        _poll ??= Timer.periodic(
          const Duration(seconds: 1),
          (_) => _send({'type': 'poll'}),
        );
        _notify();
      } else if ((type == 'ready' && (busy || connected)) ||
          (type == 'pong' && connected)) {
        if (data['firmware'] is! String ||
            data['model'] != device?.model ||
            data['uptimeMs'] is! num ||
            (data['uptimeMs'] as num) < 0) {
          throw const FormatException();
        }
        firmware = data['firmware'] as String;
        uptimeMs = (data['uptimeMs'] as num).toInt();
        lastSeen = DateTime.now();
        _sinceReply
          ..reset()
          ..start();
        if (type == 'ready' && !connected) {
          if (_sessionToken != null && !_serverVerified) {
            throw const FormatException();
          }
          if (_sessionToken != null) {
            _tokens[device!.id] = _sessionToken!;
          }
          final token = data['pairingToken'];
          if (_sessionToken == null && pairingStore != null && token == null) {
            throw const FormatException('Missing initial pairing credential');
          }
          if (token != null) {
            if (token is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
              throw const FormatException();
            }
            if (pairingStore != null) {
              await pairingStore!.write(device!.id, token);
              if (_disposed || generation != _generation) return;
            }
            _tokens[device!.id] = token;
          }
          _poll?.cancel();
          _deadline?.cancel();
          phase = LanConnectionPhase.connected;
          final result = _result;
          _result = null;
          if (result != null && !result.isCompleted) result.complete(true);
          _heartbeat = Timer.periodic(heartbeatInterval, (_) {
            if (_sinceReply.elapsed >= heartbeatTimeout) {
              _fail(generation);
            } else {
              _send({'type': 'ping'});
            }
          });
        }
        _notify();
      } else {
        throw const FormatException();
      }
    } catch (_) {
      _fail(generation);
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _stopAutoScan();
    _close();
    phase = LanConnectionPhase.offline;
    _notify();
  }

  @override
  Future<void> cancelConnection() async {
    if (busy) disconnect();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopAutoScan();
    _close();
    super.dispose();
  }
}
