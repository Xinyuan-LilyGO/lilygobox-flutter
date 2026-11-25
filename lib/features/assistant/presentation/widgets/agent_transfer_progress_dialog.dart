import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/package_transfer_progress_dialog.dart';
import '../../state/storage_controller.dart';

typedef AgentTransferProgressDialog = PackageTransferProgressDialog;

Future<T> showAgentTransferProgress<T>({
  required BuildContext context,
  required AppTheme theme,
  required AgentStorageController controller,
  required Future<T> Function() work,
  VoidCallback? onCommit,
}) => showTransferProgress(
  context: context,
  theme: theme,
  progress: controller,
  readProgress: () => controller.transferProgress,
  onCancel: controller.cancelTransfer,
  work: () => controller.runTransfer(work),
  onCommit: onCommit,
);
