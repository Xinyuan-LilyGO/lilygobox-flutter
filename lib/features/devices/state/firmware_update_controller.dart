import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/firmware_cache.dart';
import '../data/firmware_update_service.dart';
import 'lan_connection.dart';

enum FirmwareUpdateStep {
  awaitingConfirmation,
  downloading,
  transferring,
  prepared,
  installing,
  restartRequested,
  completed,
  failed,
  cancelled,
}

/// 下载校验后自动传输，设备准备完成后等待用户确认重启安装。
class FirmwareUpdateController extends ChangeNotifier {
  FirmwareUpdateController(
    this.connection,
    FirmwareRelease targetRelease, {
    http.Client? client,
    FirmwareCache? cache,
  }) : _deviceId = connection.device?.id,
       _release = targetRelease,
       observer = false,
       cache = cache ?? (client == null ? FirmwareCache() : null),
       mainUpdateRequired = targetRelease.needsMainUpdate(connection.firmware),
       wirelessUpdateRequired = targetRelease.needsWirelessUpdate(
         connection.wirelessFirmware,
       ),
       _client = client ?? http.Client() {
    if (!mainUpdateRequired) message = '正在下载无线固件';
    connection.addListener(_connectionChanged);
  }

  FirmwareUpdateController.observe(this.connection)
    : _release = null,
      observer = true,
      cache = null,
      mainUpdateRequired = false,
      wirelessUpdateRequired = false,
      _deviceId = connection.device?.id,
      _client = http.Client() {
    _taskId = connection.firmwareTaskId;
    _transferAccepted = true;
    step = FirmwareUpdateStep.transferring;
    connection.addListener(_connectionChanged);
    _connectionChanged();
  }

  final LanConnection connection;
  final FirmwareRelease? _release;
  FirmwareRelease get release =>
      _release ?? (throw StateError('Device task has no app release'));
  final bool observer;
  final FirmwareCache? cache;
  String? _taskId;
  bool cacheChecking = false;
  bool mainCached = false;
  bool wirelessCached = false;
  bool _reuseCache = true;
  bool get hasCache => mainCached || wirelessCached;
  bool get deviceCacheAvailable {
    final release = _release;
    return release != null &&
        connection.firmwareTaskSupported &&
        !connection.firmwareTaskActive &&
        (!mainUpdateRequired ||
            connection.firmwareMainCached &&
                connection.firmwareTaskMainVersion == release.mainVersion) &&
        (!wirelessUpdateRequired ||
            connection.firmwareWirelessCached &&
                connection.firmwareTaskWirelessVersion ==
                    release.wirelessVersion);
  }

  Future<void> useDeviceCache() async {
    final release = _release;
    if (!deviceCacheAvailable ||
        release == null ||
        _downloadStarted ||
        _disposed) {
      return;
    }
    _downloadStarted = true;
    step = FirmwareUpdateStep.transferring;
    message = '正在请求设备重新校验已下载的固件…';
    progress = null;
    _publish();
    _timeout = Timer(const Duration(minutes: 10), () => _fail('设备缓存校验超时'));
    try {
      final accepted = await connection.startLocalMainFirmwareUpdate(
        firmware: null,
        version: release.mainVersion,
        sha256: release.mainSha256,
        mainSize: release.mainSize,
        wirelessFirmware: null,
        wirelessVersion: release.wirelessVersion,
        wirelessSha256: release.wirelessSha256,
        wirelessSize: release.wirelessSize,
        deviceCacheOnly: true,
      );
      if (_disposed || terminal) return;
      if (!accepted) {
        _fail('设备未接受缓存复用请求，请重试或重新下载');
        return;
      }
      _transferAccepted = true;
      _taskId = connection.firmwareTaskId;
      _connectionChanged();
    } catch (error) {
      _fail('设备缓存复用失败：$error');
    }
  }

