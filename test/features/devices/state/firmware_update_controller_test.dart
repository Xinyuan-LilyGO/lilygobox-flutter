import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:lilygobox/generated/l10n/app_localizations_en.dart';
import 'package:lilygobox/generated/l10n/app_localizations_zh.dart';
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
  int taskCommands = 0;
  @override
  Future<bool> controlFirmwareTask({
    required bool install,
    required String taskId,
  }) async {
    taskCommands++;
    return true;
  }

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
    bool reuseCache = true,
    bool deviceCacheOnly = false,
    List<String> releaseNotes = const [],
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
  Future<void> download({bool reuseCache = true}) async {
    step = FirmwareUpdateStep.transferring;
    message = (l10n) => l10n.otaTransferMain;
    notifyListeners();
  }
}

void main() {
  test('observing a remote task does not cancel it when the window closes', () {
    final connection = _Connection();
    connection.firmwareTaskId = 'a' * 32;
    connection.firmwareTaskSource = 'remote';
    connection.firmwareTaskBusy = true;
    connection.firmwareUpdateStage = 'downloadingMain';
    connection.firmwareReceivedBytes = 25;
    connection.firmwareTotalBytes = 100;
    final observer = FirmwareUpdateController.observe(connection);
    expect(observer.progress, .25);
    expect(observer.message(AppLocalizationsZh()), startsWith('设备下载主固件'));
    observer.dispose();
    expect(connection.taskCommands, 0);
    expect(connection.cancels, 0);
    connection.dispose();
  });

  test(
    'remote task progress reaches prepared state before install confirmation',
    () async {
      final connection = _Connection();
      connection.firmwareTaskId = 'a' * 32;
      connection.firmwareTaskSource = 'remote';
      connection.firmwareTaskBusy = true;
      connection.firmwareUpdateStage = 'verifyingMain';
      final observer = FirmwareUpdateController.observe(connection);
      expect(observer.progress, isNull);
      connection.report('readyToInstall');
      expect(observer.step, FirmwareUpdateStep.prepared);
      expect(connection.taskCommands, 0);
      await observer.install();
      expect(connection.taskCommands, 1);
      expect(observer.step, FirmwareUpdateStep.restartRequested);
      observer.dispose();
      connection.dispose();
    },
  );

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

  test('update status and failures render in the requested language', () async {
    final en = AppLocalizationsEn();
    final zh = AppLocalizationsZh();
    await controller.download();
    final cases = <String, String>{
      'verifyingMain': en.otaVerifyingMain,
      'verifyingWireless': en.otaVerifyingWireless,
      'preparingInstall': en.otaPreparing,
      'paused': en.otaPaused,
      'readyToInstall': en.otaPrepared,
    };
    for (final entry in cases.entries) {
      connection.report(entry.key);
      expect(controller.message(en), entry.value);
      expect(controller.message(zh), isNot(entry.value));
    }
    connection.firmwareUpdateMessage = 'SHA-256 mismatch';
    connection.report('failed');
    expect(controller.message(en), en.otaDeviceFailed('SHA-256 mismatch'));
    expect(controller.message(zh), zh.otaDeviceFailed('SHA-256 mismatch'));
    connection.firmwareUpdateMessage = 'Unrelated later task';
    expect(controller.message(en), en.otaDeviceFailed('SHA-256 mismatch'));
  });

  testWidgets('update confirmation and cache actions follow locale changes', (
    tester,
  ) async {
    final release = controller.release;
    connection.firmwareRelease = FirmwareRelease(
      version: release.version,
      mainVersion: release.mainVersion,
      mainUrl: release.mainUrl,
      mainSize: release.mainSize,
      mainSha256: release.mainSha256,
      wirelessVersion: release.wirelessVersion,
      wirelessUrl: release.wirelessUrl,
      wirelessSize: release.wirelessSize,
      wirelessSha256: release.wirelessSha256,
      notes: const ['Test firmware.'],
    );
    connection.firmwareTaskSupported = true;
    connection.firmwareMainCached = true;
    connection.firmwareTaskMainVersion = release.mainVersion;
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    Widget app(String language) => MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FirmwareUpdateFlowDialog(
        connection: connection,
        theme: theme.themeData,
        checkForUpdate: false,
      ),
    );
    await tester.pumpWidget(app('en'));
    await tester.pump();
    final en = AppLocalizationsEn();
    expect(find.text(en.otaFound), findsOneWidget);
    expect(find.text(en.otaUseDeviceCache), findsOneWidget);
    expect(find.text(en.otaRedownload), findsOneWidget);
    expect(find.text(en.otaCancel), findsOneWidget);
    expect(find.text(en.otaDeviceCacheHint), findsOneWidget);
    final english = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .join('\n');
    expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(english), isFalse);
    expect(english, contains('Main firmware version'));
    expect(english, contains('Release notes'));
    expect(english, contains('Test firmware.'));
    await tester.pumpWidget(app('zh'));
    await tester.pump();
    final zh = AppLocalizationsZh();
    expect(find.text(zh.otaFound), findsOneWidget);
    expect(find.text(zh.otaUseDeviceCache), findsOneWidget);
    expect(find.text(zh.otaCancel), findsOneWidget);
    expect(find.textContaining('Test firmware.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
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
      expect(controller.message(AppLocalizationsZh()), contains('重启安装指令已确认'));
      expect(controller.message(AppLocalizationsZh()), isNot(contains('更新成功')));
    },
  );

  test(
    'received bytes switch to verification and readiness hides progress',
    () async {
      await controller.download();
      connection.report('downloadingMain', received: 3, total: 3);
      expect(controller.progress, isNull);
      expect(controller.message(AppLocalizationsZh()), contains('等待设备校验结果'));
      expect(controller.canCancel, isTrue);
      connection.report('verifyingMain');
      expect(
        controller.message(AppLocalizationsZh()),
        contains('校验主固件镜像与 SHA-256'),
      );
      expect(controller.progress, isNull);
      connection.report('verifyingWireless');
      expect(
        controller.message(AppLocalizationsZh()),
        contains('校验无线固件镜像与 SHA-256'),
      );
      connection.report('downloadingWireless', received: 1, total: 3);
      expect(controller.progress, closeTo(1 / 3, 0.0001));
      expect(controller.message(AppLocalizationsZh()), startsWith('传输无线固件'));
      connection.report('preparingInstall');
      expect(controller.message(AppLocalizationsZh()), contains('整理固件并准备安装'));
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

  test('complete device cache skips app download and file transfer', () async {
    connection.firmwareTaskSupported = true;
    connection.firmwareMainCached = true;
    connection.firmwareTaskMainVersion = '1.1.2';
    expect(controller.deviceCacheAvailable, isTrue);
    await controller.useDeviceCache();
    expect(client.requests, isEmpty);
    expect(connection.starts, 1);
    expect(connection.receivedFile, isNull);
    expect(connection.receivedWirelessFile, isNull);
    expect(controller.step, FirmwareUpdateStep.transferring);
    connection.report('readyToInstall');
    expect(controller.step, FirmwareUpdateStep.prepared);
    expect(connection.installs, 0);
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

  Future<void> openDialog(WidgetTester tester, {String language = 'zh'}) async {
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
      controller.message = (l10n) => l10n.otaVerifyingMain;
      controller.notifyListeners();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      controller.step = FirmwareUpdateStep.prepared;
      controller.message = (l10n) => l10n.otaPrepared;
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
      expect(find.textContaining('重启安装指令已确认'), findsOneWidget);
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
      'remote observer closes without cancelling (background: $background)',
      (tester) async {
        controller.dispose();
        connection.firmwareTaskId = 'a' * 32;
        connection.firmwareTaskSource = 'remote';
        connection.firmwareTaskBusy = true;
        connection.firmwareUpdateStage = 'downloadingMain';
        connection.firmwareReceivedBytes = 1;
        connection.firmwareTotalBytes = 3;
        controller = FirmwareUpdateController.observe(connection);
        await openDialog(tester);
        expect(find.textContaining('设备联网更新'), findsOneWidget);
        expect(find.text('取消更新'), findsOneWidget);
        if (background) {
          await tester.tapAt(const Offset(10, 10));
        } else {
          await tester.tap(find.text('关闭'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(connection.taskCommands, 0);
        expect(connection.cancels, 0);
      },
    );
  }

  testWidgets(
    'checking observer only closes and cancellation returns for downloads',
    (tester) async {
      controller.dispose();
      connection.firmwareTaskId = 'a' * 32;
      connection.firmwareTaskSource = 'remote';
      connection.firmwareTaskBusy = true;
      connection.firmwareUpdateStage = 'downloadingMain';
      connection.firmwareReceivedBytes = 1;
      connection.firmwareTotalBytes = 3;
      controller = FirmwareUpdateController.observe(connection);
      await openDialog(tester);
      expect(find.text('取消更新'), findsOneWidget);
      for (final stage in ['checking', 'waitingForNetwork']) {
        connection.report(stage);
        await tester.pump();
        expect(find.text('关闭'), findsOneWidget);
        expect(find.text('取消更新'), findsNothing);
        expect(controller.canCancel, isFalse);
        await controller.cancel();
        expect(connection.taskCommands, 0);
      }
      connection.report('verifyingMain');
      await tester.pump();
      expect(find.text('取消更新'), findsOneWidget);
      expect(controller.canCancel, isTrue);
      connection.report('checking');
      await tester.pump();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(connection.taskCommands, 0);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  for (final stage in [
    'updateAvailable',
    'upToDate',
    'failed',
    'cancelled',
    'installing',
  ]) {
    testWidgets('remote $stage hides stale background update explanation', (
      tester,
    ) async {
      controller.dispose();
      connection.firmwareTaskId = 'a' * 32;
      connection.firmwareTaskSource = 'remote';
      connection.firmwareTaskBusy = true;
      connection.firmwareUpdateStage = 'downloadingMain';
      connection.firmwareReceivedBytes = 1;
      connection.firmwareTotalBytes = 3;
      controller = FirmwareUpdateController.observe(connection);
      await openDialog(tester);
      expect(find.textContaining('关闭窗口不影响设备当前任务'), findsOneWidget);
      connection.report(stage);
      await tester.pump();
      expect(find.textContaining('关闭窗口不影响设备当前任务'), findsNothing);
      expect(find.text('关闭'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('cache detection preserves primary button animation identity', (
    tester,
  ) async {
    await openDialog(tester);
    final primary = tester.element(
      find.widgetWithText(AppActionButton, '下载更新'),
    );
    controller.mainCached = true;
    controller.notifyListeners();
    await tester.pump();
    expect(
      tester.element(find.widgetWithText(AppActionButton, '使用已下载固件')),
      same(primary),
    );
    expect(
      tester.element(find.widgetWithText(AppActionButton, '重新下载')),
      isNot(same(primary)),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('verified cache offers reuse and redownload in the same dialog', (
    tester,
  ) async {
    controller.mainCached = true;
    await openDialog(tester);
    expect(find.text('使用已下载固件'), findsOneWidget);
    expect(find.text('重新下载'), findsOneWidget);
    expect(find.textContaining('已下载并校验：主固件'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  test(
    'disconnect without installation acknowledgement is not success',
    () async {
      await controller.download();
      connection.report('readyToInstall');
      connection.installReply = Completer<bool>();
      final installing = controller.install();
      connection.online(false);
      connection.installReply!.complete(false);
      await installing;
      expect(controller.step, FirmwareUpdateStep.failed);
      expect(controller.message(AppLocalizationsZh()), '设备未确认重启安装');
    },
  );

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
    expect(controller.message(AppLocalizationsZh()), contains('设备未确认取消更新'));
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
    expect(controller.message(AppLocalizationsZh()), '当前已是最新版本');
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
