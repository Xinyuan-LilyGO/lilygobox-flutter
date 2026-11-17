import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/desktop_card_selection.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/settings/fields.dart';
import '../../../../core/widgets/settings/search_field.dart';
import '../../../../core/widgets/settings/select.dart';
import '../../../settings/presentation/widgets/content_layout.dart';
import '../../domain/agent_package_progress.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/provider.dart' show AiContextCompactionOutcome;
import '../../state/storage_controller.dart';
import 'agent_direct_transfer.dart';
import 'agent_transfer_error.dart';
import 'agent_transfer_progress_dialog.dart';
import 'memory_import_review.dart';
import 'recycle_bin_dialog.dart';

enum _StorageManager { memory, context, backup }

class AgentStorageContent extends StatefulWidget {
  const AgentStorageContent({super.key, required this.theme, this.owner})
    : _manager = null;

  const AgentStorageContent._manager({
    required this.theme,
    required this.owner,
    required this._manager,
  });

  final _StorageManager? _manager;
  final AppTheme theme;
  final String? owner;
  @override
  State<AgentStorageContent> createState() => _AgentStorageContentState();
}

class _AgentStorageContentState extends State<AgentStorageContent> {
  late final AgentStorageController controller;
  final search = TextEditingController();
  final _memorySelection = DesktopCardSelection();
  final _memoryListFocus = FocusNode(debugLabel: 'memory card selection');
  String? _memorySelectionOwner;
  List<Map<String, Object?>>? _memorySource;
  List<String> _memoryIds = const [];
  Object? _memoryEnvironment;
  final _memoryViews = <String, ({bool selected, Widget view})>{};
  final _contextBudget = TextEditingController();
  final _contextPercent = TextEditingController();
  int? _savedPercent;
  bool _invalidPercent = false;
  String? _budgetOwner;
  int? _savedBudget;
  bool _invalidBudget = false;
  String _packageType = 'workflow';
  String? _exportTarget = 'workflow';
  bool _importMode = false;
  bool _includeChildren = false;
  bool _choosingFile = false;
  @override
  void initState() {
    super.initState();
    controller = AgentStorageController(context.read<AiWorkspaceProvider>())
      ..owner = widget.owner ?? '';
    controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _run(controller.refresh);
      if (!mounted) return;
    });
  }

  Future<void> _openManager(_StorageManager manager) async {
    final owner = await showDialog<String>(
      context: context,
      builder: (_) => AgentStorageContent._manager(
        theme: widget.theme,
        owner: controller.owner,
        manager: manager,
      ),
    );
    if (!mounted) return;
    if (owner != null) controller.owner = owner;
    await _run(controller.refresh);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    search.dispose();
    _memoryListFocus.dispose();
    _contextBudget.dispose();
    _contextPercent.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (controller.busy) return;
    setState(() {
      controller.busy = true;
      controller.error = null;
    });
    try {
      await work();
    } on AgentPackageCancelled {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          context.l10n.agentStorageTransferCancelled,
        );
      }
    } catch (e) {
      controller.error = e;
    } finally {
      if (mounted) setState(() => controller.busy = false);
    }
  }

  Future<void> _clean() => _run(() async {
    final l = context.l10n;
    try {
      await controller.workspaces.flush();
      final result =
          await controller.workspaces.main.storage!.request('clean') as Map;
      await controller.refresh(query: search.text);
      if (!mounted) return;
      final count = result['objectsRemoved'] as int;
      final bytes = result['bytesFreed'] as int;
      final message = count > 0
          ? l.agentStorageCleanResult(count, _StorageOverview._size(bytes))
          : bytes > 0
          ? l.agentStorageCleanSpaceResult(_StorageOverview._size(bytes))
          : l.agentStorageCleanNothing;
      showAppNotice(ScaffoldMessenger.of(context), message);
    } catch (_) {
      if (mounted) {
        showAppNotice(ScaffoldMessenger.of(context), l.agentStorageCleanFailed);
      }
      rethrow;
    }
  });

  Future<void> _compact(AiAgentWorkspace selected) => _run(() async {
    final l = context.l10n;
    final before = selected.assistant.estimatedContextTokens;
    try {
      final outcome = await selected.assistant.compactContext();
      if (!mounted) return;
      final message = switch (outcome) {
        AiContextCompactionOutcome.compacted => l.agentStorageCompactResult(
          before,
          selected.assistant.estimatedContextTokens,
        ),
        AiContextCompactionOutcome.insufficientHistory =>
          l.agentStorageCompactTooShort,
        AiContextCompactionOutcome.unavailableModel =>
          l.agentStorageCompactUnavailable,
        AiContextCompactionOutcome.cancelled => l.agentStorageCompactCancelled,
        AiContextCompactionOutcome.unchanged => l.agentStorageCompactUnchanged,
      };
      showAppNotice(ScaffoldMessenger.of(context), message);
    } catch (_) {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          l.agentStorageCompactFailed,
        );
      }
      rethrow;
    }
  });

  Future<T> _transfer<T>(Future<T> Function() work) async {
    try {
      return await showAgentTransferProgress<T>(
        context: context,
        theme: widget.theme,
        controller: controller,
        work: work,
      );
    } on AgentPackageCancelled {
      rethrow;
    } catch (error) {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          agentTransferFailureMessage(context, error),
        );
      }
      rethrow;
    }
  }

  Future<void> _withFilePicker(Future<void> Function() work) async {
    if (_choosingFile || controller.busy) return;
    _choosingFile = true;
    try {
      // 原生对话框已阻止所属窗口交互，无需改变选中颜色。
      await work();
    } catch (error) {
      if (mounted) {
        setState(() => controller.error = error);
        showAppNotice(
          ScaffoldMessenger.of(context),
          agentTransferFailureMessage(context, error),
        );
      }
    } finally {
      _choosingFile = false;
    }
  }

  Future<void> _export(
    String type, {
    bool children = false,
  }) => _withFilePicker(() async {
    final l = context.l10n;
    final destination = await getSaveLocation(
      suggestedName: controller.suggestedExportName(type, children: children),
      acceptedTypeGroups: [
        XTypeGroup(label: l.agentStoragePackageType, extensions: const ['7z']),
      ],
    );
    if (destination == null || !mounted) return;
    await _run(() async {
      await _transfer(
        () => controller.export(destination.path, type, children: children),
      );
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          l.agentStorageExportSuccess,
        );
      }
    });
  });

  Future<void> _chooseImportPackage() => _withFilePicker(_readImportPackage);

  Future<void> _readImportPackage() async {
    final l = context.l10n;
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: l.agentStoragePackageType, extensions: const ['7z']),
      ],
    );
    if (file == null || !mounted) return;
    await _run(() async {
      var package = await _transfer(() => controller.inspect(file.path));
      if (!mounted) return;
      if (package['type'] == 'memory') {
        final target = await showDialog<String>(
          context: context,
          builder: (_) => _MemoryImportDestination(
            theme: widget.theme,
            workspaces: controller.workspaces,
            owner: controller.owner,
          ),
        );
        if (target == null || !mounted) return;
        if (target == _MemoryImportDestination.newAgent) {
          package = controller.memoryPackageForNewAgent(
            package,
            title: l.agentStorageImportedMemoryAgent,
          );
        } else {
          controller.owner = target;
        }
      }
      await _importSelectedPackage(package);
    });
  }

  Future<void> _importSelectedPackage(Map<String, dynamic> package) async {
    final l = context.l10n;
    final plan = await _transfer(() => controller.plan(package));
    if (!mounted) return;
    if (package['type'] == 'memory' &&
        plan.isNotEmpty &&
        !await reviewMemoryImport(context, widget.theme, plan)) {
      return;
    }
    if (!mounted) return;
    await _transfer(() => controller.import(package, plan: plan));
    if (mounted) {
      showAppNotice(ScaffoldMessenger.of(context), l.agentStorageImportSuccess);
    }
  }

  Future<void> _edit([Map<String, Object?>? memory]) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _MemoryEditor(
        theme: widget.theme,
        initial: memory?['content'] as String? ?? '',
      ),
    );
    if (value != null && value.trim().isNotEmpty) {
      await _run(
        () => controller.saveMemory(value, id: memory?['id'] as String?),
      );
    }
  }

  Widget _button(
    String text,
    IconData icon,
    VoidCallback callback, {
    bool enabled = true,
    bool destructive = false,
    EdgeInsetsGeometry? padding,
  }) => AppActionButton(
    destructive: destructive,
    padding: padding,
    theme: widget.theme,
    label: text,
    icon: icon,
    onPressed: controller.busy || !enabled ? null : callback,
  );
  String _packageLabel(String type) {
    final l = context.l10n;
    return switch (type) {
      'memory' => l.agentStorageMemoryPackage,
      'chat' => l.agentStorageChatPackage,
      'agent' => l.agentStorageAgentPackage,
      'workflow' => l.agentStorageWorkflowPackage,
      _ => throw ArgumentError.value(type, 'type'),
    };
  }

  String _packageDescription(String type) {
    final l = context.l10n;
    return switch (type) {
      'memory' => l.agentStorageMemoryPackageHint,
      'chat' => l.agentStorageChatPackageHint,
      'agent' => l.agentStorageAgentPackageHint,
      'workflow' => l.agentStorageWorkflowPackageHint,
      _ => throw ArgumentError.value(type, 'type'),
    };
  }

  Widget _scopeField(
    AiWorkspaceProvider workspaces, {
    bool forContext = false,
    bool forMemory = false,
  }) {
    final l = context.l10n;
    final theme = widget.theme;
    final selected = workspaces.find(controller.owner);
    final title = forMemory
        ? l.agentStorageScope
        : forContext
        ? l.agentStorageContextScope
        : l.agentStorageAgentTarget;
    final emptyLabel = forMemory || forContext
        ? l.agentStorageNoManagedAgents
        : l.agentStorageNoExportAgents;
    return SettingsField(
      theme: theme,
      title: title,
      description: forMemory ? l.agentStorageMemoryScopeHint : '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingSelect<String>(
            key: const ValueKey('storage-owner-select'),
            theme: theme,
            value: selected != null ? controller.owner : '',
            items: [
              if (selected == null)
                DropdownMenuItem(
                  value: '',
                  enabled: false,
                  child: Text(
                    workspaces.sessions.isEmpty
                        ? emptyLabel
                        : l.agentStorageChooseAgent,
                  ),
                ),
              for (final session in workspaces.sessions)
                DropdownMenuItem(
                  value: session.id,
                  child: Text(
                    '${session.id} · ${session.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: controller.busy || workspaces.sessions.isEmpty
                ? null
                : (value) {
                    if (value != null && value.isNotEmpty) {
                      if (controller.owner != value) {
                        _includeChildren = false;
                        _memorySelection.clear();
                      }
                      controller.owner = value;
                      _run(() => controller.refresh(query: search.text));
                    }
                  },
          ),
        ],
      ),
    );
  }

  bool _canIncludeChildren(AiWorkspaceProvider workspaces) =>
      _exportTarget == 'agent' &&
      _packageType == 'agent' &&
      workspaces.childrenOf(controller.owner).isNotEmpty;

  Widget _exportFields(AiWorkspaceProvider workspaces) {
    final l = context.l10n;
    final theme = widget.theme;
    final hasWorkflow = workspaces.sessions.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsField(
          theme: theme,
          title: l.agentStorageExportTarget,
          description: _exportTarget == 'workflow'
              ? '${_packageDescription(_packageType)} ${l.agentStoragePackageKindHint} ${l.agentStorageSensitiveHint}'
              : _packageDescription(_packageType),
          child: SettingSelect<String>(
            key: const ValueKey('storage-export-target'),
            theme: theme,
            value: _exportTarget ?? '',
            items: [
              DropdownMenuItem(
                value: 'agent',
                child: Text(l.agentStorageAgentTarget),
              ),
              DropdownMenuItem(
                value: 'workflow',
                enabled: hasWorkflow,
                child: Text(
                  hasWorkflow
                      ? l.aiTopologyTitle
                      : l.agentStorageNoExportWorkflow,
                ),
              ),
            ],
            onChanged: controller.busy
                ? null
                : (target) {
                    if (target == null || target.isEmpty) return;
                    setState(() {
                      _exportTarget = target;
                      _packageType = target == 'agent' ? 'agent' : 'workflow';
                      _includeChildren = false;
                    });
                  },
          ),
        ),
        if (_exportTarget == 'agent') ...[
          const SizedBox(height: 20),
          _scopeField(workspaces),
          const SizedBox(height: 20),
          SettingsField(
            theme: theme,
            title: l.agentStoragePackageKind,
            description:
                '${l.agentStoragePackageKindHint} ${l.agentStorageSensitiveHint}',
            child: SettingSelect<String>(
              key: const ValueKey('storage-package-type'),
              theme: theme,
              value: _packageType,
              items: [
                for (final type in ['agent', 'chat', 'memory'])
                  DropdownMenuItem(
                    value: type,
                    child: Text(
                      type == 'agent'
                          ? l.agentStorageBackupPackage
                          : _packageLabel(type),
                    ),
                  ),
              ],
              onChanged: controller.busy
                  ? null
                  : (type) {
                      if (type != null) {
                        setState(() {
                          _packageType = type;
                          _includeChildren = false;
                        });
                      }
                    },
            ),
          ),
        ],
        if (_canIncludeChildren(workspaces)) ...[
          const SizedBox(height: 12),
          _exportOption(
            key: const ValueKey('storage-include-children'),
            label: l.agentStorageIncludeChildren,
            value: _includeChildren,
            onChanged: controller.busy
                ? null
                : (value) => setState(() => _includeChildren = value ?? false),
          ),
        ],
      ],
    );
  }

  Widget _exportOption({
    Key? key,
    required String label,
    required bool value,
    required ValueChanged<bool?>? onChanged,
  }) {
    final theme = widget.theme;
    return MergeSemantics(
      child: Padding(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: theme.textColorPrimary),
              ),
            ),
            const SizedBox(width: 12),
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: theme.basePrimary,
              checkColor: theme.materialColors.onPrimary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(List<Widget> children) => SettingsPanel(
    theme: widget.theme,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _managementRow({
    required String title,
    required String description,
    required String label,
    required VoidCallback onPressed,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: widget.theme.textColorPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: widget.theme.textColorTertiary,
              ),
            ),
          ],
        );
        final action = AppActionButton.settings(
          theme: widget.theme,
          label: label,
          onPressed: controller.busy ? null : onPressed,
        );
        return constraints.maxWidth < 360
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [text, const SizedBox(height: 10), action],
              )
            : Row(
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 20),
                  action,
                ],
              );
      },
    ),
  );

  Future<void> _saveContextBudget(AiAgentWorkspace selected) async {
    if (!mounted ||
        controller.busy ||
        controller.workspaces.find(selected.id) != selected) {
      return;
    }
    final value = int.tryParse(_contextBudget.text.trim());
    if (value == null || value <= 0) {
      setState(() => _invalidBudget = true);
      return;
    }
    setState(() {
      _invalidBudget = false;
      selected.assistant.contextBudgetTokens = value;
      _savedBudget = value;
    });
    await _run(controller.workspaces.flush);
  }

  Future<void> _saveContextPercent(AiAgentWorkspace selected) async {
    if (!mounted ||
        controller.busy ||
        controller.workspaces.find(selected.id) != selected) {
      return;
    }
    final value = int.tryParse(_contextPercent.text.trim());
    if (value == null || value < 1 || value > 100) {
      setState(() => _invalidPercent = true);
      return;
    }
    setState(() {
      _invalidPercent = false;
      selected.assistant.contextCompactionPercent = value;
      _savedPercent = value;
    });
    await _run(controller.workspaces.flush);
  }

  Widget _contextControls(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace? selected,
  ) {
    final l = context.l10n;
    final theme = widget.theme;
    if (selected != null &&
        (_budgetOwner != selected.id ||
            _savedBudget != selected.assistant.contextBudgetTokens)) {
      _budgetOwner = selected.id;
      _savedBudget = selected.assistant.contextBudgetTokens;
      _contextBudget.text = _savedBudget.toString();
      _invalidBudget = false;
      _savedPercent = selected.assistant.contextCompactionPercent;
      _contextPercent.text = _savedPercent.toString();
      _invalidPercent = false;
    }
    if (selected != null &&
        _savedPercent != selected.assistant.contextCompactionPercent) {
      _savedPercent = selected.assistant.contextCompactionPercent;
      _contextPercent.text = _savedPercent.toString();
      _invalidPercent = false;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scopeField(workspaces, forContext: true),
        if (selected != null) ...[
          const SizedBox(height: 16),
          SettingsField(
            theme: theme,
            title: l.agentStorageContextUsage,
            description: l.agentStorageContextUsageHint,
            trailing: Text(
              l.agentStorageTokens(selected.assistant.estimatedContextTokens),
              style: TextStyle(fontSize: 12, color: theme.textColorSecondary),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SettingsField(
                  theme: theme,
                  title: l.agentStorageContextBudget,
                  description: '',
                  child: Focus(
                    onFocusChange: (focused) {
                      if (!focused &&
                          _contextBudget.text != _savedBudget.toString()) {
                        _saveContextBudget(selected);
                      }
                    },
                    child: SettingControlledTextField(
                      key: const ValueKey('storage-context-budget'),
                      theme: theme,
                      controller: _contextBudget,
                      enabled: !controller.busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      suffixIcon: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            'token',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textColorTertiary,
                            ),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _saveContextBudget(selected),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SettingsField(
                  theme: theme,
                  title: l.agentStorageContextPercent,
                  description: '',
                  child: Focus(
                    onFocusChange: (focused) {
                      if (!focused &&
                          _contextPercent.text != _savedPercent.toString()) {
                        _saveContextPercent(selected);
                      }
                    },
                    child: SettingControlledTextField(
                      key: const ValueKey('storage-context-percent'),
                      theme: theme,
                      controller: _contextPercent,
                      enabled: !controller.busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      suffixIcon: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            '%',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textColorTertiary,
                            ),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _saveContextPercent(selected),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.agentStorageContextTriggerTokens(
              selected.assistant.contextCompactionThresholdTokens,
            ),
            style: TextStyle(fontSize: 12, color: theme.textColorSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            l.agentStorageContextHint,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: theme.textColorTertiary,
            ),
          ),
          if (_invalidPercent) ...[
            const SizedBox(height: 4),
            Text(
              l.agentStorageContextPercentInvalid,
              style: TextStyle(fontSize: 11, color: theme.materialColors.error),
            ),
          ],
          if (selected.assistant.contextCompactionPercent >= 95) ...[
            const SizedBox(height: 4),
            Text(
              l.agentStorageContextPercentWarning,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: theme.materialColors.error,
              ),
            ),
          ],
          if (_invalidBudget) ...[
            const SizedBox(height: 4),
            Text(
              l.agentStorageContextInvalid,
              style: TextStyle(fontSize: 11, color: theme.materialColors.error),
            ),
          ],
          const SizedBox(height: 16),
          SettingsField(
            theme: theme,
            title: l.agentStorageCompact,
            description: l.agentStorageCompactHint,
            trailing: _button(
              l.agentStorageCompactNow,
              Symbols.compress,
              () => _compact(selected),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              enabled: !selected.busy,
            ),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: theme.dividerColor),
          const SizedBox(height: 16),
          SettingsField(
            theme: theme,
            title: l.agentStorageChatDataTitle,
            description: l.agentStorageDeleteChatHint,
            trailing: _button(
              l.delete,
              Symbols.delete_sweep,
              () async {
                if (selected.busy) return;
                final yes = await showAppConfirmation(
                  constraints: const BoxConstraints(maxWidth: 440),
                  context: context,
                  theme: theme,
                  actionKey: 'delete-chat',
                  destructive: true,
                  title: l.agentStorageDeleteChat,
                  description: l.agentStorageDeleteChatHint,
                  confirmLabel: l.delete,
                );
                if (yes) {
                  selected.assistant.clearConversation();
                  await _run(workspaces.flush);
                }
              },
              enabled: !selected.busy,
              destructive: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _deleteSelectedMemories([String? singleId]) async {
    if (controller.busy) return;
    final owner = controller.owner;
    final ids = singleId == null
        ? _memorySelection.selected.toSet()
        : {singleId};
    if (ids.isEmpty || controller.workspaces.find(owner) == null) return;
    final l = context.l10n;
    final confirmed = await showAppConfirmation(
      context: context,
      theme: widget.theme,
      constraints: const BoxConstraints(maxWidth: 440),
      actionKey: singleId == null ? 'delete-selected-memory' : 'delete-memory',
      destructive: true,
      title: l.agentStorageDeleting,
      description: singleId == null
          ? l.agentStorageDeleteSelectedHint(ids.length)
          : l.agentStorageDeleteMemoryHint,
      confirmLabel: singleId == null
          ? l.agentStorageDeleteSelected(ids.length)
          : l.delete,
    );
    if (!confirmed ||
        !mounted ||
        controller.busy ||
        controller.owner != owner ||
        controller.workspaces.find(owner) == null) {
      return;
    }
    await _run(() async {
      await controller.deleteMemories(ids);
      _memorySelection.clear();
    });
  }

  Widget _memoryCards(AiWorkspaceProvider workspaces) {
    final theme = widget.theme;
    final l = context.l10n;
    if (!identical(_memorySource, controller.memories)) {
      _memorySource = controller.memories;
      _memoryIds = controller.memories.map((m) => m['id'] as String).toList();
      _memoryViews.clear();
    }
    final ids = _memoryIds;
    if (_memorySelectionOwner != controller.owner) {
      _memorySelectionOwner = controller.owner;
      _memorySelection.clear();
    }
    final enabled =
        !controller.busy && workspaces.find(controller.owner) != null;
    final environment = (theme, l, enabled, controller.owner);
    if (_memoryEnvironment != environment) {
      _memoryEnvironment = environment;
      _memoryViews.clear();
    }
    return DesktopCardSelectionRegion(
      focusNode: _memoryListFocus,
      selection: _memorySelection,
      ids: ids,
      enabled: enabled,
      onChanged: () => setState(() {}),
      onDelete: enabled ? () => _deleteSelectedMemories() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final searchField = DesktopCardSelectionTarget(
                child: Semantics(
                  label: l.agentStorageSearch,
                  child: SettingSearchField(
                    key: const ValueKey('storage-memory-search'),
                    theme: theme,
                    controller: search,
                    enabled: !controller.busy,
                    onClear: () {
                      search.clear();
                      _run(() => controller.refresh());
                    },
                    hintText: l.agentStorageSearch,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (value) {
                      _run(() => controller.refresh(query: value));
                    },
                  ),
                ),
              );
              final addButton = AppActionButton(
                theme: theme,
                label: l.agentStorageAdd,
                icon: Symbols.add_rounded,
                iconSize: 16,
                iconSpacing: 6,
                fontSize: 12,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                onPressed: enabled ? () => _edit() : null,
              );
              final deleteButton = _memorySelection.selected.isEmpty
                  ? null
                  : AppActionButton(
                      key: const ValueKey('storage-memory-delete-selected'),
                      theme: theme,
                      label: l.agentStorageDeleteSelected(
                        _memorySelection.selected.length,
                      ),
                      destructive: true,
                      fontSize: 12,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      onPressed: enabled
                          ? () => _deleteSelectedMemories()
                          : null,
                    );
              final actions = DesktopCardSelectionTarget(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [addButton, ?deleteButton],
                ),
              );
              double labelWidth(String label, FontWeight weight) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: label,
                    style: DefaultTextStyle.of(context).style
                        .copyWith(fontSize: 12, fontWeight: weight),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final width = painter.width;
                painter.dispose();
                return width;
              }

              final actionsWidth =
                  labelWidth(l.agentStorageAdd, FontWeight.w400) +
                  16 +
                  6 +
                  16 +
                  (deleteButton == null
                      ? 0
                      : 8 +
                            16 +
                            labelWidth(
                              l.agentStorageDeleteSelected(
                                _memorySelection.selected.length,
                              ),
                              FontWeight.w600,
                            ));
              // 为搜索框保留可用宽度；当操作按钮的
              // 本地化文字和字体无法同排容纳时，将按钮移到下方。
              if (actionsWidth + 8 + 140 > constraints.maxWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [searchField, const SizedBox(height: 8), actions],
                );
              }
              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 8),
                  actions,
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height * .24).clamp(
                100.0,
                240.0,
              ),
            ),
            child: ListView.builder(
              key: const ValueKey('storage-memory-list-scroll'),
              primary: false,
              shrinkWrap: true,
              padding: const EdgeInsets.only(right: 20),
              itemCount: controller.memories.isEmpty
                  ? 1
                  : controller.memories.length + (controller.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (controller.memories.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      l.agentStorageEmpty,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textColorSecondary,
                      ),
                    ),
                  );
                }
                if (index == controller.memories.length) {
                  return _button(
                    l.agentStorageMore,
                    Symbols.expand_more,
                    () => _run(controller.loadMore),
                  );
                }
                final memory = controller.memories[index];
                final id = memory['id'] as String;
                final selected = _memorySelection.selected.contains(id);
                final cached = _memoryViews[id];
                if (cached != null && cached.selected == selected) {
                  return cached.view;
                }
                final view = _memoryCard(memory, ids, enabled);
                _memoryViews[id] = (selected: selected, view: view);
                return view;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _memoryCard(
    Map<String, Object?> memory,
    List<String> ids,
    bool enabled,
  ) {
    final theme = widget.theme;
    final l = context.l10n;
    final id = memory['id'] as String;
    final selected = _memorySelection.selected.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DesktopCardSelectionTarget(
        child: Semantics(
          selected: selected,
          child: Material(
            animationDuration: const Duration(milliseconds: 167),
            color: theme.secondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: selected ? theme.basePrimary : Colors.transparent,
                width: 1,
              ),
            ),
            child: Theme(
              data: Theme.of(context)
                  .copyWith(highlightColor: Colors.transparent),
              child: ListTile(
                key: ValueKey('storage-memory-card-$id'),
                selected: selected,
                contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                horizontalTitleGap: 8,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                splashColor: Colors.transparent,
                selectedTileColor: Colors.transparent,
                title: Text(
                  memory['content'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: theme.textColorPrimary),
                ),
                onTap: !enabled
                    ? null
                    : () {
                        final keyboard = HardwareKeyboard.instance;
                        setState(
                          () => _memorySelection.select(
                            id,
                            ids,
                            control:
                                keyboard.isControlPressed ||
                                keyboard.isMetaPressed,
                            shift: keyboard.isShiftPressed,
                          ),
                        );
                        _memoryListFocus.requestFocus();
                      },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MemoryActionButton(
                      theme: theme,
                      tooltip: l.agentStorageEditMemory,
                      icon: const Icon(Symbols.edit_rounded, size: 18),
                      onPressed: enabled ? () => _edit(memory) : null,
                    ),
                    const SizedBox(width: 4),
                    _MemoryActionButton(
                      theme: theme,
                      tooltip: l.delete,
                      icon: const Icon(Symbols.delete, fill: 1, size: 18),
                      onPressed: enabled
                          ? () => _deleteSelectedMemories(id)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final workspaces = context.watch<AiWorkspaceProvider>();
    final theme = widget.theme;
    final selected = workspaces.find(controller.owner);
    final hasWorkflow = workspaces.sessions.isNotEmpty;
    if (widget._manager case final manager?) {
      return AppDialog(
        constraints: const BoxConstraints(maxWidth: 440),
        theme: theme,
        title: switch (manager) {
          _StorageManager.memory => l.agentStorageMemories,
          _StorageManager.context => l.agentStorageContextTitle,
          _StorageManager.backup => l.agentStorageBackupTitle,
        },
        contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.sizeOf(context).height * .65).clamp(
              160.0,
              640.0,
            ),
          ),
          child: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              key: const ValueKey('storage-manager-scroll'),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (manager == _StorageManager.memory)
                    Padding(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _scopeField(workspaces, forMemory: true),
                          if (selected != null &&
                              manager == _StorageManager.memory) ...[
                            const SizedBox(height: 16),
                            SettingsField(
                              theme: theme,
                              title: l.agentStorageMemoryEnabled,
                              description: l.agentStorageMemoryHint,
                              trailing: SizedBox(
                                width: 44,
                                height: 28,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: Switch(
                                    key: const ValueKey(
                                      'storage-use-memory-switch',
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    activeTrackColor: theme.basePrimary,
                                    value: selected.assistant.useMemory,
                                    onChanged: controller.busy
                                        ? null
                                        : (v) {
                                            setState(
                                              () =>
                                                  selected.assistant.useMemory =
                                                      v,
                                            );
                                            _run(workspaces.flush);
                                          },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SettingsField(
                              theme: theme,
                              title: l.agentStorageAutoMemoryTitle,
                              description: l.agentStorageAutoMemoryHint,
                              trailing: SizedBox(
                                width: 44,
                                height: 28,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: Switch(
                                    key: const ValueKey(
                                      'storage-auto-memory-switch',
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    activeTrackColor: theme.basePrimary,
                                    value: selected.assistant.autoSaveMemory,
                                    onChanged:
                                        controller.busy ||
                                            !selected.assistant.useMemory
                                        ? null
                                        : (value) {
                                            setState(
                                              () =>
                                                  selected
                                                          .assistant
                                                          .autoSaveMemory =
                                                      value,
                                            );
                                            _run(workspaces.flush);
                                          },
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _memoryCards(workspaces),
                        ],
                      ),
                    )
                  else if (manager == _StorageManager.context)
                    _contextControls(workspaces, selected)
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: AppActionButton.dialog(
                            theme: theme,
                            label: l.agentStorageExportTab,
                            primary: !_importMode,
                            onPressed: controller.busy
                                ? null
                                : () => setState(() => _importMode = false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppActionButton.dialog(
                            theme: theme,
                            label: l.agentStorageImportTab,
                            primary: _importMode,
                            onPressed: controller.busy
                                ? null
                                : () => setState(() => _importMode = true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_importMode) ...[
                      SettingsField(
                        theme: theme,
                        title: l.agentStorageImportFile,
                        description: l.agentStorageImportAutoHint,
                        child: const SizedBox.shrink(),
                      ),
                    ] else ...[
                      _exportFields(workspaces),
                    ],
                  ],
                  if (controller.error != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      '${l.agentStorageFailure}\n${controller.error}',
                      style: TextStyle(color: theme.textColorPrimary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          AppActionButton.dialog(
            theme: theme,
            label: l.close,
            onPressed: controller.busy
                ? null
                : () => Navigator.pop(context, controller.owner),
          ),
          if (manager == _StorageManager.backup)
            AppActionButton.dialog(
              key: const ValueKey('storage-transfer-action'),
              theme: theme,
              primary: true,
              label: _importMode
                  ? l.agentStorageChoosePackage
                  : l.agentStorageExportTab,
              onPressed:
                  controller.busy ||
                      (!_importMode &&
                          (_exportTarget == null ||
                              _exportTarget == 'workflow' && !hasWorkflow ||
                              ['chat', 'agent'].contains(_packageType) &&
                                  selected == null ||
                              _packageType == 'memory' &&
                                  controller.owner.isEmpty))
                  ? null
                  : _importMode
                  ? _chooseImportPackage
                  : () => _export(
                      _packageType,
                      children:
                          _canIncludeChildren(workspaces) && _includeChildren,
                    ),
            ),
        ],
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 40),
                child: Text(
                  l.agentStorageTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l.agentStorageDescription,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: theme.textColorTertiary,
                ),
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: SettingsColors(theme).divider),
              const SizedBox(height: 14),
              _StorageOverview(
                theme: theme,
                stats: controller.stats,
                path: workspaces.main.storage?.databasePath,
                onRefresh: controller.busy
                    ? null
                    : () => _run(() async {
                        await workspaces.flush();
                        await controller.refresh(query: search.text);
                      }),
              ),
              const SizedBox(height: 28),
              _panel([
                _managementRow(
                  title: l.agentStorageMemories,
                  description: l.agentStorageManageHint,
                  label: l.agentStorageManageAction,
                  onPressed: () => _openManager(_StorageManager.memory),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, color: theme.dividerColor),
                ),
                _managementRow(
                  title: l.agentStorageContextTitle,
                  description: l.agentStorageContextManageHint,
                  label: l.agentStorageManageAction,
                  onPressed: () => _openManager(_StorageManager.context),
                ),
              ]),
              const SizedBox(height: 12),
              _panel([
                _managementRow(
                  title: l.agentStorageBackupTitle,
                  description: l.agentStorageBackupHint,
                  label: l.agentStorageManageAction,
                  onPressed: () => _openManager(_StorageManager.backup),
                ),
              ]),
              const SizedBox(height: 12),
              _panel([
                _managementRow(
                  title: l.agentStorageClean,
                  description: l.agentStorageCleanHint,
                  label: l.agentStorageCleanAction,
                  onPressed: _clean,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, color: theme.dividerColor),
                ),
                _managementRow(
                  title: l.agentRecycleBin,
                  description: l.agentRecycleHint,
                  label: l.agentStorageManageAction,
                  onPressed: () async {
                    await showAgentRecycleBin(context, theme);
                    if (mounted) await _run(controller.refresh);
                  },
                ),
              ]),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(
                    '${l.agentStorageFailure}\n${controller.error}',
                    style: TextStyle(color: theme.textColorPrimary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageOverview extends StatelessWidget {
  const _StorageOverview({
    required this.theme,
    required this.stats,
    required this.path,
    required this.onRefresh,
  });
  final AppTheme theme;
  final Map<String, Object?> stats;
  final String? path;
  final VoidCallback? onRefresh;

  static String _size(num bytes) {
    if (bytes < 1024) return '${bytes.round()} B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final total = (stats['bytes'] as num? ?? 0).toInt();
    final parts = stats['breakdown'] as Map? ?? const {};
    int value(String key) => (parts[key] as num? ?? 0).toInt();
    final stateParts = stats['stateBreakdown'] as Map? ?? const {};
    int stateValue(String key) => (stateParts[key] as num? ?? 0).toInt();
    final content = value('objects');
    final memory = value('memories');
    final other = (total - content - value('state') - memory).clamp(0, total);
    final categories = [
      (
        l.agentStorageChatDataTitle,
        content + stateValue('conversations') + stateValue('context'),
        const Color(0xffa3d52d),
      ),
      (
        l.agentStorageWorkflowCategory,
        stateValue('workflow'),
        const Color(0xff54a9ff),
      ),
      (l.agentRecycleBin, stateValue('recycleBin'), const Color(0xffef748e)),
      (l.agentStorageMemoryCategory, memory, const Color(0xffffcd36)),
      (
        l.agentStorageOtherCategory,
        other,
        theme.adaptiveColor(
          dark: const Color(0xff808080),
          light: const Color(0xffa0a0a0),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.agentStorageDevice,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.agentStorageDeviceHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textColorTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppActionButton.settings(
              theme: theme,
              label: l.refresh,
              onPressed: onRefresh,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          '${l.agentStorageUsage} ${_size(total)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.textColorPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          label: categories.map((c) => '${c.$1}: ${_size(c.$2)}').join(', '),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 16,
              width: double.infinity,
              child: total == 0
                  ? ColoredBox(color: theme.dividerColor)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final c in categories)
                          if (c.$2 > 0)
                            Expanded(
                              flex: c.$2,
                              child: ColoredBox(color: c.$3),
                            ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 22,
          runSpacing: 10,
          children: [
            for (final c in categories)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.$3,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 6, height: 6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        c.$1,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.textColorSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _size(c.$2),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.textColorTertiary,
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (path != null) ...[
          const SizedBox(height: 14),
          Text(
            l.agentStorageDatabaseLocation,
            style: TextStyle(fontSize: 11, color: theme.textColorSecondary),
          ),
          const SizedBox(height: 3),
          SelectableText(
            File(path!).parent.path,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: theme.textColorTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> showAgentContextStorage(
  BuildContext context,
  AppTheme theme,
  String owner,
) => showDialog<void>(
  context: context,
  builder: (_) => AgentStorageContent._manager(
    theme: theme,
    owner: owner,
    manager: _StorageManager.context,
  ),
);

Future<void> showAgentStorage(
  BuildContext context,
  AppTheme theme,
  String owner, {
  String? action,
  Set<String>? selectedIds,
}) async {
  if (action != null) {
    await runDirectAgentTransfer(
      context,
      theme,
      owner,
      action,
      selectedIds: selectedIds,
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => AgentStorageContent._manager(
      theme: theme,
      owner: owner,
      manager: _StorageManager.memory,
    ),
  );
}

class _MemoryImportDestination extends StatefulWidget {
  const _MemoryImportDestination({
    required this.theme,
    required this.workspaces,
    required this.owner,
  });
  static const newAgent = 'new-memory-import-agent';
  final AppTheme theme;
  final AiWorkspaceProvider workspaces;
  final String owner;
  @override
  State<_MemoryImportDestination> createState() =>
      _MemoryImportDestinationState();
}

class _MemoryImportDestinationState extends State<_MemoryImportDestination> {
  late String target = widget.workspaces.find(widget.owner) != null
      ? widget.owner
      : _MemoryImportDestination.newAgent;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AppDialog(
      key: const ValueKey('storage-memory-import-destination'),
      theme: widget.theme,
      constraints: const BoxConstraints(maxWidth: 440),
      title: l.agentStorageImportMemory,
      content: SizedBox(
        width: 392,
        child: SettingsField(
          theme: widget.theme,
          title: l.agentStorageMemoryDestination,
          description: l.agentStorageMemoryDestinationHint,
          child: SettingSelect<String>(
            key: const ValueKey('storage-memory-import-target'),
            theme: widget.theme,
            value: target,
            items: [
              DropdownMenuItem(
                value: _MemoryImportDestination.newAgent,
                child: Text(l.agentStorageNewAgent),
              ),
              for (final session in widget.workspaces.sessions)
                DropdownMenuItem(
                  value: session.id,
                  child: Text(
                    '${session.id} · ${session.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => target = value);
            },
          ),
        ),
      ),
      actions: [
        AppActionButton.dialog(
          key: const ValueKey('storage-memory-import-target-cancel'),
          theme: widget.theme,
          label: l.settingsCancel,
          onPressed: () => Navigator.pop(context),
        ),
        AppActionButton.dialog(
          key: const ValueKey('storage-memory-import-target-confirm'),
          theme: widget.theme,
          primary: true,
          label: l.agentStorageImportTab,
          onPressed: () => Navigator.pop(context, target),
        ),
      ],
    );
  }
}

class _MemoryEditor extends StatefulWidget {
  const _MemoryEditor({required this.theme, required this.initial});
  final AppTheme theme;
  final String initial;
  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  late final input = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AppDialog(
      constraints: const BoxConstraints(maxWidth: 440),
      theme: widget.theme,
      title: l.agentStorageContent,
      content: SizedBox(
        width: 392,
        child: SettingControlledTextField(
          theme: widget.theme,
          controller: input,
          minLines: 3,
          maxLines: 8,
          autofocus: true,
        ),
      ),
      actions: [
        AppActionButton.dialog(
          theme: widget.theme,
          label: MaterialLocalizations.of(context).cancelButtonLabel,
          onPressed: () => Navigator.pop(context),
        ),
        AppActionButton.dialog(
          theme: widget.theme,
          label: l.aiSaveService,
          primary: true,
          onPressed: () => Navigator.pop(context, input.text),
        ),
      ],
    );
  }
}

/// 复用聊天输入区附件按钮的表面颜色和交互配色。
class _MemoryActionButton extends StatelessWidget {
  const _MemoryActionButton({
    required this.theme,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final AppTheme theme;
  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppTooltip(
    message: tooltip,
    child: Semantics(
      label: tooltip,
      button: true,
      enabled: onPressed != null,
      child: MenuItemSurface(
        theme: theme,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(15),
        child: IgnorePointer(
          child: IconButton(
            tooltip: tooltip,
            icon: icon,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              fixedSize: const Size(30, 30),
              minimumSize: const Size(30, 30),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: theme.textColorSecondary,
              shape: const CircleBorder(),
            ),
          ),
        ),
      ),
    ),
  );
}