  bool get cancelOnDismiss => !observer;
  bool get canControl => !observer || connection.canControlFirmwareTask;
  String get _cacheScope {
    final device = connection.device;
    final hardware = connection.firmwareHardware;
    return '${device?.model}|${device?.modelVersion}|'
        '${hardware?.main.model}:${hardware?.main.revision}|'
        '${hardware?.wireless.model}:${hardware?.wireless.revision}';
  }

  Future<void> prepareCache() async {
    final release = _release;
    if (release == null || cache == null) return;
    cacheChecking = true;
    _publish();
    try {
      mainCached =
          mainUpdateRequired &&
          await cache!.contains(
            _cacheScope,
            'main',
            release.mainVersion,
            release.mainSize,
            release.mainSha256,
          );
      wirelessCached =
          wirelessUpdateRequired &&
          await cache!.contains(
            _cacheScope,
            'wireless',
            release.wirelessVersion,
            release.wirelessSize,
            release.wirelessSha256,
          );
    } finally {
      cacheChecking = false;
      _publish();
    }
  }

  final bool mainUpdateRequired;
  final bool wirelessUpdateRequired;
  final String? _deviceId;
  final http.Client _client;
  DownloadedFirmware? _files;
  Timer? _timeout;
  bool _disposed = false;
  bool _transferAccepted = false;
  bool _downloadStarted = false;
  FirmwareUpdateStep step = FirmwareUpdateStep.awaitingConfirmation;
  String message = '正在下载主固件';
  double? progress = 0;
  bool get terminal =>
      step == FirmwareUpdateStep.restartRequested ||
      step == FirmwareUpdateStep.completed ||
      step == FirmwareUpdateStep.failed ||
      step == FirmwareUpdateStep.cancelled;
  bool get canCancel =>
      canControl &&
      !terminal &&
      step != FirmwareUpdateStep.installing &&
      (!observer ||
          const {
            'downloadingMain',
            'downloadingWireless',
            'verifyingMain',
            'verifyingWireless',
            'preparingInstall',
            'paused',
            'readyToInstall',
          }.contains(connection.firmwareUpdateStage));

  void _publish() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> download({bool reuseCache = true}) async {
    final release = _release;
    if (release == null || cacheChecking || connection.firmwareTaskActive) {
      return;
    }
    if (_downloadStarted || terminal || _disposed) return;
    _downloadStarted = true;
    _reuseCache = reuseCache;
    final scope = _cacheScope;
    if (!mainUpdateRequired && !wirelessUpdateRequired) {
      _fail('当前已是最新版本');
      return;
    }
    step = FirmwareUpdateStep.downloading;
    _publish();
    _timeout = Timer(const Duration(minutes: 10), () => _fail('下载超时，请重试'));
    try {
      final files = await const FirmwareUpdateService().download(
        release,
        downloadMain: mainUpdateRequired,
        downloadWireless: wirelessUpdateRequired,
        client: _client,
        cache: cache,
        cacheScope: scope,
        reuseCache: reuseCache,
        isCancelled: () => terminal || _disposed,
        onProgress: (main, received, total) {
          if (terminal || _disposed) return;
          message =
              '${main ? '下载主固件' : '下载无线固件'} · ${_bytes(received)} / ${_bytes(total)}';
          progress =
              (received +
                  (main || !mainUpdateRequired ? 0 : release.mainSize)) /
              ((mainUpdateRequired ? release.mainSize : 0) +
                  (wirelessUpdateRequired ? release.wirelessSize : 0));
          _publish();
        },
      );
      _files = files;
      if (terminal || _disposed) {
        await _cleanFiles();
        return;
      }
      _timeout?.cancel();
      await _transfer();
    } catch (error) {
      if (!terminal && !_disposed) _fail('下载或校验失败：$error');
    }
  }

