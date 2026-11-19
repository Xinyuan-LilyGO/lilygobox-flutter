import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../domain/agent_package_progress.dart';
import '../../state/storage_controller.dart';

/// 仅在 [work] 执行期间显示进度，结束时只关闭当前对话框路由。
/// 具体操作负责响应取消，并在返回前完成清理。
Future<T> showAgentTransferProgress<T>({
  required BuildContext context,
  required AppTheme theme,
  required AgentStorageController controller,
  required Future<T> Function() work,
  VoidCallback? onCommit,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final showPageProgress = ValueNotifier(false);
  final route = DialogRoute<void>(
    context: context,
    barrierColor: onCommit == null ? Colors.black54 : Colors.transparent,
    barrierDismissible: false,
    builder: (context) {
      final dialog = AgentTransferProgressDialog(
        theme: theme,
        progress: controller,
        readProgress: () => controller.transferProgress,
        onCancel: controller.cancelTransfer,
      );
      if (onCommit == null) return dialog;
      return ValueListenableBuilder<bool>(
        valueListenable: showPageProgress,
        child: ColoredBox(color: Colors.black54, child: dialog),
        builder: (context, committed, child) => committed
            ? PopScope(
                canPop: false,
                child: Semantics(
                  label: context.l10n.agentStorageTransferCommitting,
                  liveRegion: true,
                  child: const SizedBox.expand(),
                ),
              )
            : child!,
      );
    },
  );
  final closed = navigator.push(route);
  void switchToPageProgress() {
    final progress = controller.transferProgress;
    if (progress?.stage != AgentPackageStage.committing ||
        progress?.canCancel != false ||
        showPageProgress.value) {
      return;
    }
    showPageProgress.value = true;
    onCommit?.call();
  }

  if (onCommit != null) controller.addListener(switchToPageProgress);
  try {
    // 后台处理开始前，先让模态窗口注册监听器。
    await Future<void>.delayed(Duration.zero);
    return await controller.runTransfer(work);
  } finally {
    if (onCommit != null) controller.removeListener(switchToPageProgress);
    if (route.isActive && navigator.mounted) {
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    }
    await closed;
    await route.completed;
    showPageProgress.dispose();
  }
}

class AgentTransferProgressDialog extends StatefulWidget {
  const AgentTransferProgressDialog({
    super.key,
    required this.theme,
    required this.progress,
    required this.readProgress,
    required this.onCancel,
  });

  final AppTheme theme;
  final Listenable progress;
  final AgentPackageProgress? Function() readProgress;
  final VoidCallback onCancel;

  @override
  State<AgentTransferProgressDialog> createState() =>
      _AgentTransferProgressDialogState();
}

class _AgentTransferProgressDialogState
    extends State<AgentTransferProgressDialog> {
  final _elapsed = Stopwatch()..start();
  Timer? _timer;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.progress,
    builder: (context, _) {
      final l = context.l10n;
      final theme = widget.theme;
      final progress = widget.readProgress();
      final fraction = progress?.fraction;
      final stage = _cancelling
          ? l.agentStorageTransferCancelling
          : switch (progress?.stage ?? AgentPackageStage.preparing) {
              AgentPackageStage.preparing => l.agentStorageTransferPreparing,
              AgentPackageStage.reading => l.agentStorageTransferReading,
              AgentPackageStage.compressing =>
                l.agentStorageTransferCompressing,
              AgentPackageStage.decompressing =>
                l.agentStorageTransferDecompressing,
              AgentPackageStage.verifying => l.agentStorageTransferVerifying,
              AgentPackageStage.checksumming =>
                l.agentStorageTransferChecksumming,
              AgentPackageStage.analyzing => l.agentStorageTransferAnalyzing,
              AgentPackageStage.writing => l.agentStorageTransferWriting,
              AgentPackageStage.committing => l.agentStorageTransferCommitting,
            };
      final seconds = _elapsed.elapsed.inSeconds;
      final duration =
          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
      return PopScope(
        canPop: false,
        child: AppDialog(
          key: const ValueKey('storage-transfer-progress-dialog'),
          constraints: const BoxConstraints(maxWidth: 400),
          theme: theme,
          title: l.agentStorageTransferTitle,
          content: SizedBox(
            width: 352,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    stage,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.textColorSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  key: const ValueKey('storage-transfer-progress-bar'),
                  value: fraction,
                  backgroundColor: theme.dividerColor,
                  semanticsLabel: stage,
                  semanticsValue: fraction == null
                      ? null
                      : '${(fraction * 100).floor()}%',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.agentStorageTransferElapsed(duration),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textColorTertiary,
                        ),
                      ),
                    ),
                    if (fraction != null)
                      Text(
                        '${(fraction * 100).floor()}%',
                        key: const ValueKey('storage-transfer-percentage'),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textColorSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            AppActionButton.dialog(
              key: const ValueKey('storage-transfer-cancel'),
              theme: theme,
              label: l.settingsCancel,
              onPressed: _cancelling || !(progress?.canCancel ?? true)
                  ? null
                  : () {
                      setState(() => _cancelling = true);
                      widget.onCancel();
                    },
            ),
          ],
        ),
      );
    },
  );
}
