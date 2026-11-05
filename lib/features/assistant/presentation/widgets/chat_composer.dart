/*
 * @Description: 构建双层 AI 输入区，预留附件承载层并提供键盘发送和模型选择菜单。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 11:07:40
 * @LastEditTime: 2026-11-04 16:34:42
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../state/provider.dart';
import 'model_selector.dart';

/// 后层独立于编辑器，后续可在它的顶部插入附件列表而不改变输入交互。
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.input,
    required this.focusNode,
    required this.theme,
    required this.assistant,
    required this.ready,
    required this.onSend,
  });

  final TextEditingController input;
  final FocusNode focusNode;
  final AppTheme theme;
  final AiAssistantProvider assistant;
  final bool ready;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      key: const ValueKey('ai-composer-context-layer'),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          theme.primary.withValues(alpha: .42),
          theme.secondary,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedBuilder(
              animation: focusNode,
              builder: (context, child) => AnimatedContainer(
                key: const ValueKey('ai-composer-input-layer'),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: theme.primary,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: focusNode.hasFocus
                        ? theme.basePrimary
                        : Colors.transparent,
                  ),
                ),
                child: child,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 10, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Focus(
                      onKeyEvent: (_, event) {
                        // 不截获输入法候选确认，也不改变 Shift+Enter 换行行为。
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed &&
                            input.value.composing.isCollapsed) {
                          if (assistant.canChangeService &&
                              input.text.trim().isNotEmpty) {
                            onSend();
                          }
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        key: const ValueKey('ai-message-input'),
                        contextMenuBuilder: AppTextSelectionMenu.build,
                        controller: input,
                        focusNode: focusNode,
                        minLines: 2,
                        maxLines: 6,
                        enabled: !assistant.busy,
                        textInputAction: TextInputAction.newline,
                        cursorColor: theme.basePrimary,
                        style: TextStyle(
                          color: theme.textColorPrimary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                        decoration: InputDecoration(
                          hintText: l10n.aiInputHint,
                          hintStyle: TextStyle(color: theme.textColorTertiary),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: false,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Row(
                          children: [
                            const Spacer(),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * .78,
                              ),
                              child: ModelSelector(
                                theme: theme,
                                assistant: assistant,
                              ),
                            ),
                            const SizedBox(width: 6),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: input,
                              builder: (context, value, _) => AppTooltip(
                                message: ready
                                    ? l10n.aiSend
                                    : l10n.aiSetupAction,
                                child: Semantics(
                                  label: ready
                                      ? l10n.aiSend
                                      : l10n.aiSetupAction,
                                  button: true,
                                  child: TitleBarIconButton(
                                    key: const ValueKey('ai-send-button'),
                                    theme: theme,
                                    isFocused: true,
                                    icon: assistant.busy
                                        ? Symbols.more_horiz_rounded
                                        : Symbols.arrow_upward_rounded,
                                    size: 32,
                                    iconSize: 20,
                                    backgroundColor: theme.textColorPrimary,
                                    hoverColor: theme.textColorSecondary,
                                    iconColor: theme.primary,
                                    onPressed:
                                        !assistant.canChangeService ||
                                            value.text.trim().isEmpty
                                        ? null
                                        : onSend,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
