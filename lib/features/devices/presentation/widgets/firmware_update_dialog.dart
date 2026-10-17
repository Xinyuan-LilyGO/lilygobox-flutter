import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
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
  String? _error;
  String _description = '';
  Timer? _timeout;

  bool get _sameDevice =>
      widget.connection.connected && widget.connection.device?.id == _deviceId;

  @override
  void initState() {
    super.initState();
    widget.connection.addListener(_connectionChanged);
    if (!widget.checkForUpdate && widget.connection.firmwareRelease != null) {
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
      _finishCheck(error: '设备已断开或已切换，请重新连接后检查更新');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 30), () {
      _finishCheck(error: '检查更新超时，请检查网络后重试');
    });
    // 自动检测尚未结束时复用其结果，避免重复请求清单。
    _waitingForBackgroundCheck = widget.connection.firmwareUpdateChecking;
    if (_waitingForBackgroundCheck) return;
    try {
      final release = await widget.connection.checkFirmwareUpdate();
      if (mounted && _checking) _finishCheck(release: release);
    } catch (_) {
      if (mounted && _checking) {
        _finishCheck(error: '检查更新失败，请检查网络后重试');
      }
    }
  }

  void _connectionChanged() {
    if (_controller != null || !_checking) return;
    if (!_sameDevice) {
      _finishCheck(error: '设备已断开或已切换，请重新连接后检查更新');
    } else if (_waitingForBackgroundCheck &&
        !widget.connection.firmwareUpdateChecking) {
      _finishCheck(release: widget.connection.firmwareRelease);
    }
  }

  void _finishCheck({FirmwareRelease? release, String? error}) {
    _timeout?.cancel();
    _waitingForBackgroundCheck = false;
    setState(() {
      _checking = false;
      _error =
          error ??
          (!_sameDevice
              ? '设备已断开或已切换，请重新连接后检查更新'
              : widget.connection.firmwareUpdateError != null
              ? '检查更新失败，请检查网络后重试'
              : null);
      if (_error == null && release != null) _setRelease(release);
    });
  }

  void _setRelease(FirmwareRelease release) {
    final connection = widget.connection;
    String version(String value) => value.isEmpty
        ? '未知'
        : value.startsWith('v')
        ? value
        : 'v$value';
    _description = [
      if (release.needsMainUpdate(connection.firmware))
        '主固件版本\n${version(connection.firmware)}  →  ${version(release.mainVersion)}',
      if (release.needsWirelessUpdate(connection.wirelessFirmware))
        '无线固件版本\n${version(connection.wirelessFirmware)}  →  ${version(release.wirelessVersion)}',
      if (release.notes.isNotEmpty)
        '更新内容\n${release.notes.map((note) => '• $note').join('\n')}',
    ].join('\n\n');
    _controller = FirmwareUpdateController(connection, release);
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
        description: _description,
      );
    }
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(_error == null ? '检查固件更新' : '检查更新失败'),
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
                child: Text(_checking ? '正在检查更新…' : _error ?? '当前已是最新版本'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        _checkButton(
          _checking ? '取消' : '关闭',
          () => Navigator.of(context).pop(),
        ),
        if (_error != null && _sameDevice)
          _checkButton('重试', () => unawaited(_check()), primary: true),
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
  });

  final FirmwareUpdateController controller;
  final AppTheme theme;
  final String description;

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
    await controller.cancel();
    if (!mounted) return;
    if (controller.step == FirmwareUpdateStep.cancelled) {
      Navigator.of(context).pop();
    } else {
      setState(() => _cancelling = false);
    }
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
          if (controller.canCancel) unawaited(controller.cancel());
        },
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(awaiting ? '发现固件更新' : '固件更新'),
          content: SizedBox(
            width: 390,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (awaiting)
                    Text(widget.description, softWrap: true)
                  else
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
                              _cancelling ? '正在取消更新…' : controller.message,
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
            if (!installing && (_cancelling || !controller.terminal))
              _button(
                awaiting ? '取消' : '取消更新',
                !_cancelling && controller.canCancel
                    ? () => unawaited(_cancelAndClose())
                    : null,
              ),
            if (awaiting)
              _button('下载更新', () => controller.download(), primary: true),
            if (!_cancelling && step == FirmwareUpdateStep.prepared)
              _button('重启安装', () => controller.install(), primary: true),
            if (!_cancelling && (installing || controller.terminal))
              _button('关闭', () => Navigator.of(context).pop()),
          ],
        ),
      );
    },
  );

  Widget _button(String label, VoidCallback? action, {bool primary = false}) =>
      Opacity(
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
