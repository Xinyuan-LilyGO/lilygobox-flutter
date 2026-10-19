import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/features/devices/data/firmware_update_service.dart';
import 'package:lilygobox/features/devices/data/lan_discovery.dart';
import 'package:lilygobox/features/devices/presentation/widgets/firmware_update_dialog.dart';
import 'package:lilygobox/features/devices/state/firmware_update_controller.dart';
import 'package:lilygobox/features/devices/state/lan_connection.dart';

class _FirmwareClient extends http.BaseClient {
  bool closed = false;
  bool corrupt = false;
  final List<String> requests = [];
  Completer<void>? wirelessRequested;
  Completer<void>? wirelessResponse;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url.path);
    if (request.url.path == '/wireless') {
      wirelessRequested?.complete();
      await wirelessResponse?.future;
    }
    final bytes = corrupt ? [9, 9, 9] : [1, 2, 3];
    return http.StreamedResponse(Stream.value(bytes), 200);
  }

  @override
  void close() {
    closed = true;
  }
}

class _Connection extends LanConnection {
  _Connection() {
    phase = LanConnectionPhase.connected;
    device = const LanDevice(
      id: 'device1',
      name: 'P4',
      address: '127.0.0.1',
      port: 443,
      model: 'T-Display-P4',
      modelVersion: '2.0',
    );
    firmware = '1.1.1';
    wirelessFirmware = '2.12.3';
  }
  int starts = 0;
  int installs = 0;
  Completer<bool>? installReply;
  int cancels = 0;
  bool acceptTransfer = true;
  Completer<void>? cancelReply;
  File? receivedFile;
  File? receivedWirelessFile;
  @override
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
    starts++;
    receivedFile = firmware;
    receivedWirelessFile = wirelessFirmware;
    return acceptTransfer;
  }

  @override
  Future<bool> installLocalFirmwareUpdate() async {
    installs++;
    return installReply == null ? true : await installReply!.future;
  }

  @override
  Future<void> cancelLocalFirmwareUpdate() async {
    cancels++;
    await cancelReply?.future;
  }

  void report(String stage, {int received = 0, int total = 0}) {
    firmwareUpdateStage = stage;
    firmwareReceivedBytes = received;
    firmwareTotalBytes = total;
    notifyListeners();
  }

  void online(bool value) {
    phase = value ? LanConnectionPhase.connected : LanConnectionPhase.offline;
    notifyListeners();
  }
}

class _DialogController extends FirmwareUpdateController {
  _DialogController(super.connection, super.release);

  @override
  Future<void> download() async {
    step = FirmwareUpdateStep.transferring;
    message = '传输主固件';
    notifyListeners();
  }
}

