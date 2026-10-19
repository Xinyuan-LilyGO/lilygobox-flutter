import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../data/firmware_update_service.dart';
import '../../state/firmware_update_controller.dart';
import '../../state/lan_connection.dart';

/// 在同一个提示框中完成手动检测、更新说明和后续更新流程。
class FirmwareUpdateFlowDialog extends StatefulWidget {
  const FirmwareUpdateFlowDialog({
    super.key,
    required this.connection,
    required this.theme,
    required this.checkForUpdate,
  });

  final LanConnection connection;
  final AppTheme theme;
  final bool checkForUpdate;

  @override
  State<FirmwareUpdateFlowDialog> createState() =>
      _FirmwareUpdateFlowDialogState();
}

class _FirmwareUpdateFlowDialogState extends State<FirmwareUpdateFlowDialog> {
  FirmwareUpdateController? _controller;
  late final String? _deviceId = widget.connection.device?.id;
  bool _checking = true;
  bool _waitingForBackgroundCheck = false;
  FirmwareUpdateMessage? _error;
  Timer? _timeout;

  bool get _sameDevice =>
      widget.connection.connected && widget.connection.device?.id == _deviceId;

  @override
  void initState() {
    super.initState();
    widget.connection.addListener(_connectionChanged);
    if (widget.connection.firmwareTaskActive) {
      _controller = FirmwareUpdateController.observe(widget.connection);
      _checking = false;
    } else if (!widget.checkForUpdate &&
        widget.connection.firmwareRelease != null) {
      _setRelease(widget.connection.firmwareRelease!);
      _checking = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_check());
      });
    }
  }

  Future<void> _check() async {
    if (!_sameDevice) {
      _finishCheck(error: (l10n) => l10n.otaCheckDisconnected);
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 45), () {
      _finishCheck(error: (l10n) => l10n.otaCheckTimeout);
    });
    // 自动检测尚未结束时复用其结果，避免重复请求清单。
    _waitingForBackgroundCheck = widget.connection.firmwareUpdateChecking;
    if (_waitingForBackgroundCheck) return;
    try {
      final release = await widget.connection.checkFirmwareUpdate();
      if (mounted && _checking) _finishCheck(release: release);
    } catch (error) {
      if (mounted && _checking) {
        _finishCheck(error: _checkErrorText(error));
      }
    }
  }

  void _connectionChanged() {
    if (_controller != null || !_checking) return;
    if (_sameDevice && widget.connection.firmwareTaskActive) {
      _timeout?.cancel();
      setState(() {
        _checking = false;
        _controller = FirmwareUpdateController.observe(widget.connection);
      });
    } else if (!_sameDevice) {
      _finishCheck(error: (l10n) => l10n.otaCheckDisconnected);
    } else if (_waitingForBackgroundCheck &&
        !widget.connection.firmwareUpdateChecking) {
      _finishCheck(release: widget.connection.firmwareRelease);
    }
  }

  void _finishCheck({FirmwareRelease? release, FirmwareUpdateMessage? error}) {
    _timeout?.cancel();
    _waitingForBackgroundCheck = false;
    setState(() {
      _checking = false;
      _error =
          error ??
          (!_sameDevice
              ? (l10n) => l10n.otaCheckDisconnected
              : widget.connection.firmwareUpdateError != null
              ? _checkErrorText(widget.connection.firmwareUpdateError!)
              : null);
      if (_error == null && release != null) _setRelease(release);
    });
  }

  FirmwareUpdateMessage _checkErrorText(Object error) {
    final text = error.toString();
    if (text.contains('HTTP 404')) {
      return (l10n) => l10n.otaManifestMissing;
    }
    if (text.contains('timed out') || text.contains('TimeoutException')) {
      return (l10n) => l10n.otaManifestTimeout;
    }
    if (text.contains('invalid or incompatible')) {
      return (l10n) => l10n.otaManifestIncompatible;
    }
    if (text.contains('network request failed')) {
      return (l10n) => l10n.otaManifestNetwork;
    }
    return (l10n) => l10n.otaCheckError(text);
  }

  void _setRelease(FirmwareRelease release) {
    _controller = FirmwareUpdateController(widget.connection, release);
    unawaited(_controller!.prepareCache());
  }

  String _description(FirmwareRelease release, AppLocalizations l10n) {
    final connection = widget.connection;
    String version(String value) => value.isEmpty
        ? l10n.otaUnknown
        : value.startsWith('v')
        ? value
        : 'v$value';
    return [
      if (release.needsMainUpdate(connection.firmware))
        '${l10n.otaMainVersion}\n${version(connection.firmware)}  →  ${version(release.mainVersion)}',
      if (release.needsWirelessUpdate(connection.wirelessFirmware))
        '${l10n.otaWirelessVersion}\n${version(connection.wirelessFirmware)}  →  ${version(release.wirelessVersion)}',
      if (release.notes.isNotEmpty)
        '${l10n.otaNotes}\n${release.notes.map((note) => '• $note').join('\n')}',
    ].join('\n\n');
  }

  @override
  void dispose() {
    _timeout?.cancel();
    widget.connection.removeListener(_connectionChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller case final controller?) {
      return FirmwareUpdateDialog(
        controller: controller,
        theme: widget.theme,
        description: controller.observer
            ? ''
            : _description(controller.release, context.l10n),
        onRetry: controller.observer
            ? null
            : () {
                if (!_sameDevice || widget.connection.firmwareTaskActive) {
                  return;
                }
                final release = controller.release;
                controller.dispose();
                setState(() => _setRelease(release));
              },
      );
    }
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        _error == null
            ? context.l10n.otaCheckTitle
            : context.l10n.otaCheckFailed,
      ),
      content: SizedBox(
        width: 390,
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              if (_checking) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  _checking
                      ? context.l10n.otaChecking
                      : _error?.call(context.l10n) ?? context.l10n.otaLatest,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        _checkButton(
          _checking ? context.l10n.otaCancel : context.l10n.otaClose,
          () => Navigator.of(context).pop(),
        ),
        if (_error != null && _sameDevice)
          _checkButton(
            context.l10n.otaRetry,
            () => unawaited(_check()),
            primary: true,
          ),
      ],
    );
  }

  Widget _checkButton(
    String label,
    VoidCallback action, {
    bool primary = false,
  }) => AppActionButton(
    theme: widget.theme,
    label: label,
    primary: primary,
    settingBackground: !primary,
    onPressed: action,
    fontSize: 12,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    borderRadius: BorderRadius.circular(8),
  );
}

