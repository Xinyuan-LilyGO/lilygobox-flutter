/*
 * @Description: 提供语音模型信息、音色选择控件和试听弹窗。
 */

import 'dart:async';

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/definition.dart';
import '../../../core/widgets/action_button.dart';
import '../../../core/widgets/app_notice.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../core/widgets/dialog_style.dart';
import '../../../core/widgets/settings/fields.dart';
import '../../../core/widgets/settings/select.dart';
import '../../settings/presentation/widgets/content_layout.dart';
import '../domain/speech_model.dart';
import '../state/speech_provider.dart';
import 'speech_labels.dart';

class SpeechModelInfo extends StatelessWidget {
  const SpeechModelInfo({
    super.key,
    required this.theme,
    required this.model,
    this.boundCount,
    this.iconBackground,
  });

  final AppTheme theme;
  final SpeechModel model;
  final int? boundCount;
  final Color? iconBackground;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final compact = boundCount != null;
    final subtitle = compact && !model.available
        ? l10n.speechUnavailableModel
        : speechModelSubtitle(l10n, model);
    final title = Text(
      model.name,
      maxLines: compact ? 1 : null,
      overflow: compact ? TextOverflow.ellipsis : TextOverflow.clip,
      style: AppDialogStyle.titleStyle(theme).copyWith(fontSize: 15),
    );
    return Row(
      spacing: 10,
      children: [
        SpeechModelIcon(
          theme: theme,
          kind: model.kind,
          backgroundColor: iconBackground,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              if (compact)
                AppTooltip(message: model.name, child: title)
              else
                title,
              Text(subtitle, style: AppDialogStyle.descriptionStyle(theme)),
              if (boundCount case final count?)
                Text(
                  l10n.aiRoleplayLibraryBoundCount(count),
                  style: AppDialogStyle.descriptionStyle(theme),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SpeechModelIcon extends StatelessWidget {
  const SpeechModelIcon({
    super.key,
    required this.theme,
    required this.kind,
    this.size = 36,
    this.backgroundColor,
  });

  final AppTheme theme;
  final SpeechModelKind kind;
  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor ?? theme.secondary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          kind == .recognition
              ? Symbols.mic_rounded
              : Symbols.volume_up_rounded,
          size: size * .65,
          fill: 1,
          color: theme.textColorSecondary,
        ),
      ),
    ),
  );
}

class SpeechVoiceSelect extends StatelessWidget {
  const SpeechVoiceSelect({
    super.key,
    required this.theme,
    required this.model,
    required this.voice,
    required this.onChanged,
  });

  final AppTheme theme;
  final SpeechModel model;
  final int voice;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) => SettingSelect<int>(
    theme: theme,
    value: voice,
    surfaceColor: AppDialogStyle.backgroundColor(theme),
    items: [
      for (var index = 0; index < model.voiceCount; index++)
        DropdownMenuItem(
          value: index,
          child: Text(speechVoiceLabel(context.l10n, model, index)),
        ),
    ],
    onChanged: onChanged,
  );
}

class SpeechModelDialog extends StatefulWidget {
  const SpeechModelDialog({
    super.key,
    required this.theme,
    required this.speech,
    required this.model,
  });

  final AppTheme theme;
  final SpeechProvider speech;
  final SpeechModel model;

  @override
  State<SpeechModelDialog> createState() => _SpeechModelDialogState();
}

class _SpeechModelDialogState extends State<SpeechModelDialog> {
  final _previewOwner = Object();
  final _recognitionTestOwner = SpeechConversation();
  final _transcript = TextEditingController();
  int _voice = 0;
  SpeechFailureReason? _recognitionError;