void main() {
  late _Connection connection;
  late _FirmwareClient client;
  late FirmwareUpdateController controller;
  void recreateController({String? main, String? wireless}) {
    final release = controller.release;
    controller.dispose();
    if (main != null) connection.firmware = main;
    if (wireless != null) connection.wirelessFirmware = wireless;
    client = _FirmwareClient();
    controller = FirmwareUpdateController(connection, release, client: client);
  }

  setUp(() {
    connection = _Connection();
    client = _FirmwareClient();
    final hash = sha256.convert([1, 2, 3]).toString();
    controller = FirmwareUpdateController(
      connection,
      FirmwareRelease(
        version: '1.1.2',
        mainVersion: '1.1.2',
        mainUrl: Uri.https('example.com', 'main'),
        mainSize: 3,
        mainSha256: hash,
        wirelessVersion: '2.12.3',
        wirelessUrl: Uri.https('example.com', 'wireless'),
        wirelessSize: 3,
        wirelessSha256: hash,
        notes: const [],
      ),
      client: client,
    );
  });
  tearDown(() async {
    controller.dispose();
    connection.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'verified download transfers automatically and only install needs confirmation',
    () async {
      await controller.download();
      expect(controller.step, FirmwareUpdateStep.transferring);
      expect(connection.starts, 1);
      await controller.download();
      expect(connection.starts, 1);
      connection.report('downloadingMain', received: 1, total: 3);
      expect(controller.progress, closeTo(1 / 3, 0.0001));
      connection.report('readyToInstall');
      expect(controller.step, FirmwareUpdateStep.prepared);
      expect(connection.installs, 0);
      await controller.install();
      expect(connection.installs, 1);
      expect(controller.step, FirmwareUpdateStep.restartRequested);
      connection.online(false);
      connection.firmware = '1.1.2';
      connection.online(true);
      expect(controller.step, FirmwareUpdateStep.restartRequested);
    },
  );

  test(
    'restart request does not wait for reconnect version validation',
    () async {
      await controller.download();
      connection.report('readyToInstall');
      await controller.install();
      connection.online(false);
      connection.firmware = '1.1.2';
      connection.wirelessFirmware = '2.12.2';
      connection.online(true);
      expect(controller.step, FirmwareUpdateStep.restartRequested);
      expect(controller.message, contains('等待设备重启安装'));
      expect(controller.message, isNot(contains('更新成功')));
    },
  );

  test(
    'received bytes switch to verification and readiness hides progress',
    () async {
      await controller.download();
      connection.report('downloadingMain', received: 3, total: 3);
      expect(controller.progress, isNull);
      expect(controller.message, contains('等待设备校验结果'));
      expect(controller.canCancel, isTrue);
      connection.report('verifyingMain');
      expect(controller.message, contains('校验主固件镜像与 SHA-256'));
      expect(controller.progress, isNull);
      connection.report('verifyingWireless');
      expect(controller.message, contains('校验无线固件镜像与 SHA-256'));
      connection.report('downloadingWireless', received: 1, total: 3);
      expect(controller.progress, closeTo(1 / 3, 0.0001));
      expect(controller.message, startsWith('传输无线固件'));
      connection.report('preparingInstall');
      expect(controller.message, contains('整理固件并准备安装'));
      expect(controller.progress, isNull);
      expect(connection.installs, 0);
      connection.report('readyToInstall');
      expect(controller.step, FirmwareUpdateStep.prepared);
      expect(controller.progress, isNull);
      expect(controller.canCancel, isTrue);
    },
  );

  test('verification remains cancellable before installation', () async {
    await controller.download();
    connection.report('verifyingMain');
    await controller.cancel();
    expect(controller.step, FirmwareUpdateStep.cancelled);
    expect(connection.cancels, 1);
    expect(connection.installs, 0);
  });

  test('bad hash stops before device transfer', () async {
    client.corrupt = true;
    await controller.download();
    expect(controller.step, FirmwareUpdateStep.failed);
    expect(connection.starts, 0);
  });

  test('cancel while wireless downloads prevents automatic transfer', () async {
    recreateController(wireless: '2.12.2');
    final requested = client.wirelessRequested = Completer<void>();
    final response = client.wirelessResponse = Completer<void>();
    final download = controller.download();
    await requested.future;
    expect(connection.starts, 0);
    await controller.cancel();
    response.complete();
    await download;
    expect(controller.step, FirmwareUpdateStep.cancelled);
    expect(connection.starts, 0);
    expect(connection.installs, 0);
  });

  test(
    'rejected automatic transfer reports failure without installing',
    () async {
      connection.acceptTransfer = false;
      await controller.download();
      expect(controller.step, FirmwareUpdateStep.failed);
      expect(connection.starts, 1);
      expect(connection.installs, 0);
    },
  );

  test(
    'device cancellation stops the app and removes temporary binaries',
    () async {
      await controller.download();
      final file = connection.receivedFile!;
      connection.report('cancelled');
      expect(controller.step, FirmwareUpdateStep.cancelled);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await file.exists(), isFalse);
      expect(connection.installs, 0);
    },
  );

  test('disconnect during transfer fails and releases the server', () async {
    await controller.download();
    connection.online(false);
    expect(controller.step, FirmwareUpdateStep.failed);
    expect(connection.cancels, 1);
  });

  Future<void> openDialog(WidgetTester tester) async {
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: true,
                builder: (_) => FirmwareUpdateDialog(
                  controller: controller,
                  theme: theme.themeData,
                  description: '主固件版本 v1.1.1 → v1.1.2\n更新内容：测试说明',
                ),
              ),
              child: const Text('更新'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'one dialog handles confirmation, transfer and app-only restart',
    (tester) async {
      final release = controller.release;
      controller.dispose();
      controller = _DialogController(connection, release);
      await openDialog(tester);
      final original = tester.element(find.byType(AlertDialog));
      expect(find.textContaining('测试说明'), findsOneWidget);
      await tester.tap(find.text('下载更新'));
      await tester.pump();
      expect(tester.element(find.byType(AlertDialog)), same(original));
      expect(find.textContaining('测试说明'), findsNothing);
      expect(find.text('传输主固件'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      controller.progress = null;
      controller.message = '设备正在校验主固件镜像与 SHA-256';
      controller.notifyListeners();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      controller.step = FirmwareUpdateStep.prepared;
      controller.message = '设备已接收并校验固件';
      controller.progress = 1;
      controller.notifyListeners();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('100%'), findsNothing);
      final restart = tester.widget<AppActionButton>(
        find.widgetWithText(AppActionButton, '重启安装'),
      );
      expect(restart.primary, isTrue);
      expect(tester.element(find.byType(AlertDialog)), same(original));
      await tester.tap(find.text('重启安装'));
      await tester.pump();
      expect(connection.installs, 1);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final close = tester.widget<AppActionButton>(
        find.widgetWithText(AppActionButton, '关闭'),
      );
      expect(close.onPressed, isNotNull);
      expect(find.textContaining('等待设备重启安装'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.element(find.byType(AlertDialog)), same(original));
      expect(controller.step, FirmwareUpdateStep.restartRequested);
      connection.online(false);
      connection.firmware = '1.1.2';
      connection.online(true);
      await tester.pump();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('background dismiss cancels before downloading', (tester) async {
    await openDialog(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.textContaining('保留当前固件'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.step, FirmwareUpdateStep.cancelled);
    expect(client.requests, isEmpty);
    expect(connection.starts, 0);
  });

  for (final background in [false, true]) {
    testWidgets(
      'install dialog can close without cancelling device installation (background: $background)',
      (tester) async {
        controller.step = FirmwareUpdateStep.prepared;
        connection.installReply = Completer<bool>();
        await openDialog(tester);
        await tester.tap(find.text('重启安装'));
        await tester.pump();
        expect(find.text('关闭'), findsOneWidget);
        if (background) {
          await tester.tapAt(const Offset(10, 10));
        } else {
          await tester.tap(find.text('关闭'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(connection.cancels, 0);
        expect(controller.step, FirmwareUpdateStep.installing);
        connection.installReply!.complete(true);
        await tester.pump();
        connection.online(false);
        connection.firmware = '1.1.2';
        connection.online(true);
        expect(controller.step, FirmwareUpdateStep.restartRequested);
        expect(connection.cancels, 0);
      },
    );
  }

  testWidgets(
    'cancel update closes immediately while device acknowledgement is pending',
    (tester) async {
      controller.step = FirmwareUpdateStep.prepared;
      connection.cancelReply = Completer<void>();
      await openDialog(tester);
      await tester.tap(find.text('取消更新'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('正在取消更新…'), findsNothing);
      expect(find.text('更新已取消，保留当前固件。'), findsNothing);
      expect(find.text('关闭'), findsNothing);
      expect(connection.cancels, 1);
      connection.cancelReply!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(connection.cancels, 1);
    },
  );

  testWidgets('late cancellation failure does not reopen a dismissed dialog', (
    tester,
  ) async {
    controller.step = FirmwareUpdateStep.prepared;
    connection.cancelReply = Completer<void>();
    await openDialog(tester);
    await tester.tap(find.text('取消更新'));
    await tester.pump();
    connection.cancelReply!.completeError(StateError('cancel rejected'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.message, contains('设备未确认取消更新'));
    expect(find.textContaining('设备未确认取消更新'), findsNothing);
    expect(find.text('正在取消更新…'), findsNothing);
  });

  testWidgets('background dismiss cancels an active transfer', (tester) async {
    final release = controller.release;
    controller.dispose();
    controller = _DialogController(connection, release);
    await openDialog(tester);
    await tester.tap(find.text('下载更新'));
    await tester.pump();
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.textContaining('保留当前固件'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.step, FirmwareUpdateStep.cancelled);
    expect(connection.cancels, 1);
  });

  test('cancelling the download prevents later transfer', () async {
    await controller.cancel();
    await controller.download();
    expect(controller.step, FirmwareUpdateStep.cancelled);
    expect(client.closed, isTrue);
    expect(connection.starts, 0);
  });

  test(
    'main-only update skips unchanged wireless download and transfer',
    () async {
      await controller.download();
      expect(client.requests, ['/main']);
      expect(connection.receivedFile, isNotNull);
      expect(connection.receivedWirelessFile, isNull);
    },
  );

  test(
    'wireless-only update skips unchanged main download and transfer',
    () async {
      recreateController(main: '1.1.2', wireless: '2.12.2');
      final downloadProgress = <double?>[];
      controller.addListener(() {
        if (controller.step == FirmwareUpdateStep.downloading) {
          downloadProgress.add(controller.progress);
        }
      });
      await controller.download();
      expect(client.requests, ['/wireless']);
      expect(connection.receivedFile, isNull);
      expect(connection.receivedWirelessFile, isNotNull);
      expect(downloadProgress.last, 1);
    },
  );

  test('both newer components are downloaded and transferred', () async {
    recreateController(wireless: '2.12.2');
    await controller.download();
    expect(client.requests, ['/main', '/wireless']);
    expect(connection.receivedFile, isNotNull);
    expect(connection.receivedWirelessFile, isNotNull);
  });

  test('equal versions with v prefixes do not download or transfer', () async {
    recreateController(main: 'v1.1.2', wireless: 'V2.12.3');
    await controller.download();
    expect(client.requests, isEmpty);
    expect(connection.starts, 0);
    expect(controller.message, '当前已是最新版本');
  });

  test('next connection owns version checking after restart request', () async {
    await controller.download();
    connection.report('readyToInstall');
    await controller.install();
    connection.online(false);
    connection.firmware = '1.1.2';
    connection.wirelessFirmware = '';
    connection.online(true);
    expect(controller.step, FirmwareUpdateStep.restartRequested);
  });

  test(
    'restart request completion does not start a later verification dialog',
    () async {
      recreateController(wireless: '2.12.4');
      await controller.download();
      connection.report('readyToInstall');
      await controller.install();
      connection.online(false);
      connection.firmware = 'v1.1.2';
      connection.online(true);
      expect(controller.step, FirmwareUpdateStep.restartRequested);
      expect(client.requests, ['/main']);
    },
  );
}
