import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/card_transfer_dialog.dart';
import '../../domain/roleplay_card.dart';
import 'roleplay_card_controls.dart';

class RoleplayCardTransferDialog extends StatelessWidget {
  const RoleplayCardTransferDialog({
    super.key,
    required this.theme,
    required this.cards,
    this.incomingCount,
    this.unreadableFiles = 0,
  });

  final AppTheme theme;
  final List<AiRoleplayCard> cards;
  final int? incomingCount;
  final int unreadableFiles;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final incoming = incomingCount;
    return CardTransferDialog<AiRoleplayCard>(
      theme: theme,
      title: incoming == null
          ? l10n.aiRoleplayPackageExport
          : l10n.aiRoleplayImport,
      description: incoming == null
          ? l10n.aiRoleplayPackageSelectExport
          : l10n.aiRoleplayPackageSummary(
              incoming,
              cards.length,
              incoming - cards.length,
            ),
      secondaryDescription: unreadableFiles > 0
          ? l10n.aiRoleplayImportSkippedFiles(unreadableFiles)
          : null,
      items: cards,
      idOf: (card) => card.templateFingerprint,
      buildInfo: (card) => RoleplayCardInfo(card: card, theme: theme),
      confirmLabel: incoming == null
          ? l10n.aiRoleplayPackageExportSelected
          : l10n.aiRoleplayPackageImportSelected,
      keyPrefix: 'roleplay-package',
    );
  }
}
