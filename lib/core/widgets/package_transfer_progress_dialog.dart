import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../files/package_transfer.dart';
import '../l10n/language_provider.dart';
import '../theme/definition.dart';
import 'action_button.dart';
import 'confirmation_dialog.dart';

/// 仅在 [work] 执行期间显示进度，结束时只关闭当前对话框路由。
/// 具体操作负责响应取消，并在返回前完成清理。
Future<T> showTransferProgress<T>({
  required BuildContext context,
  required AppTheme theme,
  required Listenable progress,
  required PackageProgress? Function() readProgress,
  required VoidCallback onCancel,
  required Future<T> Function() work,
  VoidCallback? onCommit,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final showPageProgress = ValueNotifier(false);
  final route = DialogRoute<void>(
    context: context,
    barrierColor: onCommit == null ? Colors.black54 : Colors.transparent,
    barrierDismissible: true,
    barrierLabel: context.l10n.settingsCancel,
    builder: (context) {
      final dialog = PackageTransferProgressDialog(
        theme: theme,
        progress: progress,
        readProgress: readProgress,
        onCancel: onCancel,
      );
      if (onCommit == null) return dialog;
      return ValueListenableBuilder<bool>(
        valueListenable: showPageProgress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const IgnorePointer(child: ColoredBox(color: Colors.black54)),
            dialog,
          ],
        ),
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
    final progress = readProgress();
    if (progress?.stage != PackageStage.committing ||
        progress?.canCancel != false ||
        showPageProgress.value) {
      return;
    }
    showPageProgress.value = true;
    onCommit?.call();
  }

  if (onCommit != null) progress.addListener(switchToPageProgress);
  try {
    // 后台处理开始前，先让模态窗口注册监听器。
    await Future<void>.delayed(Duration.zero);
    return await work();
  } finally {
    if (onCommit != null) progress.removeListener(switchToPageProgress);
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

Future<T> showLibraryTransferProgress<T>({
  required BuildContext context,
  required AppTheme theme,
  required Future<T> Function(PackageTransfer) work,
}) async {
  final progress = ValueNotifier<PackageProgress>(
    const PackageProgress(.preparing),
  );
  final transfer = PackageTransfer(
    onProgress: (value) => progress.value = value,
  );
  try {
    return await showTransferProgress(
      context: context,
      theme: theme,
      progress: progress,
      readProgress: () => progress.value,
      onCancel: transfer.cancel,
      work: () async {
        try {
          transfer.check();
          return await work(transfer);
        } finally {
          transfer.finish();
        }
      },
    );
  } finally {
    progress.dispose();
  }
}

class PackageTransferProgressDialog extends StatefulWidget {
  const PackageTransferProgressDialog({
    super.key,
    required this.theme,
    required this.progress,
    required this.readProgress,
    required this.onCancel,
  });

  final AppTheme theme;
  final Listenable progress;
  final PackageProgress? Function() readProgress;
  final VoidCallback onCancel;

  @override
  State<PackageTransferProgressDialog> createState() =>
      _PackageTransferProgressDialogState();
}

class _PackageTransferProgressDialogState
    extends State<PackageTransferProgressDialog> {
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

  void _requestCancel() {
    if (_cancelling || widget.readProgress()?.canCancel == false) return;
    setState(() => _cancelling = true);
    widget.onCancel();
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
          : switch (progress?.stage ?? PackageStage.preparing) {
              .preparing => l.agentStorageTransferPreparing,
              .reading => l.agentStorageTransferReading,
              .compressing => l.agentStorageTransferCompressing,
              .decompressing => l.agentStorageTransferDecompressing,
              .verifying => l.agentStorageTransferVerifying,
              .checksumming => l.agentStorageTransferChecksumming,
              .analyzing => l.agentStorageTransferAnalyzing,
              .writing => l.agentStorageTransferWriting,
              .committing => l.agentStorageTransferCommitting,
            };
      final seconds = _elapsed.elapsed.inSeconds;
      final duration =
          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
      return PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestCancel();
        },
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
                  : _requestCancel,
            ),
          ],
        ),
      );
    },
  );
}