  Future<void> _transfer() async {
    final release = _release;
    final files = _files;
    if (terminal || _disposed || files == null || release == null) return;
    step = FirmwareUpdateStep.transferring;
    message = '等待设备接受传输请求…';
    progress = null;
    _publish();
    _timeout = Timer(const Duration(minutes: 10), () => _fail('设备传输超时'));
    try {
      final accepted = await connection.startLocalMainFirmwareUpdate(
        firmware: files.main,
        version: release.mainVersion,
        sha256: release.mainSha256,
        mainSize: release.mainSize,
        wirelessFirmware: files.wireless,
        wirelessVersion: release.wirelessVersion,
        wirelessSha256: release.wirelessSha256,
        wirelessSize: release.wirelessSize,
        reuseCache: _reuseCache,
      );
      if (terminal || _disposed) return;
      if (!accepted) {
        _fail('设备未接受传输请求，请确认设备已安装支持分步更新的新固件');
      } else {
        _transferAccepted = true;
        _taskId = connection.firmwareTaskId.isEmpty
            ? null
            : connection.firmwareTaskId;
        _connectionChanged();
      }
    } catch (error) {
      _fail('无法传输固件：$error');
    }
  }

  Future<void> install() async {
    if (step != FirmwareUpdateStep.prepared || !canControl) return;
    step = FirmwareUpdateStep.installing;
    message = '正在请求设备重启安装…\n可关闭此窗口，设备将继续安装，请勿断电。';
    progress = null;
    _publish();
    final accepted = observer
        ? await connection.controlFirmwareTask(install: true, taskId: _taskId!)
        : await connection.installLocalFirmwareUpdate();
    if (_disposed || terminal) return;
    if (!accepted) {
      _fail('设备未确认重启安装');
      return;
    }
    step = FirmwareUpdateStep.restartRequested;
    message = '重启安装指令已确认，设备将自动安装并重启，请勿断电。';
    progress = null;
    _timeout?.cancel();
    _publish();
  }

  void _connectionChanged() {
    if (_disposed || terminal) return;
    if (connection.device?.id != _deviceId && connection.connected) {
      _fail('设备已切换，本次更新已终止');
      return;
    }
    if (!connection.connected) {
      if (step == FirmwareUpdateStep.installing) {
        message = '设备连接已断开，正在等待重启安装指令的确认结果…';
        _publish();
      } else {
        _fail(observer ? '设备连接已断开，请重新连接后查看设备更新状态。' : '设备连接已断开，更新已停止');
      }
      return;
    }
    if (_taskId != null && connection.firmwareTaskId != _taskId) {
      _fail('设备更新任务已切换，请重新打开更新窗口');
      return;
    }
    if (!_transferAccepted &&
        connection.firmwareTaskActive &&
        step != FirmwareUpdateStep.transferring) {
      _fail('设备已在进行另一项更新，请关闭窗口查看设备当前任务');
      return;
    }
    if (step == FirmwareUpdateStep.awaitingConfirmation) {
      _publish();
      return;
    }
    if (step != FirmwareUpdateStep.transferring &&
        step != FirmwareUpdateStep.prepared &&
        step != FirmwareUpdateStep.installing) {
      return;
    }
    if (!_transferAccepted) return;
    switch (connection.firmwareUpdateStage) {
      case 'upToDate':
      case 'updateAvailable' when observer:
      case 'idle' when observer:
        step = FirmwareUpdateStep.completed;
        progress = null;
        message = switch (connection.firmwareUpdateStage) {
          'upToDate' => '当前已是最新版本。',
          'updateAvailable' => '发现新版本，请在设备上或关闭窗口后选择下载更新。',
          _ => '设备当前没有进行中的更新任务。',
        };
      case 'failed':
        _fail('设备更新失败：${connection.firmwareUpdateMessage}');
        return;
      case 'cancelled':
        step = FirmwareUpdateStep.cancelled;
        message = '设备已取消更新，保留当前固件。';
        _timeout?.cancel();
        unawaited(_cleanFiles());
      case 'readyToInstall' when step == FirmwareUpdateStep.transferring:
        _timeout?.cancel();
        step = FirmwareUpdateStep.prepared;
        progress = null;
        message = canControl
            ? '设备已接收固件并完成校验。点击“重启安装”后，设备将熄屏安装并自动重启。'
            : '设备固件已就绪，请在发起更新的应用中确认重启安装。';
        unawaited(_cleanFiles());
      case 'restarting':
      case 'installing':
      case 'installingWireless':
        final alreadyInstalling = step == FirmwareUpdateStep.installing;
        step = FirmwareUpdateStep.installing;
        message = '设备正在安装并重启，请勿断电。\n关闭窗口不影响安装。';
        progress = null;
        if (!alreadyInstalling) _timeout?.cancel();
      case 'checking':
      case 'waitingForNetwork':
        progress = null;
        message = '设备正在联网检查固件更新…';
      case 'paused':
        progress = null;
        message = '设备已暂停下载，可在设备上继续，或取消本次更新。';
      case 'verifyingMain':
        progress = null;
        message = '设备正在校验主固件镜像与 SHA-256，请稍候…';
      case 'verifyingWireless':
        progress = null;
        message = '设备正在校验无线固件镜像与 SHA-256，请稍候…';
      case 'preparingInstall':
        progress = null;
        message = '设备正在整理固件并准备安装，请稍候…';
      case 'downloadingMain':
      case 'downloadingWireless':
        final main = connection.firmwareUpdateStage == 'downloadingMain';
        final total = connection.firmwareTotalBytes;
        final received = connection.firmwareReceivedBytes;
        final receivedAll = total > 0 && received >= total;
        progress = total > 0 && !receivedAll
            ? (received / total).clamp(0, 1)
            : null;
        final action = observer && connection.firmwareTaskSource == 'remote'
            ? '设备下载'
            : '传输';
        message = receivedAll
            ? '${main ? '主固件' : '无线固件'}${action == '设备下载' ? '下载' : '传输'}完成，等待设备校验结果…'
            : '$action${main ? '主固件' : '无线固件'} · '
                  '${total > 0 ? '${_bytes(received)} / ${_bytes(total)}' : '等待设备报告接收进度'}';
      default:
        break;
    }
    _publish();
  }

