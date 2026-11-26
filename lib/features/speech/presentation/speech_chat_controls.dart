import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/definition.dart';
import '../../../core/theme/material_palette.dart';
import '../../../core/widgets/action_button.dart';
import '../../../core/widgets/app_scroll_behavior.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../core/widgets/dialog_style.dart';
import '../../../core/widgets/menu_item_surface.dart';
import '../../../core/widgets/popup_menu_option.dart';
import '../../../core/widgets/popup_menu_surface.dart';
import '../../../core/widgets/popup_menu_transition.dart';
import '../../../core/widgets/settings/compact_switch.dart';
import '../../../core/widgets/settings/fields.dart';
import '../../../core/widgets/settings/search_field.dart';
import '../../../core/widgets/title_bar_icon_button.dart';
import '../../settings/presentation/widgets/content_layout.dart';
import '../domain/speech_model.dart';
import '../state/speech_provider.dart';
import 'speech_labels.dart';
import 'speech_model_dialog.dart';

class SpeechChatControls extends StatefulWidget {
  const SpeechChatControls({
    super.key,
    required this.theme,
    required this.speech,
    required this.bindings,
    required this.onChanged,
    required this.compact,
    this.kinds = SpeechModelKind.values,
    this.fieldStyle = false,
  });

  final AppTheme theme;
  final SpeechProvider speech;
  final SpeechBindings bindings;
  final ValueChanged<SpeechBindings> onChanged;
  final bool compact;
  final List<SpeechModelKind> kinds;
  final bool fieldStyle;

  @override
  State<SpeechChatControls> createState() => _SpeechChatControlsState();
}

class _SpeechChatControlsState extends State<SpeechChatControls> {
  final _menu = MenuController();
  final _search = TextEditingController();
  static const _kinds = [
    SpeechModelKind.synthesis,
    SpeechModelKind.recognition,
  ];
  final _controllers = {for (final kind in _kinds) kind: MenuController()};
  bool _showingList = false;

  AppTheme get _theme => widget.theme;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String? _boundId(SpeechModelKind kind) => widget.bindings.modelIdFor(kind);

