/*
 * @Description: 提供设置中的离线语音模型库和音色试听。
 */

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/files/export_file_name.dart';
import '../../../core/files/package_transfer.dart';
import '../../../core/files/zstd_file.dart';
import '../../../core/files/zstd_tar.dart';
import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/definition.dart';
import '../../../core/widgets/action_button.dart';
import '../../../core/widgets/app_notice.dart';
import '../../../core/widgets/card_transfer_dialog.dart';
import '../../../core/widgets/desktop_card_selection.dart';
import '../../../core/widgets/dialog_style.dart';
import '../../../core/widgets/library_delete_dialog.dart';
import '../../../core/widgets/package_transfer_progress_dialog.dart';
import '../../assistant/state/agent_workspace_provider.dart';
import '../../settings/presentation/widgets/content_layout.dart';
import '../domain/speech_model.dart';
import '../state/speech_provider.dart';
import 'speech_labels.dart';
import 'speech_model_dialog.dart';

class SpeechSettingsContent extends StatefulWidget {
  const SpeechSettingsContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<SpeechSettingsContent> createState() => _SpeechSettingsContentState();
}

class _SpeechSettingsContentState extends State<SpeechSettingsContent> {
  final _selection = DesktopCardSelection();
  final _selectionFocus = FocusNode();
  bool _pickingFile = false;

  AppTheme get theme => widget.theme;