class FirmwareUpdateDialog extends StatefulWidget {
  const FirmwareUpdateDialog({
    super.key,
    required this.controller,
    required this.theme,
    required this.description,
    this.onRetry,
  });

  final FirmwareUpdateController controller;
  final AppTheme theme;
  final String description;
  final VoidCallback? onRetry;

  @override
  State<FirmwareUpdateDialog> createState() => _FirmwareUpdateDialogState();
}

class _FirmwareUpdateDialogState extends State<FirmwareUpdateDialog> {
  bool _cancelling = false;
  bool _dismissed = false;
  FirmwareUpdateController get controller => widget.controller;
  AppTheme get theme => widget.theme;

  Future<void> _cancelAndClose() async {
    if (_cancelling || !controller.canCancel) return;
    setState(() => _cancelling = true);
    // 取消请求在后台等待设备确认，界面立即退出，避免阻塞用户等待超时。
    unawaited(controller.cancel());
    if (!mounted) return;
    setState(() => _dismissed = true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (_dismissed) return const SizedBox.shrink();
      final step = controller.step;
      final installing = step == FirmwareUpdateStep.installing;
      final awaiting =
          !_cancelling && step == FirmwareUpdateStep.awaitingConfirmation;
      final working =
          _cancelling ||
          !awaiting &&
              !controller.terminal &&
              step != FirmwareUpdateStep.prepared;
      return PopScope(
        canPop: !_cancelling,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) return;
          // 退场动画期间不再绘制取消结果，避免看起来又弹出一层提示框。
          setState(() => _dismissed = true);
          if (controller.cancelOnDismiss && controller.canCancel) {
            unawaited(controller.cancel());
          }
        },
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            awaiting
                ? context.l10n.otaFound
                : controller.observer
                ? context.l10n.otaDeviceTitle
                : context.l10n.otaTitle,
          ),
          content: SizedBox(
            width: 390,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controller.observer &&
                      !controller.terminal &&
                      !installing) ...[
                    Text(
                      widget.controller.connection.firmwareTaskSource ==
                              'remote'
                          ? context.l10n.otaRemoteSource
                          : context.l10n.otaLocalSource,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (awaiting) ...[
                    Text(widget.description, softWrap: true),
                    if (controller.deviceCacheAvailable) ...[
                      const SizedBox(height: 16),
                      Text(context.l10n.otaDeviceCacheHint),
                    ],
                    if (!controller.deviceCacheAvailable &&
                        controller.cacheChecking) ...[
                      const SizedBox(height: 16),
                      Text(context.l10n.otaCacheChecking),
                    ] else if (!controller.deviceCacheAvailable &&
                        controller.hasCache) ...[
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.otaAppCacheHint(
                          [
                            if (controller.mainCached)
                              context.l10n.otaMainComponent,
                            if (controller.wirelessCached)
                              context.l10n.otaWirelessComponent,
                          ].join(context.l10n.otaComponentsSeparator),
                        ),
                      ),
                    ],
                  ] else
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (working &&
                              (_cancelling || controller.progress == null)) ...[
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Text(
                              _cancelling
                                  ? context.l10n.otaCancelling
                                  : controller.message(context.l10n),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!_cancelling &&
                      working &&
                      controller.progress != null) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: controller.progress),
                  ],
                  if (!_cancelling &&
                      working &&
                      controller.progress != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${(controller.progress! * 100).floor()}%',
                      textAlign: TextAlign.end,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (step == FirmwareUpdateStep.failed && widget.onRetry != null)
              _button(
                context.l10n.otaRetry,
                widget.onRetry,
                id: 'retry',
                primary: true,
              ),
            if (controller.observer && !controller.terminal && !installing)
              _button(
                context.l10n.otaClose,
                () => Navigator.of(context).pop(),
                id: 'close',
              ),
            if (!installing &&
                (_cancelling || !controller.terminal) &&
                controller.canCancel)
              _button(
                awaiting
                    ? context.l10n.otaCancel
                    : context.l10n.otaCancelUpdate,
                !_cancelling && controller.canCancel
                    ? () => unawaited(_cancelAndClose())
                    : null,
                id: 'cancel',
              ),
            if (awaiting &&
                (controller.hasCache || controller.deviceCacheAvailable))
              _button(
                context.l10n.otaRedownload,
                () => controller.download(reuseCache: false),
                id: 'redownload',
              ),
            if (awaiting)
              _button(
                controller.deviceCacheAvailable
                    ? context.l10n.otaUseDeviceCache
                    : controller.hasCache
                    ? context.l10n.otaUseCache
                    : context.l10n.otaDownloadUpdate,
                controller.cacheChecking
                    ? null
                    : controller.deviceCacheAvailable
                    ? () => controller.useDeviceCache()
                    : () => controller.download(),
                id: 'download',
                primary: true,
              ),
            if (!_cancelling &&
                step == FirmwareUpdateStep.prepared &&
                controller.canControl)
              _button(
                context.l10n.otaInstall,
                () => controller.install(),
                id: 'install',
                primary: true,
              ),
            if (!_cancelling && (installing || controller.terminal))
              _button(
                context.l10n.otaClose,
                () => Navigator.of(context).pop(),
                id: 'close',
              ),
          ],
        ),
      );
    },
  );

  Widget _button(
    String label,
    VoidCallback? action, {
    required String id,
    bool primary = false,
  }) => Opacity(
    key: ValueKey(id),
    opacity: action == null ? .45 : 1,
    child: AppActionButton(
      theme: theme,
      label: label,
      primary: primary,
      settingBackground: !primary,
      onPressed: action,
      fontSize: 12,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      borderRadius: BorderRadius.circular(8),
    ),
  );
}
