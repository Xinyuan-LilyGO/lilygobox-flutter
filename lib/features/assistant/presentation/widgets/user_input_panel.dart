/*
 * @Description: 在聊天输入区展示问题、选项及自填答案，并回传用户选择。
 */

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../../../core/widgets/settings/fields.dart';
import '../../domain/user_input.dart';

/// 提问与批准共用输入区的位置；草稿由外部控制器保留。
class AssistantUserInputPanel extends StatefulWidget {
  const AssistantUserInputPanel({
    super.key,
    required this.request,
    required this.theme,
    required this.inputFocus,
    required this.onSubmit,
    required this.onCancel,
  });

  final AiUserInputRequest request;
  final AppTheme theme;
  final FocusNode inputFocus;
  final ValueChanged<Map<String, List<String>>> onSubmit;
  final VoidCallback onCancel;

  @override
  State<AssistantUserInputPanel> createState() =>
      _AssistantUserInputPanelState();
}

class _AssistantUserInputPanelState extends State<AssistantUserInputPanel> {
  final _scroll = ScrollController();
  final _selected = <String, String>{};
  late final Map<String, TextEditingController> _notes;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _notes = {
      for (final question in widget.request.questions)
        question.id: TextEditingController(),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.inputFocus.unfocus();
    });
  }

  @override
  void dispose() {
    for (final controller in _notes.values) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitted &&
      widget.request.questions.every(
        (question) =>
            _selected.containsKey(question.id) ||
            _notes[question.id]!.text.trim().isNotEmpty,
      );

  void _submit() {
    if (!_canSubmit) return;
    final answers = {
      for (final question in widget.request.questions)
        question.id: [
          if (_selected[question.id] case final choice?) choice,
          if (_notes[question.id]!.text.trim().isNotEmpty)
            _notes[question.id]!.text.trim(),
        ],
    };
    setState(() => _submitted = true);
    widget.onSubmit(answers);
  }

  Widget _question(BuildContext context, AiUserInputQuestion question) {
    final theme = widget.theme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(question.header, style: AppDialogStyle.fieldTitleStyle(theme)),
        const SizedBox(height: 4),
        SelectableText(
          question.question,
          style: AppDialogStyle.descriptionStyle(theme),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < question.options.length; index++) ...[
          if (index > 0) const SizedBox(height: 4),
          Builder(
            builder: (context) {
              final option = question.options[index];
              final selected = _selected[question.id] == option.label;
              return Semantics(
                checked: selected,
                inMutuallyExclusiveGroup: true,
                child: MenuItemSurface(
                  key: ValueKey('ai-question-option-${question.id}-$index'),
                  theme: theme,
                  isSelected: selected,
                  disableWhenSelected: false,
                  backgroundColor: theme.primary,
                  selectedColor: theme.primaryTextHoverColor,
                  hoverColor: theme.basePrimary,
                  foregroundColor: selected
                      ? theme.type == ThemeType.light
                            ? Colors.black
                            : theme.materialColors.onPrimary
                      : theme.textColorSecondary,
                  hoverForegroundColor: theme.materialColors.onPrimary,
                  onPressed: _submitted
                      ? null
                      : () => setState(() {
                          if (selected) {
                            _selected.remove(question.id);
                          } else {
                            _selected[question.id] = option.label;
                          }
                        }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          selected
                              ? Symbols.radio_button_checked_rounded
                              : Symbols.radio_button_unchecked_rounded,
                          size: 17,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Builder(
                                builder: (context) => Text(
                                  option.label,
                                  style: AppDialogStyle.fieldTitleStyle(theme)
                                      .copyWith(
                                        color: DefaultTextStyle.of(
                                          context,
                                        ).style.color,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Builder(
                                builder: (context) {
                                  final foreground = DefaultTextStyle.of(
                                    context,
                                  ).style.color;
                                  return Text(
                                    option.description,
                                    style:
                                        AppDialogStyle.descriptionStyle(
                                          theme,
                                        ).copyWith(
                                          color:
                                              foreground ==
                                                  theme.textColorSecondary
                                              ? theme.textColorTertiary
                                              : foreground,
                                        ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 8),
        Text(
          l10n.aiQuestionNote,
          style: AppDialogStyle.descriptionStyle(theme),
        ),
        const SizedBox(height: 4),
        Semantics(
          label: '${question.header} · ${l10n.aiQuestionNote}',
          child: SettingControlledTextField(
            key: ValueKey('ai-question-note-${question.id}'),
            theme: theme,
            controller: _notes[question.id]!,
            enabled: !_submitted,
            maxLines: 4,
            maxLength: 16000,
            inputFormatters: [
              // 协议按 UTF-16 长度校验；拒绝超长增量，不截断代理对。
              TextInputFormatter.withFunction(
                (oldValue, newValue) =>
                    newValue.text.length <= 16000 ? newValue : oldValue,
              ),
            ],
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableHeight = constraints.hasBoundedHeight
          ? constraints.maxHeight
          : MediaQuery.sizeOf(context).height;
      // 单题按实际内容增高，只有内容超过可用区域时才需要滚动。
      return _buildPanel(context, math.max(0, availableHeight * .8 - 42));
    },
  );

  Widget _buildPanel(BuildContext context, double maxContentHeight) {
    final theme = widget.theme;
    final l10n = context.l10n;
    return DecoratedBox(
      key: const ValueKey('ai-user-input-panel'),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          theme.primary.withValues(alpha: .42),
          theme.secondary,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: PopupMenuSurface.shadowsFor(theme),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.primary,
            borderRadius: BorderRadius.circular(17),
          ),
          child: AppDialogScope(
            surfaceColor: theme.primary,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxContentHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(
                            Symbols.help_rounded,
                            fill: 1,
                            size: 20,
                            color: theme.textColorPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.aiQuestionTitle,
                              style: TextStyle(
                                color: theme.textColorPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ScrollbarTheme(
                        data: ScrollbarTheme.of(context).copyWith(
                          crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                        ),
                        child: Scrollbar(
                          key: const ValueKey('ai-user-input-scrollbar'),
                          controller: _scroll,
                          child: ScrollConfiguration(
                            behavior: const AppScrollBehavior(
                              scrollbars: false,
                            ),
                            child: SingleChildScrollView(
                              key: const ValueKey('ai-user-input-scroll'),
                              controller: _scroll,
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (
                                    var index = 0;
                                    index < widget.request.questions.length;
                                    index++
                                  ) ...[
                                    if (index > 0) const SizedBox(height: 16),
                                    _question(
                                      context,
                                      widget.request.questions[index],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          AppActionButton.dialog(
                            key: const ValueKey('ai-user-input-cancel'),
                            theme: theme,
                            label: l10n.aiQuestionCancel,
                            onPressed: _submitted ? null : widget.onCancel,
                          ),
                          AppActionButton.dialog(
                            key: const ValueKey('ai-user-input-submit'),
                            theme: theme,
                            label: l10n.aiQuestionSubmit,
                            primary: true,
                            onPressed: _canSubmit ? _submit : null,
                          ),
                        ],
                      ),
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
}