  Future<void> cancel() async {
    if (!canCancel) return;
    final wasTransferring =
        step == FirmwareUpdateStep.transferring ||
        step == FirmwareUpdateStep.prepared;
    step = FirmwareUpdateStep.cancelled;
    message = '更新已取消，保留当前固件。';
    _timeout?.cancel();
    _client.close();
    _publish();
    if (wasTransferring) {
      try {
        if (observer) {
          final accepted = await connection.controlFirmwareTask(
            install: false,
            taskId: _taskId!,
          );
          if (!accepted) throw StateError('设备拒绝取消当前任务');
        } else {
          await connection.cancelLocalFirmwareUpdate();
        }
      } catch (error) {
        step = FirmwareUpdateStep.failed;
        message = '设备未确认取消更新：$error';
        _publish();
      }
    }
    await _cleanFiles();
  }

  void _fail(String error) {
    if (_disposed || terminal) return;
    final notifyDevice =
        !observer &&
        _transferAccepted &&
        (_taskId == null || _taskId == connection.firmwareTaskId) &&
        (step == FirmwareUpdateStep.transferring ||
            step == FirmwareUpdateStep.prepared);
    step = FirmwareUpdateStep.failed;
    message = error;
    progress = null;
    _timeout?.cancel();
    _client.close();
    if (notifyDevice) {
      unawaited(
        connection.cancelLocalFirmwareUpdate().catchError((Object _) {}),
      );
    }
    unawaited(_cleanFiles());
    _publish();
  }

  Future<void> _cleanFiles() async {
    final files = _files;
    _files = null;
    if (files == null) return;
    try {
      if (await files.directory.exists()) {
        await files.directory.delete(recursive: true);
      }
    } on FileSystemException {
      // HTTP 服务仍在收尾时由连接层再次清理。
    }
  }

  static String _bytes(int value) =>
      '${(value / 1024 / 1024).toStringAsFixed(2)} MB';

  @override
  void dispose() {
    if (_disposed) return;
    if (cancelOnDismiss && canCancel) unawaited(cancel());
    _disposed = true;
    _timeout?.cancel();
    _client.close();
    connection.removeListener(_connectionChanged);
    unawaited(_cleanFiles());
    super.dispose();
  }
}
