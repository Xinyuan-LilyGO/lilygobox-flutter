/*
 * @Description: 通过真实回环 UDP 和 WebSocket 验证发现、设备确认、断线及取消竞态。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 18:37:01
 * @LastEditTime: 2026-10-06 14:12:27
 * @License: GPL 3.0
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/devices/data/lan_discovery.dart';
import 'package:lilygobox/features/devices/data/pairing_store.dart';
import 'package:lilygobox/features/devices/state/lan_connection.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';

const deviceId = '001122334455';

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class MemoryPairingStore implements DevicePairingStore {
  final tokens = <String, String>{};
  final fingerprints = <String, String>{};
  bool failFingerprintWrite = false;
  @override
  Future<String?> readFingerprint(String id) async => fingerprints[id];
  @override
  Future<void> writeFingerprint(String id, String fingerprint) async {
    if (failFingerprintWrite) throw StateError('storage unavailable');
    fingerprints[id] = fingerprint;
  }

  @override
  Future<void> deleteFingerprint(String id) async => fingerprints.remove(id);
  @override
  Future<String?> read(String id) async => tokens[id];
  @override
  Future<void> write(String id, String token) async {
    tokens[id] = token;
  }

  @override
  Future<void> delete(String id) async {
    tokens.remove(id);
  }
}

SecurityContext deviceTlsContext([String name = 'device']) => SecurityContext()
  ..useCertificateChain('test/fixtures/device_tls/$name-cert.pem')
  ..usePrivateKey('test/fixtures/device_tls/$name-key.pem');

String deviceFingerprint([String name = 'device']) {
  final pem = File(
    'test/fixtures/device_tls/$name-cert.pem',
  ).readAsStringSync();
  final der = base64Decode(
    pem.split('\n').where((line) => !line.startsWith('---')).join(),
  );
  return sha256.convert(der).toString();
}

class TestLanDiscovery extends LanDiscovery {
  TestLanDiscovery(this.device);
  final LanDevice device;
  final List<LanDevice> additionalDevices = [];
  int scans = 0;
  bool available = true;
  @override
  Stream<LanDevice> discover() {
    scans++;
    return available
        ? Stream.fromIterable([device, ...additionalDevices])
        : const Stream.empty();
  }
}

void main() {
  test(
    'UDP discovery ignores foreign/malformed replies and uses the sender address',
    () async {
      final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(udp.close);
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = udp.receive();
        if (packet == null) return;
        final request =
            jsonDecode(utf8.decode(packet.data)) as Map<String, dynamic>;
        final reply = <String, Object>{
          'v': 1,
          'type': 'lilygobox.device',
          'deviceId': deviceId,
          'name': 'T-Display-P4',
          'model': 'T-Display-P4',
          'port': 18464,
          'address': '203.0.113.10',
          'nonce': request['nonce'] as String,
        };
        udp.send(utf8.encode('not json'), packet.address, packet.port);
        udp.send(
          utf8.encode(jsonEncode({...reply, 'nonce': 'wrongnonce'})),
          packet.address,
          packet.port,
        );
        udp.send(
          utf8.encode(jsonEncode({...reply, 'v': 2})),
          packet.address,
          packet.port,
        );
        udp.send(utf8.encode(jsonEncode(reply)), packet.address, packet.port);
      });
      final discovery = LanDiscovery(
        port: udp.port,
        target: '127.0.0.1',
        bindAddresses: [InternetAddress.loopbackIPv4],
      );
      final found = await discovery.discover().first;
      expect(found.id, deviceId);
      expect(found.address, '127.0.0.1');
    },
  );

  late HttpServer server;
  late LanConnection connection;
  late LanDevice device;
  final sockets = <WebSocket>[];

  setUp(() async {
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      deviceTlsContext(),
    );
    device = LanDevice(
      id: deviceId,
      name: 'T-Display-P4',
      address: '127.0.0.1',
      port: server.port,
      model: 'T-Display-P4',
    );
    connection = LanConnection(
      approvalTimeout: const Duration(seconds: 2),
      heartbeatInterval: const Duration(milliseconds: 30),
      heartbeatTimeout: const Duration(milliseconds: 120),
    );
  });

  tearDown(() async {
    connection.dispose();
    for (final socket in sockets) {
      unawaited(socket.close());
    }
    sockets.clear();
    await server.close(force: true);
  });

  Map<String, Object> response(String type, {String id = deviceId}) => {
    'v': 1,
    'type': type,
    'deviceId': id,
    'model': 'T-Display-P4',
    'firmware': 'test-1.0',
    'uptimeMs': 12345,
  };

  void serve(void Function(WebSocket, Map<String, dynamic>) handler) {
    server.listen(
      (request) async {
        expect(request.uri.path, '/api/v1/ws');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen(
          (data) => handler(
            socket,
            jsonDecode(data as String) as Map<String, dynamic>,
          ),
        );
      },
      onError: (Object error) {
        // 客户端拒绝测试证书时，服务端可能收到对应的握手失败事件。
        if (error is! HandshakeException) throw error;
      },
    );
  }

  test(
    'connection becomes online only after device approval; heartbeats keep it online',
    () async {
      serve((socket, message) {
        if (message['type'] == 'hello') {
          socket.add(jsonEncode(response('waiting')));
        }
        if (message['type'] == 'ping') socket.add(jsonEncode(response('pong')));
      });
      final pending = connection.connect(device);
      await waitFor(
        () => connection.phase == LanConnectionPhase.awaitingApproval,
      );
      expect(connection.connected, isFalse);
      sockets.single.add(jsonEncode(response('ready')));
      expect(await pending, isTrue);
      expect(connection.firmware, 'test-1.0');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(connection.connected, isTrue);
      unawaited(sockets.single.close());
      await waitFor(() => connection.phase == LanConnectionPhase.offline);
    },
  );

  test('unresponsive peer becomes offline after heartbeat timeout', () async {
    serve((socket, message) {
      if (message['type'] == 'hello') socket.add(jsonEncode(response('ready')));
    });
    expect(await connection.connect(device), isTrue);
    await waitFor(() => connection.phase == LanConnectionPhase.offline);
  });

  test(
    'wrong device identity is rejected rather than marked connected',
    () async {
      serve((socket, message) {
        socket.add(jsonEncode(response('ready', id: 'ffffffffffff')));
      });
      expect(await connection.connect(device), isFalse);
      expect(connection.phase, LanConnectionPhase.failed);
    },
  );

  test(
    'cancelling approval cannot be undone by a late ready response',
    () async {
      serve((socket, message) {
        if (message['type'] == 'hello') {
          socket.add(jsonEncode(response('waiting')));
        }
      });
      final pending = connection.connect(device);
      await waitFor(
        () => connection.phase == LanConnectionPhase.awaitingApproval,
      );
      await connection.cancelConnection();
      sockets.single.add(jsonEncode(response('ready')));
      expect(await pending, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(connection.phase, LanConnectionPhase.offline);
    },
  );

  test('pending approval times out and releases the session', () async {
    connection.dispose();
    connection = LanConnection(
      approvalTimeout: const Duration(milliseconds: 120),
    );
    serve((socket, message) {
      socket.add(jsonEncode(response('waiting')));
    });
    expect(await connection.connect(device), isFalse);
    expect(connection.phase, LanConnectionPhase.failed);
  });

  test(
    'same model devices are saved by identity, and legacy entries remain',
    () {
      final manager = DeviceManagerProvider();
      addTearDown(manager.dispose);
      manager.addDevice('T-Glasses-P4');
      manager.addLanDevice(device);
      manager.addLanDevice(
        LanDevice(
          id: '112233445566',
          name: device.name,
          address: device.address,
          port: device.port,
          model: device.model,
        ),
      );
      expect(manager.addedDevices, ['T-Glasses-P4', deviceId, '112233445566']);
      expect(manager.displayName(deviceId), 'T-Display-P4');
    },
  );
  group('remembered app authorization', () {
    final token = List.filled(64, 'a').join();
    final challenge = List.filled(64, 'b').join();
    late MemoryPairingStore store;
    late TestLanDiscovery discovery;
    String proof(String role) => Hmac(
      sha256,
      utf8.encode(token),
    ).convert(utf8.encode('$role|$deviceId|$challenge')).toString();

    setUp(() {
      connection.dispose();
      store = MemoryPairingStore();
      discovery = TestLanDiscovery(device);
      connection = LanConnection(
        discovery: discovery,
        pairingStore: store,
        reconnectDelay: const Duration(milliseconds: 40),
        heartbeatInterval: const Duration(milliseconds: 30),
        heartbeatTimeout: const Duration(milliseconds: 150),
        approvalTimeout: const Duration(seconds: 2),
      );
    });

    void authorize(WebSocket socket, Map<String, dynamic> message) {
      // 重连只传随机挑战的证明，不能把永久凭据发给广播中声明同一 ID 的地址。
      expect(message.containsKey('token'), isFalse);
      if (message['type'] == 'hello') {
        expect(message['pairingVersion'], 2);
        expect(message['resume'], isTrue);
        expect(
          message['pairingId'],
          sha256.convert(utf8.encode(token)).toString(),
        );
        socket.add(
          jsonEncode({
            ...response('challenge'),
            'challenge': challenge,
            'proof': proof('server'),
          }),
        );
      } else if (message['type'] == 'authenticate') {
        expect(message['proof'], proof('client'));
        socket.add(jsonEncode(response('ready')));
      } else if (message['type'] == 'ping') {
        socket.add(jsonEncode(response('pong')));
      }
    }

    test('prefixed protocol IDs retain exact HMAC identity over TLS', () async {
      store.tokens[deviceId] = token;
      final legacy = LanDevice.fromJson({
        ...device.toJson(),
        'id': 'lgb-$deviceId',
      })!;
      String legacyProof(String role) => Hmac(sha256, utf8.encode(token))
          .convert(utf8.encode('$role|${legacy.protocolId}|$challenge'))
          .toString();
      serve((socket, message) {
        if (message['type'] == 'hello') {
          expect(message['deviceId'], legacy.protocolId);
          expect(message['resume'], isTrue);
          socket.add(
            jsonEncode({
              ...response('challenge', id: legacy.protocolId),
              'challenge': challenge,
              'proof': legacyProof('server'),
            }),
          );
        } else if (message['type'] == 'authenticate') {
          expect(message['proof'], legacyProof('client'));
          socket.add(jsonEncode(response('ready', id: legacy.protocolId)));
        } else if (message['type'] == 'ping') {
          socket.add(jsonEncode(response('pong', id: legacy.protocolId)));
        }
      });
      expect(await connection.connect(legacy), isTrue);
      expect(connection.device!.id, deviceId);
      expect(store.tokens.keys, [deviceId]);
    });

    test(
      'discovery hides connected ID, retains same-name devices and finds it after disconnect',
      () async {
        store.tokens[deviceId] = token;
        serve(authorize);
        expect(await connection.connect(device), isTrue);
        expect(await connection.discover().toList(), isEmpty);
        final other = LanDevice(
          id: 'aabbccddeeff',
          name: device.name,
          address: device.address,
          port: device.port,
          model: device.model,
        );
        discovery.additionalDevices.add(other);
        final found = await connection.discover().toList();
        expect(found.map((item) => item.id), [other.id]);
        expect(connection.connected, isTrue);
        expect(sockets, hasLength(1));
        expect(store.tokens[deviceId], token);
        connection.disconnect();
        final rediscovered = await connection.discover().toList();
        expect(rediscovered.map((item) => item.id), [deviceId, other.id]);
      },
    );

    test(
      'first approval saves credential then reconnects without approval',
      () async {
        var approvals = 0;
        serve((socket, message) {
          if (message['type'] == 'hello' && message['resume'] != true) {
            approvals++;
            socket.add(jsonEncode(response('waiting')));
          } else {
            authorize(socket, message);
          }
        });
        final pending = connection.connect(device);
        await waitFor(
          () => connection.phase == LanConnectionPhase.awaitingApproval,
        );
        expect(store.fingerprints, isEmpty);
        sockets.single.add(
          jsonEncode({...response('ready'), 'pairingToken': token}),
        );
        expect(await pending, isTrue);
        expect(store.tokens[deviceId], token);
        expect(store.fingerprints[deviceId], deviceFingerprint());
        await sockets.first.close();
        await waitFor(() => sockets.length == 2 && connection.connected);
        expect(approvals, 1);
        expect(discovery.scans, greaterThan(0));
      },
    );

    test(
      'startup rediscovers changed address and resumes saved authorization',
      () async {
        store.tokens[deviceId] = token;
        serve(authorize);
        final stale = LanDevice(
          id: deviceId,
          name: device.name,
          address: '192.0.2.123',
          port: 9,
          model: device.model,
        );
        await connection.restorePairings([stale]);
        await waitFor(() => connection.connected);
        expect(connection.device!.address, '127.0.0.1');
        expect(connection.device!.port, server.port);
      },
    );

    test(
      'revoked authorization is deleted and automatic retries stop',
      () async {
        store.tokens[deviceId] = token;
        store.fingerprints[deviceId] = deviceFingerprint();
        serve((socket, message) {
          socket.add(jsonEncode(response('authorization_revoked')));
        });
        await connection.restorePairings([device]);
        await waitFor(() => sockets.isNotEmpty && store.tokens.isEmpty);
        final scans = discovery.scans;
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(discovery.scans, scans);
        expect(connection.connected, isFalse);
        expect(store.fingerprints[deviceId], deviceFingerprint());
      },
    );

    test(
      'manual disconnect stays disconnected without deleting authorization',
      () async {
        store.tokens[deviceId] = token;
        serve(authorize);
        await connection.restorePairings([device]);
        await waitFor(() => connection.connected);
        connection.disconnect();
        final scans = discovery.scans;
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(discovery.scans, scans);
        expect(store.tokens[deviceId], token);
        expect(connection.connected, isFalse);
      },
    );

    test(
      'device disconnect retains authorization until explicit reconnect',
      () async {
        store.tokens[deviceId] = token;
        final attempts = <bool>[];
        serve((socket, message) {
          if (message['type'] == 'hello') {
            attempts.add(message['automatic'] as bool);
          }
          authorize(socket, message);
        });
        await connection.restorePairings([device]);
        await waitFor(() => connection.connected);
        sockets.single.add(jsonEncode(response('disconnected')));
        await waitFor(() => connection.phase == LanConnectionPhase.offline);
        final scans = discovery.scans;
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(discovery.scans, scans);
        expect(store.tokens[deviceId], token);
        expect(await connection.connect(device), isTrue);
        expect(attempts, [true, false]);
      },
    );

    test(
      'authenticated paused reply stops retries before becoming online',
      () async {
        store.tokens[deviceId] = token;
        serve((socket, message) {
          if (message['type'] == 'authenticate') {
            expect(message['proof'], proof('client'));
            socket.add(jsonEncode(response('disconnected')));
          } else {
            authorize(socket, message);
          }
        });
        await connection.restorePairings([device]);
        await waitFor(
          () =>
              sockets.isNotEmpty &&
              connection.phase == LanConnectionPhase.offline,
        );
        final scans = discovery.scans;
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(discovery.scans, scans);
        expect(store.tokens[deviceId], token);
        expect(connection.connected, isFalse);
      },
    );

    test(
      'protocol mismatch preserves credential and stops automatic retries',
      () async {
        store.tokens[deviceId] = token;
        var compatible = false;
        serve((socket, message) {
          if (!compatible) {
            socket.add(jsonEncode(response('upgrade_required')));
          } else {
            authorize(socket, message);
          }
        });
        await connection.restorePairings([device]);
        await waitFor(() => connection.phase == LanConnectionPhase.failed);
        final scans = discovery.scans;
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(store.tokens[deviceId], token);
        expect(discovery.scans, scans);
        compatible = true;
        expect(await connection.connect(device), isTrue);
      },
    );

    test(
      'restarting the app reuses the first approval without creating another',
      () async {
        var approvals = 0;
        serve((socket, message) {
          if (message['type'] == 'hello' && message['resume'] != true) {
            expect(message['pairingVersion'], 2);
            approvals++;
            socket.add(
              jsonEncode({...response('ready'), 'pairingToken': token}),
            );
          } else {
            authorize(socket, message);
          }
        });
        expect(await connection.connect(device), isTrue);
        for (var restart = 0; restart < 3; restart++) {
          connection.dispose();
          connection = LanConnection(
            discovery: discovery,
            pairingStore: store,
            reconnectDelay: const Duration(milliseconds: 40),
          );
          await connection.restorePairings([device]);
          await waitFor(() => connection.connected);
        }
        expect(approvals, 1);
        expect(store.tokens.length, 1);
      },
    );

    test('offline device is rediscovered when it becomes available', () async {
      store.tokens[deviceId] = token;
      discovery.available = false;
      serve(authorize);
      await connection.restorePairings([device]);
      await waitFor(() => discovery.scans >= 2);
      expect(sockets, isEmpty);
      discovery.available = true;
      await waitFor(() => connection.connected);
    });

    test('priority queue polls without showing first-time approval', () async {
      store.tokens[deviceId] = token;
      var polls = 0;
      serve((socket, message) {
        if (message['type'] == 'authenticate') {
          expect(message['proof'], proof('client'));
          socket.add(jsonEncode(response('queued')));
        } else if (message['type'] == 'poll') {
          polls++;
          socket.add(jsonEncode(response('ready')));
        } else {
          authorize(socket, message);
        }
      });
      final states = <LanConnectionPhase>[];
      connection.addListener(() => states.add(connection.phase));
      expect(await connection.connect(device), isTrue);
      expect(polls, 1);
      expect(states, isNot(contains(LanConnectionPhase.awaitingApproval)));
      expect(store.tokens[deviceId], token);
    });

    test(
      'busy retains authorization and retries when device becomes free',
      () async {
        store.tokens[deviceId] = token;
        var attempts = 0;
        serve((socket, message) {
          if (message['type'] == 'hello' && ++attempts == 1) {
            socket.add(jsonEncode(response('busy')));
          } else {
            authorize(socket, message);
          }
        });
        await connection.restorePairings([device]);
        await waitFor(() => connection.connected);
        expect(attempts, 2);
        expect(store.tokens[deviceId], token);
      },
    );

    test(
      'queue without server proof is rejected without deleting credential',
      () async {
        store.tokens[deviceId] = token;
        serve((socket, message) => socket.add(jsonEncode(response('queued'))));
        expect(await connection.connect(device), isFalse);
        expect(store.tokens[deviceId], token);
      },
    );

    test('cancelling priority wait ignores a late selection', () async {
      store.tokens[deviceId] = token;
      var queued = false;
      serve((socket, message) {
        if (message['type'] == 'authenticate') {
          queued = true;
          socket.add(jsonEncode(response('queued')));
        } else {
          authorize(socket, message);
        }
      });
      final result = connection.connect(device);
      await waitFor(() => queued);
      await connection.cancelConnection();
      sockets.single.add(jsonEncode(response('ready')));
      expect(await result, isFalse);
      expect(connection.phase, LanConnectionPhase.offline);
      expect(store.tokens[deviceId], token);
    });

    test(
      'full pairing list refuses a sixth app without saving a token',
      () async {
        serve(
          (socket, message) => socket.add(jsonEncode(response('pairing_full'))),
        );
        expect(await connection.connect(device), isFalse);
        expect(store.tokens, isEmpty);
        expect(connection.connected, isFalse);
      },
    );

    test(
      'forged server proof never receives client proof or credential',
      () async {
        store.tokens[deviceId] = token;
        final messages = <Map<String, dynamic>>[];
        serve((socket, message) {
          messages.add(message);
          socket.add(
            jsonEncode({
              ...response('challenge'),
              'challenge': challenge,
              'proof': 'invalid',
            }),
          );
        });
        expect(await connection.connect(device), isFalse);
        expect(messages.map((m) => m['type']), ['hello']);
        expect(messages.single.containsKey('token'), isFalse);
        expect(store.tokens[deviceId], token);
      },
    );

    test(
      'ready without server proof cannot authorize a saved connection',
      () async {
        store.tokens[deviceId] = token;
        serve((socket, message) => socket.add(jsonEncode(response('ready'))));
        expect(await connection.connect(device), isFalse);
        expect(connection.connected, isFalse);
        expect(store.fingerprints, isEmpty);
      },
    );

    test(
      'changed certificate is rejected before hello and requires explicit reset',
      () async {
        store.tokens[deviceId] = token;
        store.fingerprints[deviceId] = deviceFingerprint('other');
        var messages = 0;
        serve((socket, message) {
          messages++;
          if (message['type'] == 'hello') {
            expect(message['resume'], isNull);
            socket.add(
              jsonEncode({...response('ready'), 'pairingToken': token}),
            );
          } else if (message['type'] == 'ping') {
            socket.add(jsonEncode(response('pong')));
          }
        });
        expect(await connection.connect(device), isFalse);
        expect(connection.identityChanged, isTrue);
        expect(messages, 0);
        expect(store.tokens[deviceId], token);
        expect(store.fingerprints[deviceId], deviceFingerprint('other'));
        await Future<void>.delayed(const Duration(milliseconds: 160));
        expect(discovery.scans, 0);
        expect(await connection.resetDeviceTrust('ffffffffffff'), isFalse);
        expect(await connection.resetDeviceTrust(deviceId), isTrue);
        expect(store.tokens, isEmpty);
        expect(store.fingerprints, isEmpty);
        expect(await connection.connect(device), isTrue);
        expect(store.fingerprints[deviceId], deviceFingerprint());
        expect(await connection.resetDeviceTrust(deviceId), isFalse);
      },
    );

    test('persisted certificate is checked after app restart', () async {
      store.tokens[deviceId] = token;
      serve(authorize);
      expect(await connection.connect(device), isTrue);
      expect(store.fingerprints[deviceId], deviceFingerprint());
      connection.dispose();
      connection = LanConnection(pairingStore: store);
      expect(await connection.connect(device), isTrue);
      expect(connection.identityChanged, isFalse);
      expect(store.fingerprints[deviceId], deviceFingerprint());
    });

    test(
      'certificate save failure never reports a successful connection',
      () async {
        store.failFingerprintWrite = true;
        serve((socket, message) {
          if (message['type'] == 'hello') {
            socket.add(
              jsonEncode({...response('ready'), 'pairingToken': token}),
            );
          }
        });
        expect(await connection.connect(device), isFalse);
        expect(connection.connected, isFalse);
        expect(store.tokens, isEmpty);
        expect(store.fingerprints, isEmpty);
      },
    );

    test('unverified peer cannot erase an existing authorization', () async {
      store.tokens[deviceId] = token;
      serve(
        (socket, message) =>
            socket.add(jsonEncode(response('authorization_revoked'))),
      );
      expect(await connection.connect(device), isFalse);
      expect(store.tokens[deviceId], token);
      expect(store.fingerprints, isEmpty);
      expect(connection.identityChanged, isTrue);
    });

    test('cancelled initial approval does not persist a certificate', () async {
      serve((socket, message) {
        if (message['type'] == 'hello') {
          socket.add(jsonEncode(response('waiting')));
        }
      });
      final pending = connection.connect(device);
      await waitFor(
        () => connection.phase == LanConnectionPhase.awaitingApproval,
      );
      await connection.cancelConnection();
      expect(await pending, isFalse);
      expect(store.fingerprints, isEmpty);
      expect(store.tokens, isEmpty);
    });

    test(
      'plaintext server receives no application messages or credentials',
      () async {
        await server.close(force: true);
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        device = LanDevice.fromJson({...device.toJson(), 'port': server.port})!;
        store.tokens[deviceId] = token;
        var messages = 0;
        serve((socket, message) => messages++);
        expect(await connection.connect(device), isFalse);
        expect(messages, 0);
        expect(connection.connected, isFalse);
        expect(store.tokens[deviceId], token);
        expect(store.fingerprints, isEmpty);
      },
    );
  });
}
