import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/desktop_card_selection.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../domain/roleplay_card.dart';
import 'roleplay_card_controls.dart';

class RoleplayCardTransferDialog extends StatefulWidget {
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
  State<RoleplayCardTransferDialog> createState() =>
      _RoleplayCardTransferDialogState();
}

class _RoleplayCardTransferDialogState
    extends State<RoleplayCardTransferDialog> {
  final _selection = DesktopCardSelection();
  final _focus = FocusNode();
  late final _ids = widget.cards
      .map((card) => card.templateFingerprint)
      .toList();

  @override
  void initState() {
    super.initState();
    _selection.selectAll(_ids);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = widget.theme;
    final incoming = widget.incomingCount;
    final cards = widget.cards;
    final count = _selection.selected.length;
    return DesktopCardSelectionRegion(
      focusNode: _focus,
      selection: _selection,
      ids: _ids,
      onChanged: () => setState(() {}),
      onDelete: null,
      child: AppDialog(
        theme: theme,
        title: incoming == null
            ? l10n.aiRoleplayPackageExport
            : l10n.aiRoleplayImport,
        constraints: const BoxConstraints(maxWidth: 520),
        contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SizedBox(
            width: 468,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        incoming == null
                            ? l10n.aiRoleplayPackageSelectExport
                            : l10n.aiRoleplayPackageSummary(
                                incoming,
                                cards.length,
                                incoming - cards.length,
                              ),
                        style: AppDialogStyle.descriptionStyle(theme),
                      ),
                      if (widget.unreadableFiles > 0)
                        Text(
                          l10n.aiRoleplayImportSkippedFiles(
                            widget.unreadableFiles,
                          ),
                          style: AppDialogStyle.descriptionStyle(theme),
                        ),
                    ],
                  ),
                ),
                if (cards.isNotEmpty)
                  Flexible(
                    child: ScrollbarTheme(
                      data: ScrollbarTheme.of(context).copyWith(
                        crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                        mainAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 2,
                        ),
                        itemCount: cards.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _buildCard(cards[index]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          DesktopCardSelectionTarget(
            child: AppActionButton.dialog(
              theme: theme,
              label: cards.isEmpty ? l10n.close : l10n.settingsCancel,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (cards.isNotEmpty)
            DesktopCardSelectionTarget(
              child: AppActionButton.dialog(
                key: const ValueKey('roleplay-package-confirm'),
                theme: theme,
                primary: true,
                label: incoming == null
                    ? l10n.aiRoleplayPackageExportSelected(count)
                    : l10n.aiRoleplayPackageImportSelected(count),
                onPressed: count == 0
                    ? null
                    : () => Navigator.pop(context, [
                        for (final card in cards)
                          if (_selection.selected.contains(
                            card.templateFingerprint,
                          ))
                            card,
                      ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard(AiRoleplayCard card) {
    final theme = widget.theme;
    final id = card.templateFingerprint;
    final selected = _selection.selected.contains(id);
    final radius = BorderRadius.circular(12);
    return DesktopCardSelectionMenu(
      key: ValueKey('roleplay-package-card-$id'),
      id: id,
      theme: theme,
      child: Semantics(
        selected: selected,
        button: true,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 167),
          curve: Curves.fastOutSlowIn,
          decoration: BoxDecoration(
            color: theme.secondary,
            border: Border.all(
              color: selected ? theme.basePrimary : Colors.transparent,
            ),
            borderRadius: radius,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              onTap: () {
                final keyboard = HardwareKeyboard.instance;
                _focus.requestFocus();
                setState(
                  () => _selection.select(
                    id,
                    _ids,
                    control:
                        !keyboard.isShiftPressed ||
                        keyboard.isControlPressed ||
                        keyboard.isMetaPressed,
                    shift: keyboard.isShiftPressed,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: RoleplayCardInfo(card: card, theme: theme),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
