import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/desktop_card_selection.dart';
import '../../../../core/widgets/settings/search_field.dart';
import '../../../../core/widgets/settings/select.dart';
import '../../state/agent_workspace_provider.dart';

Future<void> showAgentRecycleBin(BuildContext context, AppTheme theme) =>
    showDialog<void>(
      context: context,
      builder: (_) => _RecycleBin(theme: theme),
    );

class _RecycleBin extends StatefulWidget {
  const _RecycleBin({required this.theme});
  final AppTheme theme;
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
  final _cardViews = <String, ({bool selected, Widget view})>{};
  bool busy = false;
  Object? error;
  @override
  void dispose() {
    search.dispose();
    selectionFocus.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e);
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

  Future<void> restoreSelected(AiWorkspaceProvider workspace) async {
    if (busy || workspace.recycleBusy || selection.selected.isEmpty) return;
    final pending = {
      for (final entry in workspace.recycledAgents)
        if (selection.selected.contains(entry.id)) entry.id: entry,
    };
    await run(() async {
      // 先还原选中的上级，再还原下级；即使列表按删除时间倒序排列，
      // 仍能恢复原有层级关系。
      while (pending.isNotEmpty) {
        final entry =
            pending.values
                .where(
                  (entry) => !pending.containsKey(entry.record['parentId']),
                )
                .firstOrNull ??
            pending.values.first;
        await workspace.restoreRecycledAgent(entry.id);
        pending.remove(entry.id);
        selection.retain(workspace.recycledAgents.map((entry) => entry.id));
      }
    });
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
    Widget fitContent(
      List<Widget> header, {
      required Widget list,
      Widget? footer,
    }) => compact
        ? DesktopCardSelectionTarget(
            child: CustomScrollView(
              key: const ValueKey('recycle-agent-compact-scroll'),
              shrinkWrap: true,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: header,
                  ),
                ),
                list,
                if (footer != null) SliverToBoxAdapter(child: footer),
              ],
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...header, list, ?footer],
          );
    Widget fitList(ListView list) => compact
        ? SliverPadding(
            padding: list.padding ?? EdgeInsets.zero,
            sliver: SliverList(delegate: list.childrenDelegate),
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
          AppActionButton(
            key: const ValueKey('recycle-restore-selected'),
            theme: theme,
            label: '${l.agentRecycleRestore} (${selection.selected.length})',
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            onPressed: disabled ? null : () => restoreSelected(workspace),
          ),
          const SizedBox(width: 6),
          AppActionButton(
            key: const ValueKey('recycle-delete-selected'),
            theme: theme,
            label: '${l.agentRecycleDelete} (${selection.selected.length})',
            destructive: true,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            onPressed: disabled
                ? null
                : () => delete(workspace, selection.selected),
          ),
        ],
      ),
    );
    final emptyButton = DesktopCardSelectionTarget(
      child: AppActionButton(
        theme: theme,
        label: l.agentRecycleEmptyAction,
        destructive: true,
        fontSize: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        onPressed: disabled || snapshot.entries.isEmpty
            ? null
            : () => empty(workspace),
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
        titleTrailing: compact ? null : emptyButton,
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: fitContent(
              [
                if (compact) ...[
                  Align(alignment: Alignment.centerRight, child: emptyButton),
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
                ListView.builder(
                  key: const ValueKey('recycle-agent-list-scroll'),
                  primary: false,
                  shrinkWrap: true,
                  padding: entries.isEmpty
                      ? EdgeInsets.zero
                      : const EdgeInsets.only(right: 20),
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
                    final cached = _cardViews[entry.id];
                    if (cached != null && cached.selected == selected) {
                      return cached.view;
                    }
                    final card = Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DesktopCardSelectionTarget(
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
                                color: theme.secondary,
                                border: Border.all(
                                  color: selection.selected.contains(entry.id)
                                      ? theme.basePrimary
                                      : Colors.transparent,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
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
                                          surfaceColor: theme.primary,
                                          fontSize: 12,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 7,
                                          ),
                                          onPressed: disabled
                                              ? null
                                              : () => run(
                                                  () => workspace
                                                      .restoreRecycledAgent(
                                                        entry.id,
                                                      ),
                                                ),
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
                    _cardViews[entry.id] = (selected: selected, view: card);
                    return card;
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
              onPressed: disabled ? null : () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
