import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../core/files/export_file_name.dart';
import '../../../../core/files/package_transfer.dart';
import '../../../../core/files/zstd_file.dart';
import '../../../../core/files/zstd_tar.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/desktop_card_selection.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../../../core/widgets/library_delete_dialog.dart';
import '../../../../core/widgets/package_transfer_progress_dialog.dart';
import '../../../settings/presentation/widgets/content_layout.dart';
import '../../data/roleplay_card_package.dart';
import '../../domain/roleplay_card.dart';
import '../../state/agent_workspace_provider.dart';
import 'roleplay_card_controls.dart';
import 'roleplay_card_transfer_dialog.dart';

class RoleplayLibraryContent extends StatefulWidget {
  const RoleplayLibraryContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<RoleplayLibraryContent> createState() => _RoleplayLibraryContentState();
}

class _RoleplayLibraryContentState extends State<RoleplayLibraryContent> {
  final _selection = DesktopCardSelection();
  final _selectionFocus = FocusNode();
  bool _transferring = false;

  AppTheme get theme => widget.theme;

  @override
  void dispose() {
    _selectionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaces = context.watch<AiWorkspaceProvider>();
    final l10n = context.l10n;
    final available = !workspaces.isRestoring && !workspaces.restoreFailed;
    final usage = available ? workspaces.roleplayLibraryUsage : null;
    final cards = available
        ? workspaces.roleplayTemplates
              .map((binding) => binding.sourceCard)
              .toList()
        : const <AiRoleplayCard>[];
    final ids = cards.map((card) => card.templateFingerprint).toList();
    _selection.retain(ids);
    void deleteSelected() => unawaited(
      _confirmDelete(
        context,
        workspaces,
        cards
            .where(
              (card) => _selection.selected.contains(card.templateFingerprint),
            )
            .toList(),
        batch: true,
      ),
    );
    final header = SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsContentHeader(
            theme: theme,
            title: l10n.aiRoleplayLibraryTitle,
            description: l10n.aiRoleplayLibraryDescription,
          ),
          if (available) ...[
            DesktopCardSelectionTarget(
              child: SettingsSection(
                theme: theme,
                title: l10n.aiRoleplayPackageTitle,
                description: l10n.aiRoleplayPackageDescription,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppActionButton.settings(
                      key: const ValueKey('roleplay-library-export'),
                      theme: theme,
                      label: l10n.aiRoleplayPackageExport,
                      onPressed: _transferring || cards.isEmpty
                          ? null
                          : () => unawaited(_exportPackage(context, cards)),
                    ),
                    AppActionButton.settings(
                      key: const ValueKey('roleplay-library-import'),
                      theme: theme,
                      label: l10n.aiRoleplayConfirmImport,
                      onPressed: _transferring
                          ? null
                          : () => unawaited(_importCards(context, workspaces)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            DesktopCardSelectionTarget(
              child: SettingsCollectionHeader(
                theme: theme,
                title: l10n.aiRoleplayLibraryAddedTitle,
                description: l10n.aiRoleplayLibraryAddedDescription,
                extraAction: Visibility(
                  visible: _selection.selected.isNotEmpty,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: AppActionButton.compact(
                    key: _selection.selected.isEmpty
                        ? null
                        : const ValueKey('roleplay-library-delete-selected'),
                    theme: theme,
                    label: l10n.settingsDeleteSelected(
                      _selection.selected.length,
                    ),
                    destructive: true,
                    onPressed: _selection.selected.isEmpty
                        ? null
                        : deleteSelected,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (cards.isEmpty)
            Text(
              workspaces.isRestoring
                  ? l10n.aiTopologyLoading
                  : available
                  ? l10n.aiRoleplayLibraryEmpty
                  : l10n.aiRoleplayLibraryUnavailable,
              style: AppDialogStyle.descriptionStyle(theme),
            ),
        ],
      ),
    );
    return DesktopCardSelectionRegion(
      focusNode: _selectionFocus,
      selection: _selection,
      ids: ids,
      enabled: available,
      onChanged: () => setState(() {}),
      onDelete: available ? deleteSelected : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const pagePadding = SettingsContentLayout.pagePadding;
          final sidePadding =
              ((constraints.maxWidth - SettingsContentLayout.contentWidth) / 2)
                  .clamp(pagePadding.left, double.infinity);
          final padding = pagePadding.copyWith(
            left: sidePadding,
            right: sidePadding,
          );
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: cards.isEmpty ? padding : padding.copyWith(bottom: 0),
                sliver: header,
              ),
              if (cards.isNotEmpty)
                SliverPadding(
                  padding: padding.copyWith(top: 0),
                  sliver: SliverList.builder(
                    itemCount: cards.length,
                    findChildIndexCallback: (key) {
                      final index = ids.indexOf(
                        (key as ValueKey<String>).value,
                      );
                      return index < 0 ? null : index;
                    },
                    itemBuilder: (_, index) => _buildCard(
                      context,
                      workspaces,
                      cards[index],
                      usage?[ids[index]]?.length ?? 0,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _importCards(
    BuildContext context,
    AiWorkspaceProvider workspaces,
  ) async {
    if (_transferring) return;
    final l10n = context.l10n;
    setState(() => _transferring = true);
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          XTypeGroup(
            label: l10n.aiRoleplayFileType,
            extensions: const ['png', 'json', ZstdFile.extension],
            mimeTypes: const [
              'image/png',
              'application/json',
              ZstdFile.mimeType,
            ],
            uniformTypeIdentifiers: const [
              'public.png',
              'public.json',
              ZstdFile.uniformTypeIdentifier,
            ],
          ),
        ],
      );
      if (files.isEmpty || !context.mounted) return;
      final incoming = await showLibraryTransferProgress(
        context: context,
        theme: theme,
        work: (transfer) =>
            RoleplayCardPackage.readSources(files, transfer: transfer),
      );
      if (!context.mounted) return;
      if (incoming.cards.isEmpty) {
        _notice(context, l10n.aiRoleplayImportFailed);
        return;
      }
      final List<AiRoleplayCard>? selected;
      if (incoming.singleCardFile) {
        final confirmed = await confirmRoleplayCardImport(
          context,
          theme,
          incoming.cards.single,
        );
        selected = confirmed == true ? incoming.cards : null;
      } else {
        selected = await _selectCards(
          context,
          workspaces.newRoleplayCards(incoming.cards),
          incomingCount: incoming.cards.length,
          unreadableFiles: incoming.unreadableFiles,
        );
      }
      if (selected == null || !context.mounted) return;
      final added = workspaces.addRoleplayTemplates([
        for (final card in selected)
          AiRoleplayBinding.libraryTemplate(card, l10n.aiRoleplayPlayer),
      ]);
      await workspaces.flush();
      if (context.mounted && !incoming.singleCardFile) {
        _notice(context, l10n.aiRoleplayPackageImported(added));
      }
    } on PackageCancelled {
      if (context.mounted) _notice(context, l10n.agentStorageTransferCancelled);
    } catch (_) {
      if (context.mounted) _notice(context, l10n.aiRoleplayImportFailed);
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _exportPackage(
    BuildContext context,
    List<AiRoleplayCard> cards,
  ) async {
    if (_transferring) return;
    final l10n = context.l10n;
    setState(() => _transferring = true);
    try {
      final selected = await _selectCards(context, cards);
      if (selected == null || !context.mounted) return;
      final destination = await getSaveLocation(
        suggestedName: datedExportFileName(
          RoleplayCardPackage.fileName,
          suffix: ZstdTar.suffix,
        ),
        acceptedTypeGroups: [
          ZstdFile.typeGroup(l10n.aiRoleplayPackageFileType),
        ],
      );
      if (destination == null || !context.mounted) return;
      await showLibraryTransferProgress(
        context: context,
        theme: theme,
        work: (transfer) => RoleplayCardPackage.write(
          destination.path,
          selected,
          transfer: transfer,
        ),
      );
      if (context.mounted) {
        _notice(context, l10n.aiRoleplayPackageExported(selected.length));
      }
    } on PackageCancelled {
      if (context.mounted) _notice(context, l10n.agentStorageTransferCancelled);
    } catch (_) {
      if (context.mounted) _notice(context, l10n.aiRoleplayPackageExportFailed);
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<List<AiRoleplayCard>?> _selectCards(
    BuildContext context,
    List<AiRoleplayCard> cards, {
    int? incomingCount,
    int unreadableFiles = 0,
  }) => showDialog<List<AiRoleplayCard>>(
    context: context,
    builder: (context) => RoleplayCardTransferDialog(
      theme: theme,
      cards: cards,
      incomingCount: incomingCount,
      unreadableFiles: unreadableFiles,
    ),
  );

  void _notice(BuildContext context, String message) =>
      showAppNotice(ScaffoldMessenger.of(context), message);

  Widget _buildCard(
    BuildContext context,
    AiWorkspaceProvider workspaces,
    AiRoleplayCard card,
    int boundCount,
  ) {
    final l10n = context.l10n;
    final fingerprint = card.templateFingerprint;
    final details = RoleplayCardInfo(
      card: card,
      theme: theme,
      subtitle: l10n.aiRoleplayLibraryBoundCount(boundCount),
    );
    final actions = [
      AppActionButton(
        key: ValueKey('roleplay-library-details-$fingerprint'),
        theme: theme,
        label: l10n.aiRoleplayLibraryViewDetails,
        onPressed: () => unawaited(_view(context, card)),
      ),
      AppActionButton(
        key: ValueKey('roleplay-library-delete-$fingerprint'),
        theme: theme,
        label: l10n.delete,
        destructive: true,
        icon: Symbols.delete_outline_rounded,
        iconSize: 16,
        iconSpacing: 6,
        fontSize: 12,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        onPressed: () => unawaited(_confirmDelete(context, workspaces, [card])),
      ),
    ];
    return Padding(
      key: ValueKey(fingerprint),
      padding: const EdgeInsets.only(bottom: 8),
      child: DesktopSelectableCard(
        id: fingerprint,
        theme: theme,
        child: SettingsLibraryCard(
          key: ValueKey('roleplay-library-card-$fingerprint'),
          theme: theme,
          details: details,
          actions: actions,
        ),
      ),
    );
  }

  Future<void> _view(BuildContext context, AiRoleplayCard card) {
    final l10n = context.l10n;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        theme: theme,
        title: l10n.aiRoleplayCard,
        constraints: const BoxConstraints(maxWidth: 480),
        content: SingleChildScrollView(
          child: RoleplayCardDetails(card: card, theme: theme),
        ),
        actions: [
          AppActionButton.dialog(
            theme: theme,
            label: l10n.close,
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AiWorkspaceProvider workspaces,
    List<AiRoleplayCard> cards, {
    bool batch = false,
  }) async {
    if (cards.isEmpty) return;
    final l10n = context.l10n;
    final usage = workspaces.roleplayLibraryUsage;
    final confirmedUsage = {
      for (final card in cards)
        card.templateFingerprint:
            usage[card.templateFingerprint] ?? const <AiRoleplayLibraryAgent>[],
    };
    final affected = confirmedUsage.values.expand((agents) => agents).toList();
    final busy = affected.where((agent) => agent.busy).toList();
    if (busy.isNotEmpty) {
      await _showBusy(context, busy);
      return;
    }
    final confirmed = await _showDeleteDialog(
      context,
      title: batch
          ? l10n.settingsDeleteSelected(cards.length)
          : affected.isEmpty
          ? l10n.aiRoleplayLibraryDeleteTitle(cards.single.name)
          : l10n.aiRoleplayLibraryDeleteBoundTitle(
              cards.single.name,
              affected.length,
            ),
      description: affected.isEmpty
          ? l10n.aiRoleplayLibraryDeleteWarning
          : l10n.aiRoleplayLibraryDeleteBoundWarning,
      cards: batch ? cards : const [],
      agents: affected,
      confirmLabel: affected.isEmpty
          ? l10n.aiRoleplayLibraryDelete
          : l10n.aiRoleplayLibraryDeleteAndUnbind,
    );
    if (!context.mounted || confirmed != true) return;
    final result = workspaces.deleteRoleplayTemplates(confirmedUsage);
    switch (result) {
      case AiRoleplayLibraryDeleteResult.deleted:
        return;
      case AiRoleplayLibraryDeleteResult.busy:
        final currentUsage = workspaces.roleplayLibraryUsage;
        await _showBusy(
          context,
          confirmedUsage.keys
              .expand(
                (id) => currentUsage[id] ?? const <AiRoleplayLibraryAgent>[],
              )
              .where((agent) => agent.busy),
        );
      case AiRoleplayLibraryDeleteResult.changed:
      case AiRoleplayLibraryDeleteResult.unavailable:
        await _showDeleteDialog(
          context,
          title: l10n.aiRoleplayLibraryTitle,
          description: result == AiRoleplayLibraryDeleteResult.changed
              ? l10n.aiRoleplayLibraryChanged
              : l10n.aiRoleplayLibraryUnavailable,
        );
    }
  }

  Future<bool?> _showBusy(
    BuildContext context,
    Iterable<AiRoleplayLibraryAgent> agents,
  ) => _showDeleteDialog(
    context,
    title: context.l10n.aiRoleplayLibraryBusyTitle,
    description: context.l10n.aiRoleplayLibraryBusyDetail,
    agents: agents,
  );

  Future<bool?> _showDeleteDialog(
    BuildContext context, {
    required String title,
    required String description,
    List<AiRoleplayCard> cards = const [],
    Iterable<AiRoleplayLibraryAgent> agents = const [],
    String? confirmLabel,
  }) => showLibraryDeleteDialog(
    context: context,
    theme: theme,
    actionKey: 'roleplay-library-delete',
    title: title,
    description: description,
    confirmLabel: confirmLabel,
    items: cards.isEmpty
        ? null
        : (
            title: context.l10n.aiRoleplayLibraryCardsToDelete(cards.length),
            names: [for (final card in cards) card.name],
          ),
    agents: [
      for (final agent in agents)
        (id: agent.id, title: agent.title, recycled: agent.recycled),
    ],
  );
}
