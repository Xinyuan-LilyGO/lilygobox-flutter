/*
 * @Description: 应用级局域网会话，管理设备确认、心跳、取消和真实在线状态。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 18:37:01
 * @LastEditTime: 2026-10-13 12:00:00
 * @License: GPL 3.0
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/firmware_update_service.dart';
import '../data/lan_discovery.dart';
import '../data/pairing_store.dart';
import '../domain/device_control.dart';
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
    this.clientIdProvider,
    this.reconnectDelay = const Duration(seconds: 3),
  });

  final LanDiscovery discovery;
  final Duration approvalTimeout;
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;
  final DevicePairingStore? pairingStore;
  final Future<String> Function()? clientIdProvider;
  final Duration reconnectDelay;
  final Map<String, String> _tokens = {};
  final Map<String, String> _fingerprints = {};
  final Map<String, Future<void>> _pairingOperations = {};
  final Map<String, Future<bool>> _forgettingDevices = {};
  final Set<String> _forgottenDevices = {};
  String? _peerFingerprint;
  bool _peerTrusted = false;
  bool identityChanged = false;
  Timer? _reconnect;
  StreamSubscription<LanDevice>? _autoScan;
  int _scanGeneration = 0;
  bool _manualDisconnect = false;
  String? _sessionToken;
  bool _serverVerified = false;
  final Map<String, DeviceControlState> _deviceStates = {};
  final Map<DeviceControlField, Object> _controlTargets = {};
  MapEntry<DeviceControlField, Object>? _inFlightControl;
  Timer? _controlDebounce;
  Timer? _controlPoll;
  Timer? _controlTimeout;
  Timer? _statePoll;
  HttpServer? _localFirmwareServer;
  int _localFirmwareGeneration = 0;
  List<File> _localFirmwareFiles = const [];
  Completer<bool>? _firmwareStartReply;
  Completer<bool>? _firmwareInstallReply;
  Completer<bool>? _firmwareCancelReply;
  bool firmwareRestartRequested = false;
  int _controlRequestId = 0;
  bool _controlsReady = false;
  String? lastControlError;
  final Map<DeviceControlField, Completer<bool>> _controlCompletions = {};

  /// 等待设备确认保存结果；断线或失败时返回 false，不把目标值当成成功值。
  Future<bool> saveControl(DeviceControlField field, Object value) {
    final id = device?.id;
    final state = id == null ? null : _deviceStates[id];
    if (id == null ||
        !controlsReadyFor(id) ||
        state == null ||
        !state.supports(field) ||
        !state.accepts(field, value) ||
        _controlCompletions.containsKey(field)) {
      return Future.value(false);
    }
    final completion = Completer<bool>();
    _controlCompletions[field] = completion;
    setControl(field, value);
    return completion.future;
  }

  DeviceControlState? controlStateFor(String id) {
    final state = _deviceStates[id];
    if (device?.id != id || state == null) return state;
    return state.withTargets({
      if (_inFlightControl case final target?) target.key: target.value,
      ..._controlTargets,
    });
  }

  bool controlsReadyFor(String id) =>
      connected && device?.id == id && _controlsReady;

  /// 单字段目标值串行提交；连续滑动只保留末次值，断线后不重放旧请求。
  void setControl(DeviceControlField field, Object value) {
    final id = device?.id;
    if (id == null ||
        !controlsReadyFor(id) ||
        !(_deviceStates[id]?.supports(field) ?? false) ||
        !(_deviceStates[id]?.accepts(field, value) ?? false)) {
      return;
    }
    _controlTargets[field] = value;
    lastControlError = null;
    _controlDebounce?.cancel();
    _controlDebounce = Timer(const Duration(milliseconds: 180), _flushControls);
    _notify();
  }

  void _flushControls() {
    if (!connected ||
        !_controlsReady ||
        (_controlDebounce?.isActive ?? false) ||
        _inFlightControl != null ||
        _controlTargets.isEmpty) {
      return;
    }
    final target = _controlTargets.entries.first;
    _controlTargets.remove(target.key);
    _inFlightControl = target;
    final requestId = ++_controlRequestId;
    _send({
      'type': 'control.set',
      'requestId': requestId,
      'field': target.key.wireName,
      'value': target.value,
    });
    final generation = _generation;
    _controlTimeout = Timer(const Duration(seconds: 10), () {
      if (_generation != generation) return;
      lastControlError = 'timeout';
      // 执行结果不确定时结束会话，重新认证与同步后才允许继续操作。
      _fail(generation);
    });
  }

  void _readControlState(Map<String, dynamic> data) {
    if (!data.containsKey('state')) return;
    final state = DeviceControlState.parse(data['state']);
    _deviceStates[device!.id] = state;
    _controlsReady = state.ready;
  }

  String _proof(String role, String challenge) => Hmac(
    sha256,
    utf8.encode(_sessionToken!),
  ).convert(utf8.encode('$role|${device!.protocolId}|$challenge')).toString();

  // 同一设备的安全存储操作串行执行，删除必须排在尚未完成的配对写入之后。
  Future<T> _pairingOperation<T>(String id, Future<T> Function() operation) {
    final previous = _pairingOperations[id] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    final completion = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _pairingOperations[id] = completion;
    unawaited(
      completion.then((_) {
        if (identical(_pairingOperations[id], completion)) {
          _pairingOperations.remove(id);
        }
      }),
    );
    return result;
  }

  Future<void> restorePairings(Iterable<LanDevice> devices) async {
    for (final target in devices) {
      if (_forgottenDevices.contains(target.id)) continue;
      try {
        final token = await _pairingOperation(
          target.id,
          () async => pairingStore?.read(target.id),
        );
        if (_disposed) return;
        if (_forgottenDevices.contains(target.id)) continue;
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
  String wirelessFirmware = '';
  FirmwareHardware? firmwareHardware;
  FirmwareRelease? firmwareRelease;
  bool firmwareUpdateChecking = false;
  String? firmwareUpdateError;
  String firmwareUpdateStage = 'idle';
  int firmwareUpdateProgress = 0;
  String firmwareUpdateMessage = '';
  int firmwareReceivedBytes = 0;
  int firmwareTotalBytes = 0;
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

  /// 通过临时局域网 HTTP 服务交付需要更新的固件，未变化的组件不提供文件。
  /// 设备端收到 URL 后仍使用原有 OTA 校验、写入和回滚流程。
  Future<bool> startLocalMainFirmwareUpdate({
    required File? firmware,
    required String version,
    required String sha256,
    required int mainSize,
    required File? wirelessFirmware,
    required String wirelessVersion,
    required String wirelessSha256,
    required int wirelessSize,
  }) async {
    if (_firmwareCancelReply != null) return false;
    final target = device;
    final generation = _generation;
    final localGeneration = ++_localFirmwareGeneration;
    if (!connected ||
        firmwareRestartRequested ||
        target == null ||
        (firmware == null && wirelessFirmware == null) ||
        (firmware != null &&
            (!await firmware.exists() ||
                await firmware.length() != mainSize)) ||
        (wirelessFirmware != null &&
            (!await wirelessFirmware.exists() ||
                await wirelessFirmware.length() != wirelessSize))) {
      return false;
    }
    if (mainSize <= 0 ||
        wirelessSize <= 0 ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256) ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(wirelessSha256)) {
      return false;
    }
    if (localGeneration != _localFirmwareGeneration) return false;
    await _closeLocalFirmwareServer();
    final address = await _localFirmwareAddress(target);
    if (!connected ||
        generation != _generation ||
        localGeneration != _localFirmwareGeneration) {
      return false;
    }
    final token = _localFirmwareToken();
    final wirelessToken = _localFirmwareToken();
    final server = await HttpServer.bind(address, 0);
    if (!connected ||
        generation != _generation ||
        localGeneration != _localFirmwareGeneration) {
      await server.close(force: true);
      return false;
    }
    _localFirmwareFiles = [
      if (firmware != null) firmware,
      if (wirelessFirmware != null) wirelessFirmware,
    ];
    _localFirmwareServer = server;
    server.listen((request) async {
      final isMain = request.uri.path == '/$token';
      final isWireless = request.uri.path == '/$wirelessToken';
      final file = isMain
          ? firmware
          : isWireless
          ? wirelessFirmware
          : null;
      if (file == null || request.method != 'GET') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType(
        'application',
        'octet-stream',
      );
      request.response.contentLength = isMain ? mainSize : wirelessSize;
      try {
        await request.response.addStream(file.openRead());
        await request.response.close();
      } catch (_) {
        request.response.done.ignore();
      }
    });
    firmwareUpdateStage = 'starting';
    firmwareUpdateError = null;
    firmwareReceivedBytes = 0;
    firmwareTotalBytes = 0;
    final reply = Completer<bool>();
    _firmwareStartReply = reply;
    _send({
      'type': 'firmware.local.start',
      'mainUrl': firmware == null
          ? ''
          : 'http://${address.address}:${server.port}/$token',
      'wirelessUrl': wirelessFirmware == null
          ? ''
          : 'http://${address.address}:${server.port}/$wirelessToken',
      'mainVersion': version,
      'wirelessVersion': wirelessVersion,
      'mainSize': mainSize,
      'wirelessSize': wirelessSize,
      'mainSha256': sha256.toLowerCase(),
      'wirelessSha256': wirelessSha256.toLowerCase(),
    });
    final accepted = await reply.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
    if (identical(_firmwareStartReply, reply)) _firmwareStartReply = null;
    if (!accepted && localGeneration == _localFirmwareGeneration) {
      await _closeLocalFirmwareServer();
    }
    return accepted && localGeneration == _localFirmwareGeneration;
  }

  Future<InternetAddress> _localFirmwareAddress(LanDevice target) async {
    if (InternetAddress(target.address).isLoopback) {
      return InternetAddress.loopbackIPv4;
    }
    final peer = target.localAddress != null
        ? target
        : await discovery
              .discover()
              .timeout(const Duration(seconds: 5))
              .firstWhere(
                (peer) =>
                    peer.id == target.id &&
                    peer.address == target.address &&
                    peer.localAddress != null,
                orElse: () =>
                    throw const SocketException('未找到设备所在的本机网卡，请重新连接设备'),
              );
    final address = peer.localAddress!;
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final assigned = interfaces
        .expand((item) => item.addresses)
        .any((item) => item.address == address.address);
    if (!assigned ||
        address.isLoopback ||
        address.address == target.address ||
        address.type != InternetAddressType.IPv4) {
      throw const SocketException('设备所在的本机网卡已变化，请重新连接设备');
    }
    return address;
  }

  String _localFirmwareToken() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  Future<void> _closeLocalFirmwareServer() async {
    final server = _localFirmwareServer;
    final files = _localFirmwareFiles;
    _localFirmwareServer = null;
    _localFirmwareFiles = const [];
    await server?.close(force: true);
    if (files.isNotEmpty) {
      final directory = files.first.parent;
      for (final file in files) {
        try {
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // 临时文件清理失败不应影响连接状态。
        }
      }
      try {
        if (await directory.exists()) await directory.delete();
      } on FileSystemException {
        // 临时目录可能仍被系统占用，交给系统临时目录清理。
      }
    }
  }

  /// 取消当前应用发起的局域网固件传输并清理临时资源。
  Future<void> cancelLocalFirmwareUpdate() async {
    final localGeneration = ++_localFirmwareGeneration;
    if (!(_firmwareStartReply?.isCompleted ?? true)) {
      _firmwareStartReply!.complete(false);
    }
    try {
      if (connected) {
        final reply = Completer<bool>();
        _firmwareCancelReply = reply;
        _send({'type': 'firmware.local.cancel'});
        final accepted = await reply.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        );
        if (identical(_firmwareCancelReply, reply)) _firmwareCancelReply = null;
        if (!accepted && connected) throw StateError('设备未确认取消，请查看设备状态');
      }
    } finally {
      if (localGeneration == _localFirmwareGeneration) {
        await _closeLocalFirmwareServer();
      }
    }
  }

  /// 请求设备安装已经准备好的固件并重启。
  Future<bool> installLocalFirmwareUpdate() async {
    if (!connected ||
        firmwareRestartRequested ||
        firmwareUpdateStage != 'readyToInstall') {
      return false;
    }
    firmwareRestartRequested = true;
    final reply = Completer<bool>();
    _firmwareInstallReply = reply;
    _send({'type': 'firmware.local.install'});
    _notify();
    final accepted = await reply.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
    if (identical(_firmwareInstallReply, reply)) _firmwareInstallReply = null;
    if (!accepted && connected) firmwareRestartRequested = false;
    _notify();
    return accepted;
  }

  /// 后台读取当前设备对应的 OTA 清单，失败时保持更新入口隐藏。
  Future<FirmwareRelease?> checkFirmwareUpdate() async {
    final target = device;
    if (!connected || target == null || firmwareUpdateChecking) {
      return firmwareRelease;
    }
    firmwareUpdateChecking = true;
    final generation = _generation;
    firmwareUpdateError = null;
    _notify();
    try {
      final release = await const FirmwareUpdateService().check(
        model: target.model,
        modelVersion: target.modelVersion,
        mainCurrent: firmware,
        wirelessCurrent: wirelessFirmware,
        hardware: firmwareHardware,
      );
      if (_disposed || generation != _generation) return null;
      firmwareRelease = release;
    } catch (error) {
      if (_disposed || generation != _generation) return null;
      firmwareRelease = null;
      firmwareUpdateError = error.toString();
    } finally {
      if (!_disposed && generation == _generation) {
        firmwareUpdateChecking = false;
        _notify();
      }
    }
    return firmwareRelease;
  }

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
    if (!(_firmwareCancelReply?.isCompleted ?? true)) {
      _firmwareCancelReply!.complete(false);
    }
    if (!(_firmwareStartReply?.isCompleted ?? true)) {
      _firmwareStartReply!.complete(false);
    }
    if (!(_firmwareInstallReply?.isCompleted ?? true)) {
      _firmwareInstallReply!.complete(false);
    }
    unawaited(_closeLocalFirmwareServer());
    _controlDebounce?.cancel();
    _controlPoll?.cancel();
    _controlTimeout?.cancel();
    _statePoll?.cancel();
    _controlTargets.clear();
    for (final completion in _controlCompletions.values) {
      completion.complete(false);
    }
    _controlCompletions.clear();
    _inFlightControl = null;
    _controlsReady = false;
    ++_generation;
    firmwareHardware = null;
    firmwareUpdateChecking = false;
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

  void _fail(int generation, {String? reason}) {
    if (_disposed || generation != _generation) return;
    if (reason != null) debugPrint('LAN connection ended: $reason');
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
    if (_disposed ||
        target is! LanDevice ||
        _forgettingDevices.containsKey(target.id) ||
        (automatic && _forgottenDevices.contains(target.id))) {
      return false;
    }
    if (!automatic) _forgottenDevices.remove(target.id);
    if (connected && device?.id == target.id) return true;
    _stopAutoScan();
    if (!automatic) _manualDisconnect = false;
    _close();
    final generation = _generation;
    device = target;
    firmware = '';
    wirelessFirmware = '';
    firmwareHardware = null;
    firmwareUpdateChecking = false;
    firmwareRelease = null;
    firmwareRestartRequested = false;
    firmwareUpdateError = null;
    uptimeMs = 0;
    lastSeen = null;
    phase = LanConnectionPhase.connecting;
    identityChanged = false;
    _peerFingerprint = null;
    _peerTrusted = false;
    final result = Completer<bool>();
    _result = result;
    _notify();
    _deadline = Timer(approvalTimeout, () => _fail(generation));
    try {
      final clientId = await clientIdProvider?.call();
      if (clientId != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(clientId)) {
        throw const FormatException('Invalid application identity');
      }
      if (_disposed || generation != _generation) return false;
      final token =
          _tokens[target.id] ??
          await _pairingOperation(
            target.id,
            () async => pairingStore?.read(target.id),
          );
      final fingerprint =
          _fingerprints[target.id] ??
          await _pairingOperation(
            target.id,
            () async => pairingStore?.readFingerprint(target.id),
          );
      if (_disposed || generation != _generation) return false;
      _sessionToken = token;
      _serverVerified = false;
      // 不使用公共 CA 信任链；设备身份按首次配对保存的 SHA-256 证书指纹验证。
      final tlsContext = SecurityContext(withTrustedRoots: false)
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;
      final client = HttpClient(context: tlsContext)
        ..connectionTimeout = const Duration(seconds: 8);
      client.badCertificateCallback = (certificate, host, port) {
        if (_disposed ||
            generation != _generation ||
            host != target.address ||
            port != target.port) {
          return false;
        }
        final received = sha256.convert(certificate.der).toString();
        if (fingerprint != null && fingerprint != received) {
          identityChanged = true;
          _manualDisconnect = true;
          return false;
        }
        // 首次仅临时接受证书，设备确认 / 授权校验成功后才保存。
        _peerFingerprint = received;
        _peerTrusted = fingerprint != null;
        return true;
      };
      // 局域网设备不经过系统 HTTP 代理，避免 VPN/代理把本地请求发送到外网。
      client.findProxy = (_) => 'DIRECT';
      _client = client;
      final socket = await WebSocket.connect(
        Uri(
          scheme: 'wss',
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
      if (_peerFingerprint == null) {
        await socket.close();
        throw const HandshakeException('Missing device certificate');
      }
      _socket = socket;
      socket
          .asyncMap((message) => _receive(message, generation))
          .listen(
            (_) {},
            onError: (Object error) =>
                _fail(generation, reason: 'WebSocket error: $error'),
            onDone: () => _fail(
              generation,
              reason:
                  'WebSocket closed: ${socket.closeCode} ${socket.closeReason ?? ''}',
            ),
          );
      final hostname = Platform.localHostname
          .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
          .trim();
      _send({
        'type': 'hello',
        'pairingVersion': 2,
        if (clientId != null) 'clientId': clientId,
        'deviceId': target.protocolId,
        'automatic': automatic,
        if (token != null) 'resume': true,
        if (token != null)
          'pairingId': sha256.convert(utf8.encode(token)).toString(),
        'clientName': hostname.isEmpty
            ? 'LilygoBox app'
            : hostname.substring(0, hostname.length.clamp(0, 48)),
      });
    } catch (error) {
      _fail(generation, reason: 'WebSocket connection failed: $error');
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

  /// 接收设备的显示名称，保留用于连接、授权和去重的稳定身份。
  void _readDeviceName(Map<String, dynamic> data) {
    final current = device;
    final name = data['name'];
    final version = data['modelVersion'] ?? current?.modelVersion;
    // 兼容旧固件未携带名称的状态消息。
    if (current == null || name == null) return;
    if (name is! String || name.trim().isEmpty || name.length > 64) {
      throw const FormatException('Invalid device name');
    }
    if (version is! String || version.length > 64) {
      throw const FormatException('Invalid device model version');
    }
    if (name == current.name && version == current.modelVersion) return;
    device = LanDevice(
      id: current.id,
      protocolId: current.protocolId,
      name: name,
      address: current.address,
      localAddress: current.localAddress,
      port: current.port,
      model: current.model,
      modelVersion: version.replaceFirst(RegExp(r'^v'), ''),
    );
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
      if (_sessionToken != null &&
          !_peerTrusted &&
          !_serverVerified &&
          (type == 'authorization_revoked' || type == 'waiting')) {
        // 尚未建立设备信任时，不允许对端消息擦除现有授权。
        identityChanged = true;
        _manualDisconnect = true;
        throw const FormatException('Device identity not verified');
      }
      if (type == 'state' && connected) {
        _readDeviceName(data);
        _readControlState(data);
        _notify();
      } else if (type == 'firmware.local.started' && connected) {
        // 设备已接受地址；后续校验、写入和重启由设备端 OTA 状态机完成。
        firmwareUpdateError = null;
        if (!(_firmwareStartReply?.isCompleted ?? true)) {
          _firmwareStartReply!.complete(true);
        }
        _notify();
      } else if (type == 'firmware.local.rejected' && connected) {
        firmwareUpdateError = '设备拒绝了本地固件更新';
        if (!(_firmwareStartReply?.isCompleted ?? true)) {
          _firmwareStartReply!.complete(false);
        }
        _notify();
      } else if (type == 'firmware.local.install.started' && connected) {
        if (!(_firmwareInstallReply?.isCompleted ?? true)) {
          _firmwareInstallReply!.complete(true);
        }
        _notify();
      } else if (type == 'firmware.local.install.rejected' && connected) {
        firmwareUpdateError = '设备拒绝重启安装';
        if (!(_firmwareInstallReply?.isCompleted ?? true)) {
          _firmwareInstallReply!.complete(false);
        }
        _notify();
      } else if (type == 'firmware.local.cancelled' && connected) {
        if (!(_firmwareCancelReply?.isCompleted ?? true)) {
          _firmwareCancelReply!.complete(true);
        }
        firmwareUpdateStage = 'cancelled';
        _notify();
      } else if (type == 'firmware.local.cancel.rejected' && connected) {
        if (!(_firmwareCancelReply?.isCompleted ?? true)) {
          _firmwareCancelReply!.complete(false);
        }
        firmwareUpdateError = '当前阶段无法取消更新';
        _notify();
      } else if (type == 'firmware.local.status' && connected) {
        if (!(_firmwareStartReply?.isCompleted ?? true)) return;
        if (data['stage'] is! String ||
            data['progress'] is! num ||
            data['busy'] is! bool ||
            data['message'] is! String) {
          throw const FormatException();
        }
        firmwareUpdateStage = data['stage'] as String;
        firmwareUpdateProgress = (data['progress'] as num).round().clamp(
          0,
          100,
        );
        firmwareUpdateMessage = data['message'] as String;
        firmwareReceivedBytes = (data['receivedBytes'] as num?)?.toInt() ?? 0;
        firmwareTotalBytes = (data['totalBytes'] as num?)?.toInt() ?? 0;
        if (firmwareUpdateStage == 'readyToInstall' ||
            firmwareUpdateStage == 'failed' ||
            firmwareUpdateStage == 'cancelled') {
          unawaited(_closeLocalFirmwareServer());
        }
        _notify();
      } else if ((type == 'control.queued' || type == 'control.result') &&
          connected) {
        if (data['requestId'] != _controlRequestId ||
            _inFlightControl == null) {
          return;
        }
        if (type == 'control.queued') {
          _controlPoll?.cancel();
          _controlPoll = Timer(const Duration(milliseconds: 150), () {
            _send({'type': 'control.poll', 'requestId': _controlRequestId});
          });
        } else {
          if (data['ok'] is! bool ||
              data['error'] is! String ||
              !data.containsKey('state')) {
            throw const FormatException();
          }
          _controlPoll?.cancel();
          _controlTimeout?.cancel();
          _readDeviceName(data);
          _readControlState(data);
          _controlCompletions
              .remove(_inFlightControl!.key)
              ?.complete(data['ok'] == true);
          _inFlightControl = null;
          lastControlError = data['ok'] == true
              ? null
              : data['error'] as String;
          if (lastControlError != null) {
            debugPrint('Device control failed: $lastControlError');
          }
          _notify();
          _flushControls();
        }
      } else if (type == 'challenge' && busy && _sessionToken != null) {
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
        await _pairingOperation(id, () async => pairingStore?.delete(id));
        _fail(generation);
      } else if (type == 'waiting' && busy) {
        // 自动恢复不产生新的授权请求；设备清除授权后需用户重新添加。
        if (_sessionToken != null) {
          final id = device!.id;
          _tokens.remove(id);
          await _pairingOperation(id, () async => pairingStore?.delete(id));
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
            (data['wirelessFirmware'] != null &&
                data['wirelessFirmware'] is! String) ||
            data['model'] != device?.model ||
            data['uptimeMs'] is! num ||
            (data['uptimeMs'] as num) < 0) {
          throw const FormatException();
        }
        firmware = data['firmware'] as String;
        wirelessFirmware = data['wirelessFirmware'] as String? ?? '';
        firmwareHardware = FirmwareHardware.fromJson(data['chips']);
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
          }
          final id = device!.id;
          final fingerprint = _peerFingerprint!;
          if (_fingerprints[id] != fingerprint) {
            await _pairingOperation(
              id,
              () async => pairingStore?.writeFingerprint(id, fingerprint),
            );
            if (_disposed || generation != _generation) return;
            _fingerprints[id] = fingerprint;
          }
          if (token is String) {
            await _pairingOperation(
              id,
              () async => pairingStore?.write(id, token),
            );
            if (_disposed || generation != _generation) return;
            _tokens[id] = token;
          }
          _poll?.cancel();
          _deadline?.cancel();
          phase = LanConnectionPhase.connected;
          _readControlState(data);
          if (data['controlVersion'] == 1) {
            _statePoll = Timer.periodic(const Duration(seconds: 1), (_) {
              _send({'type': 'state.get'});
            });
          }
          final result = _result;
          _result = null;
          if (result != null && !result.isCompleted) result.complete(true);
          _heartbeat = Timer.periodic(heartbeatInterval, (_) {
            if (_sinceReply.elapsed >= heartbeatTimeout) {
              _fail(generation, reason: 'Heartbeat reply timed out');
            } else {
              _send({'type': 'ping'});
            }
          });
        }
        if (connected) _readControlState(data);
        if (connected) _readDeviceName(data);
        if (connected && type == 'ready') unawaited(checkFirmwareUpdate());
        _notify();
      } else {
        throw const FormatException();
      }
    } catch (error) {
      _fail(generation, reason: 'WebSocket message or state error: $error');
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _stopAutoScan();
    _close();
    phase = LanConnectionPhase.offline;
    _notify();
  }

  /// 删除指定设备的本地授权与信任，并阻止旧异步结果恢复其自动连接。
  Future<bool> forgetDevice(String deviceId) {
    if (_disposed) return Future.value(false);
    final id = LanDevice.normalizeId(deviceId);
    final pending = _forgettingDevices[id];
    if (pending != null) return pending;
    // 先登记任务，再开始通知；重复点击和通知回调不能启动第二次删除。
    final result = Completer<bool>();
    _forgettingDevices[id] = result.future;
    unawaited(
      _forgetDevice(id).then((success) {
        _forgettingDevices.remove(id);
        result.complete(success);
      }),
    );
    return result.future;
  }

  Future<bool> _forgetDevice(String id) async {
    _forgottenDevices.add(id);
    _stopAutoScan();
    _tokens.remove(id);
    _fingerprints.remove(id);
    _deviceStates.remove(id);
    if (device?.id == id) {
      _close();
      device = null;
      phase = LanConnectionPhase.offline;
      firmware = '';
      wirelessFirmware = '';
      firmwareHardware = null;
      uptimeMs = 0;
      lastSeen = null;
      identityChanged = false;
      _sessionToken = null;
      _peerFingerprint = null;
      _peerTrusted = false;
      _serverVerified = false;
      _notify();
    }
    try {
      await _pairingOperation(id, () async {
        await pairingStore?.delete(id);
        await pairingStore?.deleteFingerprint(id);
      });
      return true;
    } catch (_) {
      debugPrint('Device authorization could not be removed.');
      return false;
    } finally {
      // 删除离线设备不能断开其他设备；剩余授权仍可按原规则自动恢复。
      _scheduleReconnect();
    }
  }

  /// 用户确认设备身份变化后清除本地信任，下次连接须在设备上重新授权。
  Future<bool> resetDeviceTrust(String id) async {
    if (_disposed ||
        busy ||
        connected ||
        device?.id != id ||
        !identityChanged) {
      return false;
    }
    disconnect();
    final generation = _generation;
    try {
      await _pairingOperation(id, () async {
        await pairingStore?.delete(id);
        await pairingStore?.deleteFingerprint(id);
      });
      if (_disposed || generation != _generation) return false;
      _tokens.remove(id);
      _fingerprints.remove(id);
      identityChanged = false;
      _notify();
      return true;
    } catch (_) {
      return false;
    }
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
