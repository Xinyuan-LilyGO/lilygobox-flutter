import '../../../../generated/l10n/app_localizations.dart';
import '../../domain/permissions.dart';

String aiPermissionCategoryLabel(
  AppLocalizations l10n,
  AiPermissionCategory category,
) => switch (category) {
  AiPermissionCategory.execution => l10n.aiPermissionExecution,
  AiPermissionCategory.fullFiles => l10n.aiPermissionFullFiles,
  AiPermissionCategory.network => l10n.aiPermissionNetwork,
};

String aiPermissionCategoryHelp(
  AppLocalizations l10n,
  AiPermissionCategory category,
) => switch (category) {
  AiPermissionCategory.execution => l10n.aiPermissionExecutionHelp,
  AiPermissionCategory.fullFiles => l10n.aiPermissionFullFilesHelp,
  AiPermissionCategory.network => l10n.aiPermissionNetworkHelp,
};
