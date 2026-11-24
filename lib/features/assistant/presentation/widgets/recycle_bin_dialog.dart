import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../../../core/context_menu/right_click_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/desktop_card_selection.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../../../core/widgets/settings/search_field.dart';
import '../../../../core/widgets/settings/select.dart';
import '../../state/agent_workspace_provider.dart';

Future<void> showAgentRecycleBin(BuildContext context, AppTheme theme) async {
  final workspace = context.read<AiWorkspaceProvider>();
  Future<void>? pendingOperation;
  await showDialog<void>(
    context: context,
    builder: (_) => _RecycleBin(
      theme: theme,
      onOperation: (operation) => pendingOperation = operation,
    ),
  );
  await pendingOperation;
  if (workspace.pendingRecycleRestore case final restore?) await restore;
}

class _RecycleBin extends StatefulWidget {
  const _RecycleBin({required this.theme, required this.onOperation});
  final AppTheme theme;
  final ValueChanged<Future<void>> onOperation;
  @override
  State<_RecycleBin> createState() => _RecycleBinState();
}

class _RecycleBinState extends State<_RecycleBin> {
  final search = TextEditingController();
  final searchFieldKey = GlobalKey();
  final selection = DesktopCardSelection();
  final selectionFocus = FocusNode(debugLabel: 'recycle-card-selection');
  List<AiRecycledAgent>? _sourceEntries;
  List<AiRecycledAgent> _filteredEntries = const [];
  List<String> _visibleIds = const [];
  String? _query;
  Object? _cardEnvironment;
  final _cardViews = DesktopCardViewCache();
  bool busy = false;
  Object? error;
  @override
  void dispose() {
    search.dispose();
    selectionFocus.dispose();
    super.dispose();
  }

  Future<void> run(
    Future<void> Function() action, {
    String? failureMessage,
  }) {
    if (busy) return Future.value();
    final pending = _run(action, failureMessage);
    widget.onOperation(pending);
    return pending;
  }

