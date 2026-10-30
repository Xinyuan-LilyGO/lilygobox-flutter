import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../generated/l10n/app_localizations.dart';
import '../data/firmware_cache.dart';
import '../data/firmware_update_service.dart';
import 'lan_connection.dart';

typedef FirmwareUpdateMessage = String Function(AppLocalizations l10n);

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
    if (!mainUpdateRequired) message = (l10n) => l10n.otaDownloadingWireless;
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
  bool integrityFailed = false;
  bool retryAllowed = true;
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
        terminal ||
        _disposed) {
      return;
    }
    _downloadStarted = true;
    step = FirmwareUpdateStep.transferring;
    message = (l10n) => l10n.otaRequestCache;
    progress = null;
    _publish();
    _timeout = Timer(
      const Duration(minutes: 10),
      () => _fail((l10n) => l10n.otaCacheTimeout),
    );
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
        _fail((l10n) => l10n.otaCacheRejected);
        return;
      }
      _transferAccepted = true;
      _taskId = connection.firmwareTaskId;
      _connectionChanged();
    } catch (error) {
      _fail((l10n) => l10n.otaCacheFailed(error.toString()));
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
    if (release == null || cache == null || deviceCacheAvailable) return;
    cacheChecking = true;
    _publish();
    try {
      await cache!.clean();
      final mainStatus = mainUpdateRequired
          ? await cache!.inspect(
              _cacheScope,
              'main',
              release.mainVersion,
              release.mainSize,
              release.mainSha256,
            )
          : FirmwareCacheStatus.missing;
      final wirelessStatus = wirelessUpdateRequired
          ? await cache!.inspect(
              _cacheScope,
              'wireless',
              release.wirelessVersion,
              release.wirelessSize,
              release.wirelessSha256,
            )
          : FirmwareCacheStatus.missing;
      mainCached = mainStatus == FirmwareCacheStatus.valid;
      wirelessCached = wirelessStatus == FirmwareCacheStatus.valid;
      if (mainStatus == FirmwareCacheStatus.invalid ||
          wirelessStatus == FirmwareCacheStatus.invalid) {
        integrityFailed = true;
        _fail(
          (l10n) => l10n.otaIntegrityFailed(
            mainStatus == FirmwareCacheStatus.invalid
                ? l10n.otaMainComponent
                : l10n.otaWirelessComponent,
          ),
        );
      }
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
  FirmwareUpdateMessage message = (l10n) => l10n.otaDownloadingMain;
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
      _fail((l10n) => l10n.otaLatest);
      return;
    }
    step = FirmwareUpdateStep.downloading;
    _publish();
    _timeout = Timer(
      const Duration(minutes: 10),
      () => _fail((l10n) => l10n.otaDownloadTimeout),
    );
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
          message = (l10n) => l10n.otaProgress(
            main ? l10n.otaDownloadMain : l10n.otaDownloadWireless,
            _bytes(received),
            _bytes(total),
          );
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
    } on FirmwareIntegrityException catch (error) {
      integrityFailed = true;
      _fail(
        (l10n) => l10n.otaIntegrityFailed(
          error.main ? l10n.otaMainComponent : l10n.otaWirelessComponent,
        ),
      );
    } catch (error) {
      if (!terminal && !_disposed) {
        _fail((l10n) => l10n.otaDownloadFailed(error.toString()));
      }
    }
  }

  Future<void> _transfer() async {
    final release = _release;
    final files = _files;
    if (terminal || _disposed || files == null || release == null) return;
    step = FirmwareUpdateStep.transferring;
    message = (l10n) => l10n.otaWaitingTransfer;
    progress = null;
    _publish();
    _timeout = Timer(
      const Duration(minutes: 10),
      () => _fail((l10n) => l10n.otaTransferTimeout),
    );
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
        _fail((l10n) => l10n.otaTransferRejected);
      } else {
        _transferAccepted = true;
        _taskId = connection.firmwareTaskId.isEmpty
            ? null
            : connection.firmwareTaskId;
        _connectionChanged();
      }
    } catch (error) {
      _fail((l10n) => l10n.otaTransferFailed(error.toString()));
    }
  }

  Future<void> install() async {
    if (step != FirmwareUpdateStep.prepared || !canControl) return;
    step = FirmwareUpdateStep.installing;
    message = (l10n) => l10n.otaRequestInstall;
    progress = null;
    _publish();
    final accepted = observer
        ? await connection.controlFirmwareTask(install: true, taskId: _taskId!)
        : await connection.installLocalFirmwareUpdate();
    if (_disposed || terminal) return;
    if (!accepted) {
      _fail((l10n) => l10n.otaInstallRejected);
      return;
    }
    step = FirmwareUpdateStep.restartRequested;
    message = (l10n) => l10n.otaInstallConfirmed;
    progress = null;
    _timeout?.cancel();
    _publish();
  }

  void _connectionChanged() {
    if (_disposed || terminal) return;
    if (connection.device?.id != _deviceId && connection.connected) {
      _fail((l10n) => l10n.otaDeviceChanged);
      return;
    }
    if (!connection.connected) {
      if (step == FirmwareUpdateStep.installing) {
        message = (l10n) => l10n.otaInstallDisconnected;
        _publish();
      } else {
        _fail(
          (l10n) =>
              observer ? l10n.otaObserverDisconnected : l10n.otaDisconnected,
        );
      }
      return;
    }
    if (_taskId != null && connection.firmwareTaskId != _taskId) {
      _fail((l10n) => l10n.otaTaskChanged);
      return;
    }
    if (!_transferAccepted &&
        connection.firmwareTaskActive &&
        step != FirmwareUpdateStep.transferring) {
      _fail((l10n) => l10n.otaOtherTask);
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
    final deviceStage = connection.firmwareUpdateStage;
    switch (deviceStage) {
      case 'upToDate':
      case 'updateAvailable' when observer:
      case 'idle' when observer:
        step = FirmwareUpdateStep.completed;
        progress = null;
        message = (l10n) => switch (deviceStage) {
          'upToDate' => l10n.otaLatestComplete,
          'updateAvailable' => l10n.otaCheckAvailable,
          _ => l10n.otaNoTask,
        };
      case 'failed':
        final detail = connection.firmwareUpdateMessage;
        final failedWireless = connection.firmwareFailedComponent == 'wireless';
        integrityFailed = connection.firmwareIntegrityFailed;
        retryAllowed = !connection.firmwareManualUpdateRequired;
        _fail(
          (l10n) => integrityFailed
              ? l10n.otaIntegrityFailed(
                  failedWireless
                      ? l10n.otaWirelessComponent
                      : l10n.otaMainComponent,
                )
              : l10n.otaDeviceFailed(detail),
        );
        return;
      case 'cancelled':
        step = FirmwareUpdateStep.cancelled;
        message = (l10n) => l10n.otaDeviceCancelled;
        _timeout?.cancel();
        unawaited(_cleanFiles());
      case 'readyToInstall' when step == FirmwareUpdateStep.transferring:
        _timeout?.cancel();
        step = FirmwareUpdateStep.prepared;
        progress = null;
        message = (l10n) =>
            canControl ? l10n.otaPrepared : l10n.otaPreparedOtherApp;
        unawaited(_cleanFiles());
      case 'restarting':
      case 'installing':
      case 'installingWireless':
        final alreadyInstalling = step == FirmwareUpdateStep.installing;
        step = FirmwareUpdateStep.installing;
        message = (l10n) => l10n.otaInstalling;
        progress = null;
        if (!alreadyInstalling) _timeout?.cancel();
      case 'checking':
      case 'waitingForNetwork':
        progress = null;
        message = (l10n) => l10n.otaDeviceChecking;
      case 'paused':
        progress = null;
        message = (l10n) => l10n.otaPaused;
      case 'verifyingMain':
        progress = null;
        message = (l10n) => l10n.otaVerifyingMain;
      case 'verifyingWireless':
        progress = null;
        message = (l10n) => l10n.otaVerifyingWireless;
      case 'preparingInstall':
        progress = null;
        message = (l10n) => l10n.otaPreparing;
      case 'downloadingMain':
      case 'downloadingWireless':
        final main = connection.firmwareUpdateStage == 'downloadingMain';
        final total = connection.firmwareTotalBytes;
        final received = connection.firmwareReceivedBytes;
        final receivedAll = total > 0 && received >= total;
        progress = total > 0 && !receivedAll
            ? (received / total).clamp(0, 1)
            : null;
        final deviceDownload =
            observer && connection.firmwareTaskSource == 'remote';
        message = (l10n) {
          final component = main
              ? l10n.otaMainComponent
              : l10n.otaWirelessComponent;
          final action = deviceDownload
              ? (main
                    ? l10n.otaDeviceDownloadMain
                    : l10n.otaDeviceDownloadWireless)
              : (main ? l10n.otaTransferMain : l10n.otaTransferWireless);
          if (receivedAll) {
            return deviceDownload
                ? l10n.otaDownloadComplete(component)
                : l10n.otaTransferComplete(component);
          }
          return total > 0
              ? l10n.otaProgress(action, _bytes(received), _bytes(total))
              : l10n.otaAwaitingProgress(action);
        };
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
    message = (l10n) => l10n.otaCancelled;
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
          if (!accepted) {
            throw StateError('Firmware task cancellation rejected');
          }
        } else {
          await connection.cancelLocalFirmwareUpdate();
        }
      } catch (error) {
        step = FirmwareUpdateStep.failed;
        message = (l10n) => l10n.otaCancelUnconfirmed(error.toString());
        _publish();
      }
    }
    await _cleanFiles();
  }

  void _fail(FirmwareUpdateMessage error) {
    if (_disposed || terminal) return;
    final notifyDevice =
        !observer &&
        _transferAccepted &&
        connection.firmwareUpdateStage != 'failed' &&
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
