import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/firmware_update_service.dart';
import 'lan_connection.dart';

enum FirmwareUpdateStep {
  awaitingConfirmation,
  downloading,
  transferring,
  prepared,
  installing,
  restartRequested,
  failed,
  cancelled,
}

/// 下载校验后自动传输，设备准备完成后等待用户确认重启安装。
class FirmwareUpdateController extends ChangeNotifier {
  FirmwareUpdateController(this.connection, this.release, {http.Client? client})
    : _deviceId = connection.device?.id,
      mainUpdateRequired = release.needsMainUpdate(connection.firmware),
      wirelessUpdateRequired = release.needsWirelessUpdate(
        connection.wirelessFirmware,
      ),
      _client = client ?? http.Client() {
    if (!mainUpdateRequired) message = '正在下载无线固件';
    connection.addListener(_connectionChanged);
  }

  final LanConnection connection;
  final FirmwareRelease release;
  final bool mainUpdateRequired;
  final bool wirelessUpdateRequired;
  final String? _deviceId;
  final http.Client _client;
  DownloadedFirmware? _files;
  Timer? _timeout;
  bool _disposed = false;
  bool _sawDisconnect = false;
  bool _transferAccepted = false;
  bool _downloadStarted = false;
  FirmwareUpdateStep step = FirmwareUpdateStep.awaitingConfirmation;
  String message = '正在下载主固件';
  double? progress = 0;
  bool get terminal =>
      step == FirmwareUpdateStep.restartRequested ||
      step == FirmwareUpdateStep.failed ||
      step == FirmwareUpdateStep.cancelled;
  bool get canCancel => !terminal && step != FirmwareUpdateStep.installing;

  void _publish() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> download() async {
    if (_downloadStarted || terminal || _disposed) return;
    _downloadStarted = true;
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
    final files = _files;
    if (terminal || _disposed || files == null) return;
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
      );
      if (terminal || _disposed) return;
      if (!accepted) {
        _fail('设备未接受传输请求，请确认设备已安装支持分步更新的新固件');
      } else {
        _transferAccepted = true;
        _connectionChanged();
      }
    } catch (error) {
      _fail('无法传输固件：$error');
    }
  }

  Future<void> install() async {
    if (step != FirmwareUpdateStep.prepared) return;
    step = FirmwareUpdateStep.installing;
    message = '正在请求设备重启安装…\n可关闭此窗口，设备将继续安装，请勿断电。';
    progress = null;
    _publish();
    final accepted = await connection.installLocalFirmwareUpdate();
    if (_disposed || terminal) return;
    if (!accepted && !_sawDisconnect) {
      _fail('设备未确认重启安装');
      return;
    }
    step = FirmwareUpdateStep.restartRequested;
    message = '固件传输完成，重启安装指令已发出，等待设备重启安装。';
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
        _sawDisconnect = true;
        message = '重启安装指令已发出，等待设备重启安装。';
        _publish();
      } else {
        _fail('设备连接已断开，更新已停止');
      }
      return;
    }
    if (step != FirmwareUpdateStep.transferring &&
        step != FirmwareUpdateStep.prepared &&
        step != FirmwareUpdateStep.installing) {
      return;
    }
    if (!_transferAccepted) return;
    switch (connection.firmwareUpdateStage) {
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
        message = '设备已接收并校验固件。点击“重启安装”按钮后，设备会自动重启并安装固件。';
        unawaited(_cleanFiles());
      case 'restarting':
      case 'installingWireless':
        final alreadyInstalling = step == FirmwareUpdateStep.installing;
        step = FirmwareUpdateStep.installing;
        message = '设备正在安装并重启…\n可关闭此窗口，设备将继续安装，请勿断电。';
        progress = null;
        if (!alreadyInstalling) _timeout?.cancel();
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
        message = receivedAll
            ? '${main ? '主固件' : '无线固件'}已传输完成，等待设备校验结果…'
            : '${main ? '传输主固件' : '传输无线固件'} · '
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
        await connection.cancelLocalFirmwareUpdate();
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
        _transferAccepted &&
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
    if (canCancel) unawaited(cancel());
    _disposed = true;
    _timeout?.cancel();
    _client.close();
    connection.removeListener(_connectionChanged);
    unawaited(_cleanFiles());
    super.dispose();
  }
}
