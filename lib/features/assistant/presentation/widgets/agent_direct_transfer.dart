import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../core/files/zstd_file.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../domain/agent_package_progress.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/storage_controller.dart';
import 'agent_transfer_error.dart';
import 'agent_transfer_progress_dialog.dart';
import 'memory_import_review.dart';

final _activeDirectTransfers = <AiWorkspaceProvider>{};

/// 卡片和画布快捷入口已经确定操作类型与目标。
/// 仅保留文件选择、记忆检查和实际传输进度。
Future<void> runDirectAgentTransfer(
  BuildContext context,
  AppTheme theme,
  String owner,
  String action, {
  Set<String>? selectedIds,
  ValueChanged<bool>? onImportCommitting,
}) async {
  final workspaces = context.read<AiWorkspaceProvider>();
  if (!_activeDirectTransfers.add(workspaces)) return;
  final controller = AgentStorageController(workspaces)..owner = owner;
  final importing = action == 'import' || action == 'import-agents';
  final l = context.l10n;

  Future<T> transfer<T>(Future<T> Function() work, {VoidCallback? onCommit}) =>
      showAgentTransferProgress<T>(
        context: context,
        theme: theme,
        controller: controller,
        work: work,
        onCommit: onCommit,
      );

  void notice(String message) {
    if (context.mounted) {
      showAppNotice(ScaffoldMessenger.of(context), message);
    }
  }

  try {
    while (context.mounted) {
      try {
        if (importing) {
          final file = await openFile(
            acceptedTypeGroups: [ZstdFile.typeGroup(l.agentStoragePackageType)],
          );
          if (file == null || !context.mounted) return;
          try {
            final completed = await transfer(
              () async {
                var package = await controller.inspect(file.path);
                if (!context.mounted) return false;
                final type = package['type'] as String;
                final validType = action == 'import'
                    ? type == 'memory'
                    : {'agent', 'workflow', 'chat', 'memory'}.contains(type);
                if (!validType) {
                  throw const _UnexpectedPackageKind();
                }
                final createsMemoryAgent =
                    type == 'memory' && action == 'import-agents';
                if (type == 'memory' &&
                    !createsMemoryAgent &&
                    workspaces.find(owner) == null) {
                  throw const _UnexpectedPackageKind();
                }
                if (createsMemoryAgent) {
                  package = controller.memoryPackageForNewAgent(
                    package,
                    title: l.agentStorageImportedMemoryAgent,
                  );
                }
                final plan = await controller.plan(package);
                if (!context.mounted) return false;
                if (package['type'] == 'memory' &&
                    plan.isNotEmpty &&
                    !await reviewMemoryImport(context, theme, plan)) {
                  return false;
                }
                if (!context.mounted) return false;
                await controller.import(package, plan: plan);
                return true;
              },
              onCommit: onImportCommitting == null
                  ? null
                  : () => onImportCommitting(true),
            );
            if (!completed) return;
          } finally {
            onImportCommitting?.call(false);
          }
          notice(l.agentStorageImportSuccess);
        } else {
          final destination = await getSaveLocation(
            suggestedName: controller.suggestedExportName(action),
            acceptedTypeGroups: [ZstdFile.typeGroup(l.agentStoragePackageType)],
          );
          if (destination == null || !context.mounted) return;
          await transfer(
            () => controller.export(
              destination.path,
              action,
              selectedIds: selectedIds,
            ),
          );
          notice(l.agentStorageExportSuccess);
        }
        return;
      } on AgentPackageCancelled {
        notice(l.agentStorageTransferCancelled);
        return;
      } catch (error) {
        if (!context.mounted) return;
        final message = error is _UnexpectedPackageKind
            ? l.agentStorageImportInvalidKind
            : agentTransferFailureMessage(context, error);
        notice(message);
        final retry = await showAppConfirmation(
          context: context,
          theme: theme,
          constraints: const BoxConstraints(maxWidth: 440),
          actionKey: 'storage-transfer-retry',
          title: l.agentStorageTransferFailedTitle,
          description: message,
          confirmLabel: importing
              ? l.agentStorageChoosePackage
              : l.agentStorageExportTab,
        );
        if (!retry || !context.mounted) return;
      }
    }
  } finally {
    controller.dispose();
    _activeDirectTransfers.remove(workspaces);
  }
}

class _UnexpectedPackageKind implements Exception {
  const _UnexpectedPackageKind();
}