  void _select(SpeechModelKind kind, SpeechModel? model) {
    if (model != null &&
        (widget.speech.busy ||
            widget.speech.library.modelFor(kind, model.id) == null)) {
      return;
    }
    final bindings = widget.bindings;
    if (model != null) setState(() => _showingList = false);
    if (_boundId(kind) == model?.id) return;
    widget.onChanged(switch (kind) {
      .synthesis => bindings.withVoice(
        model == null ? null : (modelId: model.id, voice: 0),
      ),
      .recognition => bindings.withRecognition(model?.id),
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.speech,
    builder: (_, _) => RawMenuAnchorGroup(
      controller: _menu,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          for (final kind in widget.kinds)
            Flexible(
              child: RawMenuAnchor(
                controller: _controllers[kind]!,
                onClose: () {
                  if (mounted) {
                    setState(() {
                      _showingList = false;
                      _search.clear();
                    });
                  }
                },
                overlayBuilder: (context, info) =>
                    _buildPanel(context, info, kind),
                builder: (context, menu, _) =>
                    _buildTrigger(context, menu, kind),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildTrigger(
    BuildContext context,
    MenuController menu,
    SpeechModelKind kind,
  ) {
    final l10n = context.l10n;
    final hover = _theme.secondaryTextHoverColor;
    final library = widget.speech.library;
    final model = library.modelFor(kind, _boundId(kind));
    final kindLabel = speechKindLabel(l10n, kind);
    final label = model?.name ?? kindLabel;
    final tooltip = model == null ? kindLabel : '$kindLabel · ${model.name}';
    void toggle() => menu.isOpen ? menu.close() : menu.open();
    if (widget.fieldStyle) {
      final background = _theme.selectControlColorForSurface(
        AppDialogStyle.backgroundColor(_theme),
      );
      final fieldLabel = model?.name ??
          (kind == .synthesis ? l10n.speechNoSynthesis : l10n.speechNoRecognition);
      return AppTooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          expanded: menu.isOpen,
          label: tooltip,
          excludeSemantics: true,
          onTap: toggle,
          child: MenuItemSurface(
            key: ValueKey('speech-chat-menu-${kind.name}'),
            theme: _theme,
            backgroundColor: background,
            surfaceColor: background,
            foregroundColor: _theme.textColorSecondary,
            borderRadius: BorderRadius.circular(4),
            onPressed: toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      model == null
                          ? Symbols.block_rounded
                          : kind == .synthesis
                          ? Symbols.volume_up_rounded
                          : Symbols.mic_rounded,
                      size: 16,
                      fill: model == null ? 0 : 1,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        fieldLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    AnimatedRotation(
                      turns: menu.isOpen ? 0 : -.25,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : PopupMenuTransition.duration,
                      child: const Icon(Symbols.expand_more_rounded, size: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return AppTooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        expanded: menu.isOpen,
        label: tooltip,
        excludeSemantics: true,
        onTap: toggle,
        child: MenuItemSurface(
          key: ValueKey('speech-chat-menu-${kind.name}'),
          theme: _theme,
          backgroundColor: hover.withValues(alpha: 0),
          surfaceColor: _theme.primary,
          hoverColor: hover,
          borderRadius: BorderRadius.circular(10),
          onPressed: toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  kind == .synthesis
                      ? Symbols.volume_up_rounded
                      : Symbols.mic_rounded,
                  size: 22,
                  fill: 1,
                  color: _theme.textColorSecondary,
                ),
                if (!widget.compact) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: _theme.textColorSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: menu.isOpen ? 0 : -.25,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : PopupMenuTransition.duration,
                    child: Icon(
                      Symbols.expand_more_rounded,
                      size: 14,
                      color: _theme.textColorSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(
    BuildContext context,
    RawMenuOverlayInfo info,
    SpeechModelKind kind,
  ) {
    const gap = PopupMenuSurface.fieldAnchorGap;
    const maxPanelHeight = PopupMenuSurface.searchablePickerMaxHeight;
    final bounds =
        (const EdgeInsets.all(PopupMenuSurface.verticalInset) +
                MediaQuery.paddingOf(context) +
                MediaQuery.viewInsetsOf(context))
            .deflateRect(Offset.zero & info.overlaySize);
    if (bounds.isEmpty) return const SizedBox.shrink();
    final anchor = info.anchorRect;
    final aboveEdge = (anchor.top - gap).clamp(bounds.top, bounds.bottom);
    final belowEdge = (anchor.bottom + gap).clamp(bounds.top, bounds.bottom);
    final aboveSpace = aboveEdge - bounds.top;
    final belowSpace = bounds.bottom - belowEdge;
    final above = belowSpace < maxPanelHeight && aboveSpace > belowSpace;
    final height = (above ? aboveSpace : belowSpace).clamp(0.0, maxPanelHeight);
    final width = PopupMenuSurface.searchablePickerWidth.clamp(
      0.0,
      bounds.width,
    );
    final model = _showingList
        ? null
        : widget.speech.library.modelFor(kind, _boundId(kind));
    if (height <
        MediaQuery.textScalerOf(context).scale(model == null ? 110 : 64)) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: anchor.left.clamp(bounds.left, bounds.right - width),
      width: width,
      top: above ? null : belowEdge,
      bottom: above ? info.overlaySize.height - aboveEdge : null,
      child: TapRegion(
        groupId: info.tapRegionGroupId,
        onTapOutside: (_) => _menu.close(),
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event.logicalKey != LogicalKeyboardKey.escape) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent) _menu.close();
            return KeyEventResult.handled;
          },
          child: PopupMenuTransition(
            alignment: above ? Alignment.bottomLeft : Alignment.topLeft,
            child: PopupMenuSurface(
              key: const ValueKey('speech-chat-panel'),
              theme: _theme,
              padding: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height),
                child: PopupMenuPageTransition(
                  child: _buildPage(context, kind, model),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    SpeechModelKind kind,
    SpeechModel? model,
  ) {
    final l10n = context.l10n;
    final query = _search.text.trim().toLowerCase();
    return Column(
      key: ValueKey(model?.id),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            model == null ? 8 : 12,
            8,
            popupMenuOptionsTrailingInset,
            8,
          ),
          child: Row(
            spacing: 8,
            children: [
              if (model != null)
                AppTooltip(
                  message: l10n.back,
                  child: TitleBarIconButton(
                    key: const ValueKey('speech-chat-back'),
                    theme: _theme,
                    isFocused: true,
                    icon: Symbols.arrow_back_rounded,
                    size: 26,
                    iconSize: 16,
                    backgroundColor: PopupMenuSurface.backgroundColorFor(
                      _theme,
                    ),
                    onPressed: () => setState(() => _showingList = true),
                  ),
                ),
              Expanded(
                child: Text(
                  speechKindLabel(l10n, kind),
                  style: AppDialogStyle.fieldTitleStyle(_theme).copyWith(
                    fontWeight: FontWeight.w600,
                    color: _theme.textColorPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (model == null) ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 8),
            child: SettingSearchField(
              fieldKey: const ValueKey('speech-chat-search'),
              theme: _theme,
              controller: _search,
              hintText: l10n.speechSearchModels,
              backgroundColor: _theme.primary,
              onChanged: (_) => setState(() {}),
              onClear: () => setState(_search.clear),
            ),
          ),
        ],
        Flexible(
          child: ScrollbarTheme(
            data: ScrollbarTheme.of(
              context,
            ).copyWith(crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset),
            child: ScrollConfiguration(
              behavior: const AppScrollBehavior(),
              child: SingleChildScrollView(
                key: ValueKey((model?.id, query)),
                primary: false,
                padding: EdgeInsetsDirectional.fromSTEB(
                  model == null ? 8 : 12,
                  0,
                  popupMenuOptionsTrailingInset,
                  8,
                ),
                child: model == null
                    ? _choices(context, kind, query)
                    : _details(context, model),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _choices(BuildContext context, SpeechModelKind kind, String query) {
    final l10n = context.l10n;
    final library = widget.speech.library;
    final bound = _boundId(kind);
    final boundModel = library.modelFor(kind, bound);
    final models = library.models
        .where(
          (model) =>
              model.kind == kind &&
              (model.available || model.id == bound) &&
              model.name.toLowerCase().contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: popupMenuOptionSpacing,
      children: [
        buildPopupMenuOption(
          key: ValueKey('speech-chat-none-${kind.name}'),
          theme: _theme,
          leading: const SizedBox.square(
            dimension: 28,
            child: Icon(Symbols.block_rounded, size: 16, fill: 0),
          ),
          title: kind == .synthesis
              ? l10n.speechNoSynthesis
              : l10n.speechNoRecognition,
          description: kind == .synthesis
              ? l10n.speechNoSynthesisSummary
              : l10n.speechNoRecognitionSummary,
          uniformHeight: true,
          selected: bound == null,
          onPressed: () => _select(kind, null),
        ),
        for (final model in models) _modelOption(context, model),
        if (bound != null && boundModel == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              l10n.speechUnavailableModel,
              style: AppDialogStyle.descriptionStyle(_theme),
            ),
          ),
        if (models.isEmpty && (bound == null || boundModel != null))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              query.isEmpty ? l10n.speechNoModels : l10n.speechNoMatchingModels,
              style: AppDialogStyle.descriptionStyle(_theme),
            ),
          ),
      ],
    );
  }

  Widget _modelOption(BuildContext context, SpeechModel model) {
    final l10n = context.l10n;
    final selected = _boundId(model.kind) == model.id;
    final description = model.available
        ? speechModelSubtitle(l10n, model)
        : l10n.speechUnavailableModel;
    return AppTooltip(
      message: description,
      child: buildPopupMenuOption(
        key: ValueKey('speech-chat-model-${model.id}'),
        theme: _theme,
        leading: SpeechModelIcon(
          theme: _theme,
          kind: model.kind,
          size: 28,
          backgroundColor: selected ? _theme.primary : null,
        ),
        title: model.name,
        description: description,
        uniformHeight: true,
        selected: selected,
        next: true,
        onPressed: () => _select(model.kind, model),
      ),
    );
  }

  Widget _details(BuildContext context, SpeechModel model) {
    final l10n = context.l10n;
    final voice = widget.bindings.voice?.voice ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        SpeechModelInfo(theme: _theme, model: model),
        if (!model.available)
          Text(
            l10n.speechMissingFiles,
            style: AppDialogStyle.descriptionStyle(_theme),
          ),
        MergeSemantics(
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  model.kind == .synthesis
                      ? l10n.speechEnableSynthesis
                      : l10n.speechEnableRecognition,
                  style: AppDialogStyle.fieldTitleStyle(_theme),
                ),
              ),
              CompactSettingSwitch(
                controlKey: ValueKey('speech-chat-toggle-${model.kind.name}'),
                theme: _theme,
                surface: PopupMenuSurface.backgroundColorFor(_theme),
                value: widget.bindings.enabledFor(model.kind),
                onChanged: model.available && !widget.speech.busy
                    ? (enabled) => widget.onChanged(
                        widget.bindings.withEnabled(model.kind, enabled),
                      )
                    : null,
              ),
            ],
          ),
        ),
        if (model.available && model.kind == .recognition)
          AppActionButton(
            key: const ValueKey('speech-chat-recognition-settings'),
            theme: _theme,
            surfaceColor: PopupMenuSurface.backgroundColorFor(_theme),
            label: l10n.speechRecognitionSettings,
            icon: Symbols.tune_rounded,
            iconFill: 1,
            iconSize: 15,
            iconSpacing: 5,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            onPressed: () {
              _menu.close();
              unawaited(_editRecognitionSettings(this.context, model));
            },
          ),
        if (model.available && model.kind == .synthesis)
          AppActionButton(
            key: const ValueKey('speech-chat-voice-settings'),
            theme: _theme,
            surfaceColor: PopupMenuSurface.backgroundColorFor(_theme),
            label: l10n.speechSynthesisSettings,
            icon: Symbols.tune_rounded,
            iconFill: 1,
            iconSize: 15,
            iconSpacing: 5,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            onPressed: () {
              _menu.close();
              unawaited(_editVoice(this.context, model, voice));
            },
          ),
      ],
    );
  }

  Future<void> _editRecognitionSettings(
    BuildContext context,
    SpeechModel model,
  ) async {
    final result = await showSpeechRecognitionSettingsDialog(
      context,
      theme: _theme,
      model: model,
      initialContinuous: widget.bindings.continuousRecognition,
      initialWakeWords: widget.bindings.wakeWords,
      initialIdleTimeoutSeconds: widget.bindings.idleTimeoutSeconds,
    );
    if (!mounted ||
        result == null ||
        widget.speech.busy ||
        widget.speech.library.modelFor(model.kind, model.id) == null ||
        widget.bindings.recognitionId != model.id) {
      return;
    }
    widget.onChanged(
      widget.bindings
          .withContinuousRecognition(result.continuous)
          .withWakeWords(result.wakeWords)
          .withIdleTimeoutSeconds(result.idleTimeoutSeconds),
    );
  }

  Future<void> _editVoice(
    BuildContext context,
    SpeechModel model,
    int current,
  ) async {
    final result = await showSpeechSynthesisSettingsDialog(
      context,
      theme: _theme,
      model: model,
      currentVoice: current,
      initialAutoPlay: widget.bindings.autoPlay,
    );
    if (!mounted ||
        result == null ||
        widget.speech.busy ||
        widget.speech.library.modelFor(model.kind, model.id) == null ||
        widget.bindings.voice?.modelId != model.id) {
      return;
    }
    widget.onChanged(
      widget.bindings
          .withVoice((modelId: model.id, voice: result.voice))
          .withAutoPlay(result.autoPlay),
    );
  }
}

Future<({int voice, bool autoPlay})?> showSpeechSynthesisSettingsDialog(
  BuildContext context, {
  required AppTheme theme,
  required SpeechModel model,
  required int currentVoice,
  required bool initialAutoPlay,
}) {
  final l10n = context.l10n;
  var voice = currentVoice < model.voiceCount ? currentVoice : 0;
  var autoPlay = initialAutoPlay;
  return showDialog<({int voice, bool autoPlay})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AppDialog(
        theme: theme,
        title: l10n.speechSynthesisSettings,
        titleFontWeight: FontWeight.w500,
        constraints: const BoxConstraints(maxWidth: 540),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        content: SizedBox(
          width: 492,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                SpeechModelInfo(
                  key: const ValueKey('speech-agent-voice-model-info'),
                  theme: theme,
                  model: model,
                ),
                MergeSemantics(
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 4,
                          children: [
                            Text(
                              l10n.speechAutoRead,
                              style: AppDialogStyle.fieldTitleStyle(theme),
                            ),
                            Text(
                              l10n.speechAutoReadDescription,
                              style: AppDialogStyle.descriptionStyle(theme),
                            ),
                          ],
                        ),
                      ),
                      CompactSettingSwitch(
                        controlKey: const ValueKey('speech-chat-auto-read'),
                        theme: theme,
                        surface: AppDialogStyle.backgroundColor(theme),
                        value: autoPlay,
                        onChanged: (value) => update(() => autoPlay = value),
                      ),
                    ],
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scale =
                        MediaQuery.textScalerOf(context).scale(13) / 13;
                    final selectWidth = 220 * scale;
                    const spacing = 8.0;
                    final inline =
                        constraints.maxWidth >=
                        selectWidth + spacing + 200 * scale;
                    final select = Semantics(
                      label: l10n.speechAgentVoiceLabel,
                      child: SpeechVoiceSelect(
                        key: const ValueKey('speech-agent-voice'),
                        theme: theme,
                        model: model,
                        voice: voice,
                        onChanged: (value) {
                          if (value != null) update(() => voice = value);
                        },
                      ),
                    );
                    final field = SettingsField(
                      theme: theme,
                      title: l10n.speechAgentVoiceLabel,
                      description: l10n.speechAgentVoiceDescription,
                      child: inline ? null : select,
                    );
                    return inline
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: spacing,
                            children: [
                              Expanded(child: field),
                              SizedBox(width: selectWidth, child: select),
                            ],
                          )
                        : field;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          AppActionButton.dialog(
            theme: theme,
            label: l10n.settingsCancel,
            onPressed: () => Navigator.pop(context),
          ),
          AppActionButton.dialog(
            key: const ValueKey('speech-agent-save'),
            theme: theme,
            label: l10n.speechSave,
            primary: true,
            onPressed: () =>
                Navigator.pop(context, (voice: voice, autoPlay: autoPlay)),
          ),
        ],
      ),
    ),
  );
}

Future<({bool continuous, List<String> wakeWords, int idleTimeoutSeconds})?>
showSpeechRecognitionSettingsDialog(
  BuildContext context, {
  required AppTheme theme,
  required SpeechModel model,
  required bool initialContinuous,
  required List<String> initialWakeWords,
  int initialIdleTimeoutSeconds = defaultSpeechIdleTimeoutSeconds,
}) => showDialog<
    ({bool continuous, List<String> wakeWords, int idleTimeoutSeconds})>(
  context: context,
  builder: (_) => _RecognitionSettingsDialog(
    theme: theme,
    model: model,
    initialContinuous: initialContinuous,
    initialWakeWords: initialWakeWords,
    initialIdleTimeoutSeconds: initialIdleTimeoutSeconds,
  ),
);

class _RecognitionSettingsDialog extends StatefulWidget {
  const _RecognitionSettingsDialog({
    required this.theme,
    required this.model,
    required this.initialContinuous,
    required this.initialWakeWords,
    required this.initialIdleTimeoutSeconds,
  });

  final AppTheme theme;
  final SpeechModel model;
  final bool initialContinuous;
  final List<String> initialWakeWords;
  final int initialIdleTimeoutSeconds;

  @override
  State<_RecognitionSettingsDialog> createState() =>
      _RecognitionSettingsDialogState();
}

class _RecognitionSettingsDialogState
    extends State<_RecognitionSettingsDialog> {
  final _controller = TextEditingController();
  late final _timeoutController = TextEditingController(
    text: '${widget.initialIdleTimeoutSeconds}',
  );
  late bool _continuous = widget.initialContinuous;
  late List<String> _wakeWords = List<String>.from(widget.initialWakeWords);

  @override
  void dispose() {
    _controller.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  int _parsedTimeoutSeconds() {
    final parsed = int.tryParse(_timeoutController.text.trim());
    if (parsed == null) return widget.initialIdleTimeoutSeconds;
    return parsed < 0 ? 0 : parsed;
  }

  void _addWord() {
    final next = normalizeWakeWords([..._wakeWords, _controller.text]);
    _controller.clear();
    setState(() => _wakeWords = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = widget.theme;
    return AppDialog(
      theme: theme,
      title: l10n.speechRecognitionSettings,
      titleFontWeight: FontWeight.w500,
      constraints: const BoxConstraints(maxWidth: 540),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      content: SizedBox(
        width: 492,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              SpeechModelInfo(
                key: const ValueKey('speech-agent-recognition-model-info'),
                theme: theme,
                model: widget.model,
              ),
              MergeSemantics(
                child: Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          Text(
                            l10n.speechContinuousRecognition,
                            style: AppDialogStyle.fieldTitleStyle(theme),
                          ),
                          Text(
                            l10n.speechContinuousRecognitionDescription,
                            style: AppDialogStyle.descriptionStyle(theme),
                          ),
                        ],
                      ),
                    ),
                    CompactSettingSwitch(
                      controlKey: const ValueKey('speech-chat-continuous'),
                      theme: theme,
                      surface: AppDialogStyle.backgroundColor(theme),
                      value: _continuous,
                      onChanged: (value) => setState(() => _continuous = value),
                    ),
                  ],
                ),
              ),
              SettingsField(
                theme: theme,
                title: l10n.speechIdleTimeout,
                description: l10n.speechIdleTimeoutDescription,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: 140,
                    child: SettingControlledTextField(
                      key: const ValueKey('speech-idle-timeout-input'),
                      theme: theme,
                      controller: _timeoutController,
                      enabled: _continuous,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      maxLength: 5,
                      suffixIcon: Padding(
                        padding: const EdgeInsetsDirectional.only(end: 10),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            l10n.speechIdleTimeoutUnit,
                            style: AppDialogStyle.descriptionStyle(theme),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SettingsField(
                theme: theme,
                title: l10n.speechWakeWords,
                description: l10n.speechWakeWordsDescription,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: SettingControlledTextField(
                            key: const ValueKey('speech-wake-word-input'),
                            theme: theme,
                            controller: _controller,
                            hintText: l10n.speechWakeWordHint,
                            onSubmitted: (_) => _addWord(),
                          ),
                        ),
                        AppActionButton.settings(
                          key: const ValueKey('speech-wake-word-add'),
                          theme: theme,
                          label: l10n.speechAddWakeWord,
                          onPressed: _addWord,
                        ),
                      ],
                    ),
                    if (_wakeWords.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final word in _wakeWords)
                            _wakeWordChip(
                              theme,
                              word,
                              onRemove: () => setState(
                                () => _wakeWords = _wakeWords
                                    .where((item) => item != word)
                                    .toList(),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppActionButton.dialog(
          theme: theme,
          label: l10n.settingsCancel,
          onPressed: () => Navigator.pop(context),
        ),
        AppActionButton.dialog(
          key: const ValueKey('speech-recognition-save'),
          theme: theme,
          label: l10n.speechSave,
          primary: true,
          onPressed: () => Navigator.pop(context, (
            continuous: _continuous,
            wakeWords: _wakeWords,
            idleTimeoutSeconds: _parsedTimeoutSeconds(),
          )),
        ),
      ],
    );
  }
}

Widget _wakeWordChip(
  AppTheme theme,
  String word, {
  required VoidCallback onRemove,
}) {
  final chipColor = AppDialogStyle.neutralButtonColor(
    theme,
    AppDialogStyle.backgroundColor(theme),
  );
  return DecoratedBox(
    decoration: BoxDecoration(
      color: chipColor,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 4, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Flexible(
            child: Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: theme.textColorPrimary),
            ),
          ),
          MenuItemSurface(
            key: ValueKey('speech-wake-word-remove-$word'),
            theme: theme,
            onPressed: onRemove,
            backgroundColor: chipColor.withValues(alpha: 0),
            surfaceColor: chipColor,
            hoverColor: theme.hoverColorForBackground(chipColor),
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 20,
              height: 20,
              child: Icon(
                Symbols.close,
                size: 13,
                color: theme.textColorSecondary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
