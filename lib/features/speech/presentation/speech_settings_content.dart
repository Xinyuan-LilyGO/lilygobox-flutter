/*
 * @Description: 提供设置中的离线语音模型库和音色试听。
 */

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/files/zstd_file.dart';
import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/definition.dart';
import '../../../core/widgets/action_button.dart';
import '../../../core/widgets/app_notice.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../core/widgets/dialog_style.dart';
import '../../../core/widgets/settings/select.dart';
import '../../settings/presentation/widgets/content_layout.dart';
import '../domain/speech_model.dart';
import '../state/speech_provider.dart';
import 'speech_labels.dart';

class SpeechSettingsContent extends StatefulWidget {
  const SpeechSettingsContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<SpeechSettingsContent> createState() => _SpeechSettingsContentState();
}

class _SpeechSettingsContentState extends State<SpeechSettingsContent> {
  final _previewOwner = Object();
  SpeechProvider? _speech;
  String? _previewId;
  bool _pickingFile = false;

  AppTheme get theme => widget.theme;

  @override
  void dispose() {
    final speech = _speech;
    scheduleMicrotask(() => speech?.stopPlayback(_previewOwner));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speech = context.watch<SpeechProvider>();
    _speech = speech;
    final l10n = context.l10n;
    final synthesis = speech.library.selectedModel(.synthesis);
    return SettingsContentLayout(
      theme: theme,
      title: l10n.speechTitle,
      description: l10n.speechDescription,
      children: [
        SettingsCollectionHeader(
          theme: theme,
          title: l10n.speechLibraryTitle,
          description: l10n.speechLibraryDescription,
          actionKey: const ValueKey('speech-import'),
          actionLabel: l10n.speechImport,
          onAction: speech.busy || !speech.loaded || _pickingFile
              ? null
              : () => unawaited(_import(speech)),
        ),
        const SizedBox(height: 12),
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
          for (final kind in SpeechModelKind.values) ...[
            SettingsCollectionHeader(
              theme: theme,
              title: kind == .recognition
                  ? l10n.speechRecognition
                  : l10n.speechSynthesis,
              description: kind == .recognition
                  ? l10n.speechRecognitionFormat
                  : l10n.speechSynthesisFormat,
            ),
            const SizedBox(height: 8),
            if (!speech.library.models.any((model) => model.kind == kind))
              Text(
                l10n.speechNoModels,
                style: AppDialogStyle.descriptionStyle(theme),
              ),
            for (final model in speech.library.models.where(
              (model) => model.kind == kind,
            ))
              _modelRow(speech, model),
            const SizedBox(height: 14),
          ],
          if (synthesis != null)
            SettingsSection(
              theme: theme,
              title: l10n.speechDefaultVoice,
              description: synthesis.name,
              child: SettingSelect<int>(
                theme: theme,
                value: speech.library.voice,
                surfaceColor: theme.primary,
                items: [
                  for (var voice = 0; voice < synthesis.voiceCount; voice++)
                    DropdownMenuItem(
                      value: voice,
                      child: Text(l10n.speechVoiceNumber(voice + 1)),
                    ),
                ],
                onChanged: speech.busy || _pickingFile
                    ? null
                    : (voice) {
                        if (voice == null) return;
                        unawaited(_report(speech.selectVoice(voice)));
                      },
              ),
            ),
        ],
      ],
    );
  }

  Widget _modelRow(SpeechProvider speech, SpeechModel model) {
    final l10n = context.l10n;
    final selected = speech.library.selectedId(model.kind) == model.id;
    final playing = _previewId == model.id && speech.isPlaying(_previewOwner);
    final blocked = speech.busy || _pickingFile;
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 6,
      children: [
        if (model.kind == .synthesis)
          AppActionButton.compact(
            key: ValueKey('speech-preview-${model.id}'),
            theme: theme,
            label: playing ? l10n.speechStopPlayback : l10n.speechPreview,
            onPressed: playing
                ? () => speech.stopPlayback(_previewOwner)
                : blocked || !model.available
                ? null
                : () {
                    _previewId = model.id;
                    unawaited(
                      _report(
                        speech.play(
                          _previewOwner,
                          l10n.speechPreviewText,
                          model: model,
                        ),
                      ),
                    );
                  },
          ),
        if (!selected)
          AppActionButton.compact(
            theme: theme,
            label: l10n.speechSelectDefault,
            onPressed: blocked || !model.available
                ? null
                : () => unawaited(_report(speech.select(model))),
          ),
        AppActionButton.compact(
          key: ValueKey('speech-export-${model.id}'),
          theme: theme,
          label: l10n.speechExport,
          onPressed: blocked || !model.available
              ? null
              : () => unawaited(_export(speech, model)),
        ),
        AppActionButton.compact(
          key: ValueKey('speech-delete-${model.id}'),
          theme: theme,
          label: l10n.delete,
          destructive: true,
          onPressed: blocked ? null : () => unawaited(_delete(speech, model)),
        ),
      ],
    );
    final details = Row(
      spacing: 10,
      children: [
        Icon(
          model.kind == .recognition
              ? Symbols.mic_rounded
              : Symbols.volume_up_rounded,
          size: 20,
          fill: 1,
          color: theme.textColorSecondary,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: [
              Text(model.name, style: AppDialogStyle.fieldTitleStyle(theme)),
              Text(
                !model.available
                    ? l10n.speechMissingFiles
                    : selected
                    ? l10n.speechCurrentDefault
                    : l10n.speechModelReady,
                style: AppDialogStyle.descriptionStyle(theme),
              ),
            ],
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SettingsPanel(
        theme: theme,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth <
                  620 * MediaQuery.textScalerOf(context).scale(1)
              ? Column(
                  spacing: 8,
                  children: [
                    details,
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: actions,
                    ),
                  ],
                )
              : Row(
                  spacing: 12,
                  children: [
                    Expanded(flex: 2, child: details),
                    Flexible(flex: 3, child: actions),
                  ],
                ),
        ),
      ),
    );
  }

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
      await _report(speech.import(source.path), success: l10n.speechImported);
    } catch (_) {
      if (mounted) _notice(l10n.speechStorageError);
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  Future<void> _export(SpeechProvider speech, SpeechModel model) async {
    if (_pickingFile || speech.busy) return;
    final l10n = context.l10n;
    setState(() => _pickingFile = true);
    try {
      final destination = await getSaveLocation(
        suggestedName: speech.exportFileName(model),
        acceptedTypeGroups: [ZstdFile.typeGroup(l10n.speechZstdType)],
      );
      if (destination == null || !mounted) return;
      await _report(
        speech.export(model, destination.path),
        success: l10n.speechExported,
      );
    } catch (_) {
      if (mounted) _notice(l10n.speechExportFailed);
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  Future<void> _delete(SpeechProvider speech, SpeechModel model) async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirmation(
      context: context,
      theme: theme,
      actionKey: 'speech-delete',
      title: l10n.speechDeleteTitle(model.name),
      description: l10n.speechDeleteDescription,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (mounted && confirmed) await _report(speech.delete(model));
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
