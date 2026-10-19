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
      _finishCheck(error: '设备已断开或已切换，请重新连接后检查更新');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 45), () {
      _finishCheck(error: '检查更新超时，请检查网络后重试');
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
              ? _checkErrorText(widget.connection.firmwareUpdateError!)
              : null);
      if (_error == null && release != null) _setRelease(release);
    });
  }

  String _checkErrorText(Object error) {
    final text = error.toString();
    if (text.contains('HTTP 404')) {
      return '没有找到当前设备对应的 OTA 清单（HTTP 404）';
    }
    if (text.contains('timed out') || text.contains('TimeoutException')) {
      return 'OTA 清单请求超时，请检查网络后重试';
    }
    if (text.contains('invalid or incompatible')) {
      return '当前设备型号、硬件版本或芯片与 OTA 清单不匹配';
    }
    if (text.contains('network request failed')) {
      return 'OTA 清单网络请求失败，请检查网络后重试';
    }
    return '检查更新失败：$text';
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
    unawaited(_controller!.prepareCache());
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
                ? '发现固件更新'
                : controller.observer
                ? '设备固件更新'
                : '固件更新',
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
                          ? '设备联网更新 · 关闭窗口不影响设备当前任务'
                          : '局域网更新 · 由发起更新的应用提供固件',
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (awaiting) ...[
                    Text(widget.description, softWrap: true),
                    if (controller.deviceCacheAvailable) ...[
                      const SizedBox(height: 16),
                      const Text('设备已有本次更新所需的完整固件，可重新校验后直接准备安装。'),
                    ],
                    if (!controller.deviceCacheAvailable &&
                        controller.cacheChecking) ...[
                      const SizedBox(height: 16),
                      const Text('正在校验本机已下载的固件…'),
                    ] else if (!controller.deviceCacheAvailable &&
                        controller.hasCache) ...[
                      const SizedBox(height: 16),
                      Text(
                        '已下载并校验：${[if (controller.mainCached) '主固件', if (controller.wirelessCached) '无线固件'].join('、')}。可直接使用，缺少的组件会继续下载。',
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
            if (step == FirmwareUpdateStep.failed && widget.onRetry != null)
              _button('重试', widget.onRetry, primary: true),
            if (controller.observer && !controller.terminal && !installing)
              _button('关闭', () => Navigator.of(context).pop()),
            if (!installing &&
                (_cancelling || !controller.terminal) &&
                controller.canCancel)
              _button(
                awaiting ? '取消' : '取消更新',
                !_cancelling && controller.canCancel
                    ? () => unawaited(_cancelAndClose())
                    : null,
              ),
            if (awaiting &&
                (controller.hasCache || controller.deviceCacheAvailable))
              _button('重新下载', () => controller.download(reuseCache: false)),
            if (awaiting)
              _button(
                controller.deviceCacheAvailable
                    ? '使用设备已有固件'
                    : controller.hasCache
                    ? '使用已下载固件'
                    : '下载更新',
                controller.cacheChecking
                    ? null
                    : controller.deviceCacheAvailable
                    ? () => controller.useDeviceCache()
                    : () => controller.download(),
                primary: true,
              ),
            if (!_cancelling &&
                step == FirmwareUpdateStep.prepared &&
                controller.canControl)
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
