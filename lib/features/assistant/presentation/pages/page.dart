/*
 * @Description: 提供 LilygoBox AI 对话主页与设置操作确认。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-04 12:04:44
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../domain/models.dart';
import '../../state/provider.dart';
import '../widgets/chat_composer.dart';
import '../widgets/error_text.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _send(AiAssistantProvider assistant) async {
    final text = _input.text;
    if (text.trim().isEmpty || !assistant.canChangeService) return;
    if (!assistant.hasApiKey) {
      context.read<AppNavigationProvider>().openAiSettings();
      return;
    }
    _input.clear();
    final request = assistant.sendMessage(text);
    _scrollToEnd();
    await request;
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final assistant = context.watch<AiAssistantProvider>();
    final messages = assistant.messages;
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    final ready = assistant.credentialLoaded && assistant.hasApiKey;

    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
      child: ColoredBox(
        color: theme.secondary,
        child: Column(
          children: [
            if (messages.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: AppTooltip(
                    message: l10n.aiClearConversation,
                    child: IconButton(
                      onPressed: assistant.busy
                          ? null
                          : assistant.clearConversation,
                      icon: const Icon(Symbols.delete_sweep_rounded),
                      tooltip: l10n.aiClearConversation,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: messages.isEmpty
                  ? _Welcome(theme: theme)
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                          itemCount: messages.length + (assistant.busy ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == messages.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  l10n.aiAssistantThinking,
                                  style: TextStyle(
                                    color: theme.textColorTertiary,
                                    fontSize: 13,
                                  ),
                                ),
                              );
                            }
                            final message = messages[index];
                            return _MessageView(
                              message: message,
                              theme: theme,
                              isResolving: assistant.isResolvingTool(
                                message.id,
                              ),
                              onResolve: (approve) => assistant.resolveTool(
                                message.id,
                                approve: approve,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
            if (messages.isNotEmpty && assistant.error != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Row(
                    children: [
                      Icon(Symbols.error_outline, size: 16, color: errorColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          !ready
                              ? l10n.aiConfigureMessage
                              : aiErrorText(l10n, assistant.error!),
                          style: TextStyle(color: errorColor, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ChatComposer(
                  input: _input,
                  focusNode: _inputFocus,
                  theme: theme,
                  assistant: assistant,
                  ready: ready,
                  onSend: () => _send(assistant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 740),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.assistantGreeting,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          color: theme.textColorPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.assistantDescription,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: theme.textColorTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.message,
    required this.theme,
    required this.isResolving,
    required this.onResolve,
  });

  final AiMessage message;
  final AppTheme theme;
  final bool isResolving;
  final ValueChanged<bool> onResolve;

  @override
  Widget build(BuildContext context) {
    if (message.toolName != null) return _ToolApprovalCard(this);
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isUser ? theme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: SelectableText(
                message.content,
                style: TextStyle(
                  color: theme.textColorPrimary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolApprovalCard extends StatelessWidget {
  const _ToolApprovalCard(this.view);
  final _MessageView view;

  String _summary(BuildContext context) {
    final args = view.message.toolArguments!;
    final l10n = context.l10n;
    return switch (view.message.toolName) {
      'set_theme' => l10n.aiActionTheme(
        args['theme'] == 'dark' ? l10n.themeDark : l10n.themeLight,
      ),
      'set_language' => l10n.aiActionLanguage(switch (args['language']) {
        'en' => l10n.languageEnglish,
        'zh' => l10n.languageChinese,
        _ => l10n.languageAutoDetect,
      }),
      'set_font' => l10n.aiActionFont(switch (args['font']) {
        'inter' => l10n.fontInter,
        'googleSansFlex' => l10n.fontGoogleSansFlex,
        'roboto' => l10n.fontRoboto,
        _ => l10n.fontSystem,
      }),
      'set_sidebar_visibility' =>
        args['visible'] == true
            ? l10n.aiActionShowSidebar
            : l10n.aiActionHideSidebar,
      'set_sidebar_width' => l10n.aiActionSidebarWidth(
        args['width'].toString(),
      ),
      'set_content_split_width' => l10n.aiActionSplitWidth(
        args['width'].toString(),
      ),
      'set_settings_sidebar_width' => l10n.aiActionSettingsWidth(
        args['width'].toString(),
      ),
      _ => l10n.aiActionUnknown,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final decided = view.message.toolDecision;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: view.theme.primary,
              border: Border.all(color: view.theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiApprovalTitle,
                    style: TextStyle(
                      color: view.theme.textColorPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _summary(context),
                    style: TextStyle(color: view.theme.textColorSecondary),
                  ),
                  const SizedBox(height: 12),
                  if (decided == null)
                    Wrap(
                      spacing: 8,
                      children: [
                        AppActionButton(
                          theme: view.theme,
                          label: l10n.aiApprove,
                          icon: Symbols.check_rounded,
                          primary: true,
                          onPressed: view.isResolving
                              ? null
                              : () => view.onResolve(true),
                        ),
                        AppActionButton(
                          theme: view.theme,
                          label: l10n.aiReject,
                          icon: Symbols.close_rounded,
                          onPressed: view.isResolving
                              ? null
                              : () => view.onResolve(false),
                        ),
                      ],
                    )
                  else
                    Text(
                      decided ? l10n.aiActionApproved : l10n.aiActionRejected,
                      style: TextStyle(
                        color: view.theme.textColorTertiary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