  @override
  void dispose() {
    _selectionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speech = context.watch<SpeechProvider>();
    final l10n = context.l10n;
    final usage = context.select<AiWorkspaceProvider?, Map<String, int>>(
      (workspaces) => workspaces?.speechLibraryUsage ?? const {},
    );
    final canDelete = context.select<AiWorkspaceProvider?, bool>(
      (workspaces) => workspaces?.canDeleteSpeechModel ?? true,
    );
    final models = speech.library.models;
    final ids = [for (final model in models) model.id];
    _selection.retain(ids);
    final exportable = models.where((model) => model.available).toList();
    final blocked = speech.busy || !speech.loaded || _pickingFile;
    final canDeleteSelected =
        !blocked && canDelete && _selection.selected.isNotEmpty;
    void deleteSelected() => unawaited(
      _delete(speech, [
        for (final model in models)
          if (_selection.selected.contains(model.id)) model,
      ], batch: true),
    );
    return DesktopCardSelectionRegion(
      focusNode: _selectionFocus,
      selection: _selection,
      ids: ids,
      enabled: !blocked,
      onChanged: () => setState(() {}),
      onDelete: canDeleteSelected ? deleteSelected : null,
      child: SettingsContentLayout(
        theme: theme,
        title: l10n.speechTitle,
        description: l10n.speechDescription,
        children: [
          DesktopCardSelectionTarget(
            child: SettingsSection(
              theme: theme,
              title: l10n.speechLibraryTitle,
              description: l10n.speechLibraryDescription,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppActionButton.settings(
                    key: const ValueKey('speech-export'),
                    theme: theme,
                    label: l10n.speechExport,
                    onPressed: blocked || exportable.isEmpty
                        ? null
                        : () => unawaited(_export(speech, exportable, usage)),
                  ),
                  AppActionButton.settings(
                    key: const ValueKey('speech-import'),
                    theme: theme,
                    label: l10n.speechImport,
                    onPressed: blocked
                        ? null
                        : () => unawaited(_import(speech)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (!speech.loaded) ...[
            Text(
              speech.busy ? l10n.speechLoading : l10n.speechStorageError,
              style: AppDialogStyle.descriptionStyle(theme),
            ),
            if (!speech.busy)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: AppActionButton.settings(
                  theme: theme,
                  label: l10n.preferencesRetry,
                  onPressed: () => unawaited(speech.load()),
                ),
              ),
          ] else ...[
            if (speech.busy) ...[
              Text(
                l10n.speechLoading,
                style: AppDialogStyle.descriptionStyle(theme),
              ),
              const SizedBox(height: 8),
            ],
            DesktopCardSelectionTarget(
              child: SettingsCollectionHeader(
                theme: theme,
                title: l10n.speechImportedModels,
                description: l10n.speechImportedModelsDescription,
                extraAction: Visibility(
                  visible: _selection.selected.isNotEmpty,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: AppActionButton.compact(
                    key: _selection.selected.isEmpty
                        ? null
                        : const ValueKey('speech-delete-selected'),
                    theme: theme,
                    label: l10n.settingsDeleteSelected(
                      _selection.selected.length,
                    ),
                    destructive: true,
                    onPressed: canDeleteSelected ? deleteSelected : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (models.isEmpty)
              Text(
                l10n.speechNoModels,
                style: AppDialogStyle.descriptionStyle(theme),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  for (final model in models)
                    _modelRow(speech, model, usage[model.id] ?? 0, canDelete),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _modelRow(
    SpeechProvider speech,
    SpeechModel model,
    int boundCount,
    bool canDelete,
  ) {
    final l10n = context.l10n;
    final blocked = speech.busy || _pickingFile;
    return DesktopSelectableCard(
      key: ValueKey(model.id),
      id: model.id,
      theme: theme,
      child: SettingsLibraryCard(
        key: ValueKey('speech-model-${model.id}'),
        theme: theme,
        details: SpeechModelInfo(
          theme: theme,
          model: model,
          boundCount: boundCount,
        ),
        actions: [
          AppActionButton(
            key: ValueKey('speech-details-${model.id}'),
            theme: theme,
            label: l10n.speechViewDetails,
            onPressed: blocked ? null : () => unawaited(_view(speech, model)),
          ),
          AppActionButton(
            key: ValueKey('speech-delete-${model.id}'),
            theme: theme,
            label: l10n.delete,
            destructive: true,
            icon: Symbols.delete_outline_rounded,
            iconSize: 16,
            iconSpacing: 6,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            onPressed: blocked || !canDelete
                ? null
                : () => unawaited(_delete(speech, [model])),
          ),
        ],
      ),
    );
  }

  Future<void> _view(SpeechProvider speech, SpeechModel model) =>
      showDialog<void>(
        context: context,
        builder: (_) =>
            SpeechModelDialog(theme: theme, speech: speech, model: model),
      );

  Future<void> _import(SpeechProvider speech) async {
    if (_pickingFile || speech.busy) return;
    final l10n = context.l10n;
    setState(() => _pickingFile = true);
    try {
      final source = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: l10n.speechArchiveTypes,
            extensions: const ['bz2', ZstdFile.extension],
            mimeTypes: const ['application/x-bzip2', ZstdFile.mimeType],
            uniformTypeIdentifiers: const [
              'public.bzip2-archive',
              ZstdFile.uniformTypeIdentifier,
            ],
          ),
        ],
      );
      if (source == null || !mounted) return;
      await _report(
        showLibraryTransferProgress(
          context: context,
          theme: theme,
          work: (transfer) => speech.import(source.path, transfer: transfer),
        ),
        success: l10n.speechImported,
      );
    } on PackageCancelled {
      if (mounted) _notice(l10n.agentStorageTransferCancelled);
    } catch (_) {
      if (mounted) _notice(l10n.speechStorageError);
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  Future<void> _export(
    SpeechProvider speech,
    List<SpeechModel> models,
    Map<String, int> usage,
  ) async {
    if (_pickingFile || speech.busy) return;
    final l10n = context.l10n;
    setState(() => _pickingFile = true);
    try {
      final selected = await showDialog<List<SpeechModel>>(
        context: context,
        builder: (_) => CardTransferDialog<SpeechModel>(
          theme: theme,
          title: l10n.speechExport,
          description: l10n.speechExportSelection,
          items: models,
          idOf: (model) => model.id,
          buildInfo: (model) => SpeechModelInfo(
            theme: theme,
            model: model,
            boundCount: usage[model.id] ?? 0,
            iconBackground: theme.primary,
          ),
          confirmLabel: l10n.speechExportSelected,
          keyPrefix: 'speech-package',
        ),
      );
      if (selected == null || !mounted) return;
      final destination = await getSaveLocation(
        suggestedName: datedExportFileName(
          'lilygobox-voice-model-package${ZstdTar.suffix}',
          suffix: ZstdTar.suffix,
        ),
        acceptedTypeGroups: [ZstdFile.typeGroup(l10n.speechZstdType)],
      );
      if (destination == null || !mounted) return;
      await _report(
        showLibraryTransferProgress(
          context: context,
          theme: theme,
          work: (transfer) =>
              speech.export(selected, destination.path, transfer: transfer),
        ),
        success: l10n.speechExported,
      );
    } on PackageCancelled {
      if (mounted) _notice(l10n.agentStorageTransferCancelled);
    } catch (_) {
      if (mounted) _notice(l10n.speechExportFailed);
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  Future<void> _delete(
    SpeechProvider speech,
    List<SpeechModel> models, {
    bool batch = false,
  }) async {
    if (models.isEmpty || speech.busy || _pickingFile) return;
    final l10n = context.l10n;
    final workspaces = context.read<AiWorkspaceProvider?>();
    final confirmedUsage = {
      for (final model in models)
        model:
            workspaces?.speechModelAgents(model) ??
            const <AiSpeechLibraryAgent>[],
    };
    final agents = confirmedUsage.values.expand((agents) => agents).toSet();
    final confirmed = await showLibraryDeleteDialog(
      context: context,
      theme: theme,
      actionKey: 'speech-delete',
      title: batch
          ? l10n.settingsDeleteSelected(models.length)
          : agents.isEmpty
          ? l10n.speechDeleteTitle(models.single.name)
          : l10n.aiRoleplayLibraryDeleteBoundTitle(
              models.single.name,
              agents.length,
            ),
      description: agents.isEmpty
          ? l10n.speechDeleteDescription
          : l10n.speechDeleteBoundDescription,
      agents: agents,
      items: batch
          ? (
              title: l10n.speechDeleteModelsHeading(models.length),
              names: [for (final model in models) model.name],
            )
          : null,
      confirmLabel: agents.isEmpty
          ? l10n.delete
          : l10n.aiRoleplayLibraryDeleteAndUnbind,
    );
    if (!mounted || confirmed != true) return;
    if (speech.busy || !models.every(speech.library.models.contains)) {
      _notice(l10n.speechDeleteUnavailable);
      return;
    }
    final ids = {for (final model in models) model.id};
    Future<bool> removeModels() async {
      final error = await speech.deleteModels(ids);
      if (error != null && mounted) {
        _notice(speechErrorLabel(context.l10n, error));
      }
      return error == null &&
          !speech.library.models.any((model) => ids.contains(model.id));
    }

    if (workspaces == null) {
      await removeModels();
    } else if (!await workspaces.deleteSpeechModels(
          confirmedUsage,
          removeModels: removeModels,
        ) &&
        mounted) {
      _notice(
        workspaces.canDeleteSpeechModel
            ? l10n.speechDeleteBindingsChanged
            : l10n.speechDeleteUnavailable,
      );
    }
  }

  Future<void> _report(
    Future<SpeechFailureReason?> pending, {
    String? success,
  }) async {
    final error = await pending;
    if (!mounted) return;
    if (error != null) {
      _notice(speechErrorLabel(context.l10n, error));
    } else if (success != null) {
      _notice(success);
    }
  }

  void _notice(String message) =>
      showAppNotice(ScaffoldMessenger.of(context), message);
}
