/*
 * @Description: 使用限时 UDP 广播发现局域网设备，校验协议和本轮随机标识。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 18:37:01
 * @LastEditTime: 2026-10-04 18:58:06
 * @License: GPL 3.0
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/discovery_service.dart';

class LanDevice extends DiscoveredDevice {
  const LanDevice({
    required super.id,
    required super.name,
    required this.address,
    required this.port,
    required this.model,
    this.modelVersion = '',
    this.localAddress,
    String? protocolId,
  }) : _protocolId = protocolId;

  final String address;
  final int port;
  final String model;
  final String modelVersion;

  /// 本次发现响应实际经过的本机地址，不持久化，也不读取设备声明的地址。
  final InternetAddress? localAddress;

  String get modelLabel =>
      modelVersion.isEmpty ? model : '$model v$modelVersion';
  final String? _protocolId;

  // 旧固件仍使用带前缀的协议标识；存储和界面统一使用无前缀 ID。
  String get protocolId => _protocolId ?? id;

  static String normalizeId(String value) =>
      RegExp(r'^lgb-[0-9a-f]{12}$').hasMatch(value)
      ? value.substring(4)
      : value;

  // 设备 ID 来源于出厂基础 MAC，不是 IP 地址或临时网卡地址。
  String get macAddress => RegExp(r'.{2}')
      .allMatches(normalizeId(id))
      .map((match) => match.group(0)!.toUpperCase())
      .join(':');

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'port': port,
    'model': model,
    'modelVersion': modelVersion,
    if (protocolId != id) 'protocolId': protocolId,
  };

  static LanDevice? fromJson(Object? value, {InternetAddress? localAddress}) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final name = value['name'];
    final address = value['address'];
    final port = value['port'];
    final model = value['model'];
    final modelVersion = value['modelVersion'] ?? '';
    final protocolId = value['protocolId'] ?? id;
    if (id is! String ||
        !RegExp(r'^(lgb-)?[0-9a-f]{12}$').hasMatch(id) ||
        protocolId is! String ||
        !RegExp(r'^(lgb-)?[0-9a-f]{12}$').hasMatch(protocolId) ||
        normalizeId(protocolId) != normalizeId(id) ||
        name is! String ||
        name.isEmpty ||
        name.length > 64 ||
        address is! String ||
        InternetAddress.tryParse(address)?.type != InternetAddressType.IPv4 ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        model is! String ||
        model.isEmpty ||
        model.length > 64 ||
        modelVersion is! String ||
        modelVersion.length > 64) {
      return null;
    }
    return LanDevice(
      id: normalizeId(id),
      protocolId: protocolId,
      name: name,
      address: address,
      port: port,
      model: model,
      modelVersion: modelVersion.replaceFirst(RegExp(r'^v'), ''),
      localAddress: localAddress,
    );
  }
}

class LanDiscovery {
  const LanDiscovery({
    this.port = 18463,
    this.target = '255.255.255.255',
    this.duration = const Duration(seconds: 10),
    this.bindAddresses,
  });

  final int port;
  final String target;
  final Duration duration;
  // 用于回环联调；实际运行枚举各个 IPv4 网卡，不假设子网掩码为 /24。
  final List<InternetAddress>? bindAddresses;

  Stream<LanDevice> discover() {
    final random = Random.secure();
    final nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final request = utf8.encode(
      jsonEncode({'v': 1, 'type': 'lilygobox.discover', 'nonce': nonce}),
    );
    final sockets = <RawDatagramSocket>[];
    Timer? retry;
    Timer? timeout;
    var stopped = false;
    late StreamController<LanDevice> controller;

    void stop() {
      stopped = true;
      retry?.cancel();
      timeout?.cancel();
      for (final socket in sockets) {
        socket.close();
      }
      sockets.clear();
    }

    void send() {
      for (final socket in sockets) {
        try {
          socket.send(request, InternetAddress(target), port);
        } on SocketException {
          // 继续尝试其他网卡。
        }
      }
    }

    Future<void> start() async {
      try {
        final addresses =
            bindAddresses ??
            (await NetworkInterface.list(type: InternetAddressType.IPv4))
                .expand((network) => network.addresses)
                .where((address) => !address.isLoopback)
                .toList();
        for (final address in addresses) {
          if (stopped) return;
          RawDatagramSocket socket;
          try {
            socket = await RawDatagramSocket.bind(address, 0);
          } on SocketException {
            continue;
          }
          if (stopped) {
            socket.close();
            return;
          }
          socket.broadcastEnabled = true;
          sockets.add(socket);
          socket.listen(
            (event) {
              if (stopped || event != RawSocketEvent.read) return;
              Datagram? packet;
              while ((packet = socket.receive()) != null) {
                if (packet!.data.length > 2048) continue;
                try {
                  final data = jsonDecode(utf8.decode(packet.data));
                  if (data is! Map<String, dynamic> ||
                      data['v'] != 1 ||
                      data['type'] != 'lilygobox.device' ||
                      data['nonce'] != nonce) {
                    continue;
                  }
                  final device = LanDevice.fromJson({
                    ...data,
                    'id': data['deviceId'],
                    'protocolId': data['deviceId'],
                    'address': packet.address.address,
                  }, localAddress: socket.address);
                  if (device != null) controller.add(device);
                } on FormatException {
                  // 忽略不属于本协议的广播数据。
                }
              }
            },
            onError: (Object _) {
              // 单个网卡失效不终止其他网卡的发现。
            },
          );
        }
        if (stopped) return;
        if (sockets.isEmpty) {
          throw const SocketException('No IPv4 interface available');
        }
        send();
        retry = Timer.periodic(const Duration(seconds: 1), (_) => send());
        timeout = Timer(duration, () {
          stop();
          unawaited(controller.close());
        });
      } catch (error, stack) {
        if (!stopped) {
          controller.addError(error, stack);
          stop();
          unawaited(controller.close());
        }
      }
    }

    controller = StreamController<LanDevice>(
      onListen: () => unawaited(start()),
      onCancel: stop,
    );
    return controller.stream;
  }
}