  @override
  void dispose() {
    final speech = widget.speech;
    scheduleMicrotask(() {
      speech.stopPlayback(_previewOwner);
      speech.stopConversation(_recognitionTestOwner);
    });
    _transcript.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.speech,
    builder: (context, _) {
      final l10n = context.l10n;
      final theme = widget.theme;
      final speech = widget.speech;
      final model = widget.model;
      final canPreview = model.kind == .synthesis && model.available;
      final canTestRecognition = model.kind == .recognition && model.available;
      final playing = speech.isPlaying(_previewOwner);
      final capturePhase = speech.capturePhase(_recognitionTestOwner);
      return AppDialog(
        theme: theme,
        title: l10n.speechTitle,
        constraints: const BoxConstraints(maxWidth: 480),
        content: SizedBox(
          width: 432,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                SpeechModelInfo(theme: theme, model: model),
                Text(
                  model.available
                      ? speechFormatLabel(l10n, model.format)
                      : l10n.speechMissingFiles,
                  style: AppDialogStyle.descriptionStyle(theme),
                ),
                if (canPreview)
                  SettingsField(
                    theme: theme,
                    title: l10n.speechPreviewVoice,
                    description: l10n.speechPreviewVoiceDescription,
                    child: SpeechVoiceSelect(
                      key: const ValueKey('speech-preview-voice'),
                      theme: theme,
                      model: model,
                      voice: _voice,
                      onChanged: speech.busy
                          ? null
                          : (value) {
                              if (value == null || value == _voice) return;
                              speech.stopPlayback(_previewOwner);
                              setState(() => _voice = value);
                            },
                    ),
                  ),
                if (canTestRecognition) ...[
                  SettingsField(
                    theme: theme,
                    title: l10n.speechTestRecognition,
                    description: l10n.speechTestRecognitionDescription,
                    child: Semantics(
                      label: l10n.speechTestTranscript,
                      child: SettingControlledTextField(
                        key: const ValueKey('speech-recognition-test-result'),
                        theme: theme,
                        controller: _transcript,
                        hintText: l10n.speechTestTranscript,
                        minLines: 3,
                        maxLines: 5,
                        readOnly: capturePhase != null,
                      ),
                    ),
                  ),
                  if (_recognitionError case final error?)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        speechErrorLabel(l10n, error),
                        style: AppDialogStyle.descriptionStyle(theme),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          AppActionButton.dialog(
            key: const ValueKey('speech-model-close'),
            theme: theme,
            label: l10n.close,
            onPressed: () => Navigator.pop(context),
          ),
          if (canTestRecognition)
            AppActionButton.dialog(
              key: ValueKey('speech-recognition-test-${model.id}'),
              theme: theme,
              label: switch (capturePhase) {
                .recording => l10n.speechStopRecording,
                .transcribing => l10n.speechTranscribing,
                .starting => l10n.speechStartingRecording,
                null => l10n.speechStartRecording,
              },
              primary: true,
              onPressed: switch (capturePhase) {
                .recording => () => speech.finishRecording(
                  _recognitionTestOwner,
                ),
                .starting || .transcribing => null,
                null when speech.busy || speech.hasCapture => null,
                null => () => unawaited(_testRecognition(model)),
              },
            ),
          if (canPreview)
            AppActionButton.dialog(
              key: ValueKey('speech-preview-${model.id}'),
              theme: theme,
              label: playing ? l10n.speechStopPlayback : l10n.speechPreview,
              primary: true,
              onPressed: playing
                  ? () => speech.stopPlayback(_previewOwner)
                  : speech.busy || speech.hasCapture
                  ? null
                  : () => unawaited(
                      _report(
                        speech.play(
                          _previewOwner,
                          model.format == .kokoroMultiLanguage
                              ? l10n.speechKokoroPreviewText
                              : l10n.speechPreviewText,
                          selection: (modelId: model.id, voice: _voice),
                        ),
                      ),
                    ),
            ),
        ],
      );
    },
  );

  Future<void> _report(Future<SpeechFailureReason?> pending) async {
    final error = await pending;
    if (!mounted || error == null) return;
    showAppNotice(
      ScaffoldMessenger.of(context),
      speechErrorLabel(context.l10n, error),
    );
  }

  Future<void> _testRecognition(SpeechModel model) async {
    setState(() => _recognitionError = null);
    final draft = _transcript.text;
    final separator = draft.trimRight().length == draft.length ? '\n' : '';
    void updateTranscript(String text) {
      if (!mounted) return;
      final value = draft.isEmpty || text.isEmpty
          ? '$draft$text'
          : '$draft$separator$text';
      if (_transcript.text == value) return;
      _transcript.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }

    final result = await widget.speech.startRecording(
      _recognitionTestOwner,
      modelId: model.id,
      onPartial: updateTranscript,
    );
    if (!mounted) return;
    if (result.text case final text?) updateTranscript(text);
    if (result.error case final error?) {
      setState(() => _recognitionError = error);
    }
  }
}