  Future<void> _run(
    Future<void> Function() action,
    String? failureMessage,
  ) async {
    final route = ModalRoute.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final notice = failureMessage ?? context.l10n.agentStorageFailure;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted && route?.isCurrent == true) {
        setState(() => error = failureMessage ?? e);
      } else {
        showAppNotice(messenger, notice);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> delete(
    AiWorkspaceProvider workspace,
    Iterable<String> ids,
  ) async {
    final deleting = ids.toSet();
    if (busy || workspace.recycleBusy || deleting.isEmpty) return;
    final l = context.l10n;
    if (await showAppConfirmation(
          constraints: const BoxConstraints(maxWidth: 440),
          context: context,
          theme: widget.theme,
          actionKey: 'recycle-delete',
          destructive: true,
          title: l.agentRecycleDelete,
          description: deleting.length > 1
              ? l.agentRecycleDeleteSelectedHint(deleting.length)
              : l.agentRecycleDeleteHint,
          confirmLabel: l.agentRecycleDelete,
        ) &&
        mounted) {
      await run(() async {
        await workspace.permanentlyDeleteRecycledAgents(deleting);
        selection.retain(workspace.recycledAgents.map((entry) => entry.id));
      });
    }
  }

  Future<void> restore(
    AiWorkspaceProvider workspace,
    Set<String> ids, {
    bool all = false,
  }) async {
    if (busy || workspace.recycleBusy || ids.isEmpty) return;
    final l = context.l10n;
    if (all) {
      final confirmed = await showAppConfirmation(
        context: context,
        theme: widget.theme,
        actionKey: 'recycle-restore',
        title: l.agentRecycleRestoreAll,
        description: l.agentRecycleRestoreAllConfirm(ids.length),
        confirmLabel: l.agentRecycleRestoreAll,
      );
      if (!confirmed || !mounted || workspace.recycleBusy) return;
    }
    await run(
      () => workspace.restoreRecycledAgents(ids),
      failureMessage: l.agentRecycleRestoreFailed,
    );
  }

  Future<void> empty(AiWorkspaceProvider workspace) async {
    final l = context.l10n;
    if (await showAppConfirmation(
          constraints: const BoxConstraints(maxWidth: 440),
          context: context,
          theme: widget.theme,
          actionKey: 'recycle-empty',
          destructive: true,
          title: l.agentRecycleEmptyAction,
          description: l.agentRecycleDeleteHint,
          confirmLabel: l.agentRecycleEmptyAction,
        ) &&
        mounted) {
      await run(
        () => workspace.permanentlyDeleteRecycledAgents(
          workspace.recycledAgents.map((e) => e.id),
        ),
      );
    }
  }

  String remainingTime(DateTime? expiry) {
    final l = context.l10n;
    if (expiry == null) return l.agentRecycleNever;
    final remaining = expiry.difference(DateTime.now());
    if (remaining <= Duration.zero) return l.agentRecyclePendingDeletion;
    if (remaining.inHours >= 24) {
      return l.agentRecycleRemainingDays((remaining.inHours / 24).ceil());
    }
    if (remaining.inMinutes >= 60) {
      return l.agentRecycleRemainingHours((remaining.inMinutes / 60).ceil());
    }
    return l.agentRecycleRemainingMinutes(
      (remaining.inSeconds / 60).ceil().clamp(1, 60),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.read<AiWorkspaceProvider>();
    final snapshot = context
        .select<
          AiWorkspaceProvider,
          ({List<AiRecycledAgent> entries, bool busy, int retention})
        >(
          (value) => (
            entries: value.recycledAgents,
            busy: value.recycleBusy,
            retention: value.recycleRetentionDays,
          ),
        );
    final theme = widget.theme;
    final cardSurface = theme.secondary;
    final restoreBackground = theme
        .buttonColorsForSurface(cardSurface)
        .background;
    final l = context.l10n;
    final disabled = busy || snapshot.busy;
    final query = search.text.trim().toLowerCase();
    final sourceChanged = !identical(_sourceEntries, snapshot.entries);
    if (sourceChanged) {
      selection.retain(snapshot.entries.map((entry) => entry.id));
      _cardViews.clear();
    }
    if (sourceChanged || _query != query) {
      _sourceEntries = snapshot.entries;
      _query = query;
      _filteredEntries = query.isEmpty
          ? snapshot.entries
          : snapshot.entries
                .where(
                  (e) => '${e.title} ${e.id}'.toLowerCase().contains(query),
                )
                .toList();
      _visibleIds = _filteredEntries.map((entry) => entry.id).toList();
    }
    final entries = _filteredEntries;
    final environment = (
      theme,
      l,
      disabled,
      snapshot.retention,
      DateTime.now().millisecondsSinceEpoch ~/ 60000,
    );
    if (_cardEnvironment != environment) {
      _cardEnvironment = environment;
      _cardViews.clear();
    }
    final viewport = MediaQuery.sizeOf(context);
    final compact =
        viewport.height < 700 ||
        (viewport.width < 500 &&
            MediaQuery.textScalerOf(context).scale(14) > 16);
    const contentInset = EdgeInsets.symmetric(horizontal: 24);
    Widget fitContent(
      List<Widget> header, {
      required Widget list,
      Widget? footer,
    }) {
      final paddedHeader = Padding(
        padding: contentInset,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: header,
        ),
      );
      final paddedFooter = footer == null
          ? null
          : Padding(padding: contentInset, child: footer);
      return compact
          ? DesktopCardSelectionTarget(
              child: CustomScrollView(
                key: const ValueKey('recycle-agent-compact-scroll'),
                shrinkWrap: true,
                slivers: [
                  SliverToBoxAdapter(child: paddedHeader),
                  list,
                  if (paddedFooter != null)
                    SliverToBoxAdapter(child: paddedFooter),
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [paddedHeader, list, ?paddedFooter],
            );
    }

    Widget fitList(SuperListView list) => compact
        ? SliverPadding(
            padding: list.padding ?? EdgeInsets.zero,
            sliver: SuperSliverList(delegate: list.childrenDelegate),
          )
        : Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (viewport.height * .30).clamp(100.0, 300.0),
              ),
              child: list,
            ),
          );
    const dialogWidth = 440.0;
    final searchField = DesktopCardSelectionTarget(
      child: SettingSearchField(
        key: searchFieldKey,
        theme: theme,
        controller: search,
        hintText: l.agentRecycleSearch,
        onChanged: (_) => setState(() {}),
        onClear: () => setState(search.clear),
      ),
    );
    final batchActions = DesktopCardSelectionTarget(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppActionButton.compact(
            key: const ValueKey('recycle-restore-selected'),
            theme: theme,
            label: '${l.agentRecycleRestore} (${selection.selected.length})',
            onPressed: disabled
                ? null
                : () => restore(workspace, selection.selected.toSet()),
          ),
          const SizedBox(width: 6),
          AppActionButton.compact(
            key: const ValueKey('recycle-delete-selected'),
            theme: theme,
            label: '${l.agentRecycleDelete} (${selection.selected.length})',
            destructive: true,
            onPressed: disabled
                ? null
                : () => delete(workspace, selection.selected),
          ),
        ],
      ),
    );
    final bulkActionsDisabled = disabled || snapshot.entries.isEmpty;
    final bulkActions = DesktopCardSelectionTarget(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppActionButton(
            key: const ValueKey('recycle-restore-all'),
            theme: theme,
            label: l.agentRecycleRestoreAll,
            surfaceColor: theme.primary,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            onPressed: bulkActionsDisabled
                ? null
                : () => restore(workspace, {
                    for (final entry in snapshot.entries) entry.id,
                  }, all: true),
          ),
          const SizedBox(width: 8),
          AppActionButton(
            key: const ValueKey('recycle-empty-all'),
            theme: theme,
            label: l.agentRecycleEmptyAction,
            destructive: true,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            onPressed: bulkActionsDisabled ? null : () => empty(workspace),
          ),
        ],
      ),
    );
    return DesktopCardSelectionRegion(
      focusNode: selectionFocus,
      selection: selection,
      ids: _visibleIds,
      enabled: !disabled,
      onChanged: () => setState(() {}),
      onDelete: disabled ? null : () => delete(workspace, selection.selected),
      child: AppDialog(
        constraints: BoxConstraints(maxWidth: dialogWidth),
        theme: theme,
        title: l.agentRecycleBin,
        titleTrailing: compact ? null : bulkActions,
        contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: dialogWidth,
            maxWidth: dialogWidth,
            maxHeight: (MediaQuery.sizeOf(context).height * .65).clamp(
              180.0,
              640.0,
            ),
          ),
          child: ScrollbarTheme(
            data: ScrollbarTheme.of(context).copyWith(
              crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
              mainAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
            ),
            child: fitContent(
              [
                if (compact) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(fit: BoxFit.scaleDown, child: bulkActions),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  l.agentRecycleRestoreHint,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: theme.textColorSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l.agentRecycleRetention,
                  style: TextStyle(fontSize: 13, color: theme.textColorPrimary),
                ),
                const SizedBox(height: 8),
                SettingSelect<int>(
                  theme: theme,
                  surfaceColor: AppDialogStyle.backgroundColor(theme),
                  value: workspace.recycleRetentionDays,
                  items: [
                    for (final pair in [
                      (7, l.agentRecycleDays7),
                      (30, l.agentRecycleDays30),
                      (90, l.agentRecycleDays90),
                      (0, l.agentRecycleNever),
                    ])
                      DropdownMenuItem(value: pair.$1, child: Text(pair.$2)),
                  ],
                  onChanged: disabled
                      ? null
                      : (days) async {
                          if (days == null ||
                              days == workspace.recycleRetentionDays) {
                            return;
                          }
                          final expires =
                              days != 0 &&
                              workspace.recycledAgents.any(
                                (e) => !e.deletedAt
                                    .add(Duration(days: days))
                                    .isAfter(DateTime.now()),
                              );
                          if (expires &&
                              !await showAppConfirmation(
                                constraints: const BoxConstraints(
                                  maxWidth: 440,
                                ),
                                context: context,
                                theme: theme,
                                actionKey: 'recycle-retention',
                                destructive: true,
                                title: l.agentRecycleRetention,
                                description: l.agentRecycleRetentionConfirm,
                                confirmLabel: l.agentRecycleDelete,
                              )) {
                            return;
                          }
                          if (mounted) {
                            await run(
                              () => workspace.setRecycleRetentionDays(days),
                            );
                          }
                        },
                ),
                const SizedBox(height: 16),
                if (selection.selected.isEmpty)
                  searchField
                else
                  LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        Expanded(child: searchField),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * .65,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: batchActions,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              list: fitList(
                SuperListView.builder(
                  key: const ValueKey('recycle-agent-list-scroll'),
                  primary: false,
                  shrinkWrap: true,
                  padding: contentInset,
                  itemCount: entries.isEmpty ? 1 : entries.length,
                  itemBuilder: (context, index) {
                    if (entries.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            l.agentRecycleEmpty,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: theme.textColorSecondary,
                            ),
                          ),
                        ),
                      );
                    }
                    final entry = entries[index];
                    final selected = selection.selected.contains(entry.id);
                    if (_cardViews.lookup(entry.id, selected) case final view?) {
                      return view;
                    }
                    final card = Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DesktopCardSelectionMenu(
                        key: ValueKey(entry.id),
                        id: entry.id,
                        theme: theme,
                        extraItems: disabled
                            ? null
                            : (close) => [
                                RightClickMenuItem(
                                  key: ValueKey('recycle-restore-${entry.id}'),
                                  label: l.agentRecycleRestore,
                                  icon: Symbols.restore_from_trash,
                                  onTap: () {
                                    close();
                                    restore(workspace, {entry.id});
                                  },
                                ),
                              ],
                        child: Semantics(
                          selected: selection.selected.contains(entry.id),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: disabled
                                ? null
                                : () {
                                    selectionFocus.requestFocus();
                                    setState(
                                      () => selection.select(
                                        entry.id,
                                        _visibleIds,
                                        control:
                                            HardwareKeyboard
                                                .instance
                                                .isControlPressed ||
                                            HardwareKeyboard
                                                .instance
                                                .isMetaPressed,
                                        shift: HardwareKeyboard
                                            .instance
                                            .isShiftPressed,
                                      ),
                                    );
                                  },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 167),
                              curve: Curves.fastOutSlowIn,
                              key: ValueKey('recycle-agent-card-${entry.id}'),
                              decoration: BoxDecoration(
                                color: cardSurface,
                                border: Border.all(
                                  color: selection.selected.contains(entry.id)
                                      ? theme.basePrimary
                                      : Colors.transparent,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  18,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            entry.title,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: theme.textColorPrimary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${l.aiTopologyTaskId}: ${entry.id}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.textColorTertiary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      remainingTime(
                                        workspace.recycleExpiry(entry),
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.textColorTertiary,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        AppActionButton(
                                          theme: theme,
                                          label: l.agentRecycleRestore,
                                          surfaceColor: cardSurface,
                                          backgroundColor: restoreBackground,
                                          fontSize: 12,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 7,
                                          ),
                                          onPressed: disabled
                                              ? null
                                              : () => restore(workspace, {
                                                  entry.id,
                                                }),
                                        ),
                                        AppActionButton(
                                          theme: theme,
                                          label: l.agentRecycleDelete,
                                          destructive: true,
                                          fontSize: 12,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 7,
                                          ),
                                          onPressed: disabled
                                              ? null
                                              : () => delete(workspace, [
                                                  entry.id,
                                                ]),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    return _cardViews.store(entry.id, selected, card);
                  },
                ),
              ),
              footer: error != null
                  ? Text(
                      '$error',
                      style: TextStyle(color: theme.textColorSecondary),
                    )
                  : null,
            ),
          ),
        ),
        actions: [
          DesktopCardSelectionTarget(
            child: AppActionButton.dialog(
              theme: theme,
              label: l.close,
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
