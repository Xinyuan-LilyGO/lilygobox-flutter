/*
 * @Description: 提供 LilygoBox AI 对话主页与设置操作确认。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-09 11:53:23
 */

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/provider.dart';
import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../data/chat_completion_client.dart';
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

  Future<void> _send(
    AiAssistantProvider assistant, {
    required bool fromKeyboard,
  }) async {
    final text = _input.text;
    if (text.trim().isEmpty || !assistant.canSendMessage) return;
    if (!assistant.hasApiKey) {
      context.read<AppNavigationProvider>().openAiSettings();
      return;
    }
    _input.clear();
    final request = assistant.sendMessage(text);
    if (fromKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    } else {
      _inputFocus.unfocus();
    }
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
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 772),
                            child: _MessageView(
                              key: ValueKey(messages[index].id),
                              message: messages[index],
                              theme: theme,
                              isResolving: assistant.isResolvingTool(
                                messages[index].id,
                              ),
                              onResolve: (approve) => assistant.resolveTool(
                                messages[index].id,
                                approve: approve,
                              ),
                            ),
                          ),
                        );
                      },
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
                  onSend: (fromKeyboard) =>
                      _send(assistant, fromKeyboard: fromKeyboard),
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

class _MessageView extends StatefulWidget {
  const _MessageView({
    super.key,
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
  State<_MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<_MessageView> {
  bool _detailsExpanded = false;
  final _detailsScroll = ScrollController();

  @override
  void dispose() {
    _detailsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.toolName != null) return _ToolApprovalCard(widget);
    final message = widget.message;
    final isUser = message.role == 'user';
    final content = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isUser ? widget.theme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isUser ? 12 : 14,
                vertical: isUser ? 9 : 11,
              ),
              child: SelectableText(
                message.content,
                selectionWidthStyle: ui.BoxWidthStyle.tight,
                contextMenuBuilder: AppTextSelectionMenu.build,
                style: TextStyle(
                  color: widget.theme.textColorPrimary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (isUser || message.elapsed == null) return content;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('ai-response-details-${message.id}'),
          onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _responseStatusText(context, message),
                    style: TextStyle(
                      color: widget.theme.textColorTertiary,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _detailsExpanded ? .25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Symbols.chevron_right_rounded,
                    size: 16,
                    color: widget.theme.textColorTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: widget.theme.dividerColor),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.topCenter,
          child: _detailsExpanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.aiResponseModel(message.model ?? ''),
                        style: TextStyle(
                          color: widget.theme.textColorSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (message.processEvents.isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: Scrollbar(
                            controller: _detailsScroll,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _detailsScroll,
                              primary: false,
                              padding: const EdgeInsetsDirectional.only(
                                end: 16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final event in message.processEvents)
                                    _ProcessEventView(
                                      event: event,
                                      theme: widget.theme,
                                      isThinking:
                                          message.status ==
                                              AiResponseStatus.thinking &&
                                          identical(
                                            event,
                                            message.processEvents.last,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (message.processingSteps.isEmpty)
                        Text(
                          l10n.aiResponseNoActions,
                          style: TextStyle(
                            color: widget.theme.textColorTertiary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (message.content.isNotEmpty) content,
        if (message.requestError case final error?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.error_outline_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    '${l10n.aiTurnFailed}  ${aiErrorText(l10n, error)}',
                    selectionWidthStyle: ui.BoxWidthStyle.tight,
                    contextMenuBuilder: AppTextSelectionMenu.build,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _responseStatusText(BuildContext context, AiMessage message) {
  final l10n = context.l10n;
  final elapsed = _formatElapsed(message.elapsed!);
  final label = _responseStatusLabel(
    context,
    message.status,
    retryAttempt: message.retries.isEmpty ? 1 : message.retries.last.attempt,
  );
  return label == null
      ? l10n.aiResponseElapsed(elapsed)
      : l10n.aiStatusElapsed(label, elapsed);
}

String? _responseStatusLabel(
  BuildContext context,
  AiResponseStatus? status, {
  int retryAttempt = 1,
}) {
  final l10n = context.l10n;
  return switch (status) {
    AiResponseStatus.connecting => l10n.aiConnecting,
    AiResponseStatus.awaitingReply => l10n.aiAwaitingReply,
    AiResponseStatus.thinking => l10n.aiAssistantThinking,
    AiResponseStatus.streaming => l10n.aiStreaming,
    AiResponseStatus.preparingTools => l10n.aiPreparingTools,
    AiResponseStatus.executingTools => l10n.aiExecutingTools,
    AiResponseStatus.retrying => l10n.aiRetryingRequest(
      retryAttempt,
      ChatCompletionClient.maxRetries,
    ),
    AiResponseStatus.paused => l10n.aiResponsePaused,
    AiResponseStatus.failed => l10n.aiResponseFailed,
    AiResponseStatus.stopped => l10n.aiResponseStopped,
    AiResponseStatus.completed || null => null,
  };
}

class _ProcessEventView extends StatelessWidget {
  const _ProcessEventView({
    required this.event,
    required this.theme,
    this.isThinking = false,
  });
  final AiProcessEvent event;
  final AppTheme theme;
  final bool isThinking;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final action = event.action;
    final retry = event.retry;
    final failed =
        action?.succeeded == false || event.status == AiResponseStatus.failed;
    final label = switch (event.type) {
      AiProcessEventType.status =>
        _responseStatusLabel(context, event.status) ?? l10n.aiProcessCompleted,
      AiProcessEventType.reasoning =>
        isThinking ? l10n.aiAssistantThinking : l10n.aiProcessReasoning,
      AiProcessEventType.assistant => l10n.aiProcessAssistant,
      AiProcessEventType.action =>
        action!.succeeded
            ? l10n.aiProcessActionSucceeded(
                _aiActionSummary(context, action.name, action.arguments),
              )
            : l10n.aiProcessActionFailed(
                _aiActionSummary(context, action.name, action.arguments),
              ),
      AiProcessEventType.retry =>
        '${l10n.aiRequestRetryRecord(retry!.attempt)}: ${aiErrorText(l10n, retry.error)}',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              failed
                  ? Symbols.error_outline_rounded
                  : action != null || event.status == AiResponseStatus.completed
                  ? Symbols.check_rounded
                  : Symbols.circle_rounded,
              size: 12,
              color: failed
                  ? Theme.of(context).colorScheme.error
                  : theme.textColorTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        label,
                        contextMenuBuilder: AppTextSelectionMenu.build,
                        selectionWidthStyle: ui.BoxWidthStyle.tight,
                        style: TextStyle(
                          color: failed
                              ? Theme.of(context).colorScheme.error
                              : theme.textColorSecondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _formatElapsed(event.elapsed),
                      style: TextStyle(
                        color: theme.textColorTertiary,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
                if (event.text.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  SelectableText(
                    event.text,
                    contextMenuBuilder: AppTextSelectionMenu.build,
                    selectionWidthStyle: ui.BoxWidthStyle.tight,
                    style: TextStyle(
                      color: theme.textColorSecondary,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatElapsed(Duration duration) {
  final seconds = duration.inSeconds;
  final minutes = seconds ~/ 60;
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  final remainingSeconds = seconds % 60;
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return hours > 0
      ? '${twoDigits(hours)}:${twoDigits(remainingMinutes)}:${twoDigits(remainingSeconds)}'
      : '${twoDigits(minutes)}:${twoDigits(remainingSeconds)}';
}

String _aiActionSummary(
  BuildContext context,
  String? name,
  Map<String, Object?> args,
) {
  final l10n = context.l10n;
  return switch (name) {
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
    'set_sidebar_width' => l10n.aiActionSidebarWidth(args['width'].toString()),
    'set_content_split_width' => l10n.aiActionSplitWidth(
      args['width'].toString(),
    ),
    'set_settings_sidebar_width' => l10n.aiActionSettingsWidth(
      args['width'].toString(),
    ),
    _ => l10n.aiActionUnknown,
  };
}

class _ToolApprovalCard extends StatelessWidget {
  const _ToolApprovalCard(this.view);
  final _MessageView view;

  String _summary(BuildContext context) {
    return _aiActionSummary(
      context,
      view.message.toolName,
      view.message.toolArguments!,
    );
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
