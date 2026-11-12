/*
 * @Description: 提供 LilygoBox AI 对话主页与设置操作确认。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-12 15:19:13
 */

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/provider.dart';
import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/image_clipboard_menu.dart';
import '../../../../core/widgets/interaction_decoration.dart';
import '../../../../core/widgets/popup_menu_transition.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../data/chat_completion_client.dart';
import '../../domain/models.dart';
import '../../state/provider.dart';
import '../widgets/chat_composer.dart';
import '../widgets/error_text.dart';
import '../widgets/message_content.dart';
import '../widgets/reasoning_effort_label.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  final _conversationSelectionFocus = FocusNode(skipTraversal: true);
  final _inputScroll = ScrollController();
  bool _showLatest = false;
  // 仅在用户仍停留在底部时跟随流式内容；手动向上滚动后暂停跟随。
  bool _followLatest = true;
  bool _scrollToEndPending = false;
  int _scrollToEndVersion = 0;
  List<AiImageAttachment> _attachments = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateLatestButton);
  }

  void _updateLatestButton() {
    if (!mounted || !_scroll.hasClients) return;
    final show = _scroll.position.extentAfter > 120;
    if (show != _showLatest) setState(() => _showLatest = show);
  }

  bool _handleScrollNotification(Notification notification) {
    if (notification is AppUserScrollNotification) {
      if (_scroll.hasClients &&
          identical(notification.position, _scroll.position) &&
          notification.delta < 0) {
        final cancelFollowAnimation = _scrollToEndPending;
        _followLatest = false;
        _scrollToEndVersion++;
        _scrollToEndPending = false;
        // 只取消仍在运行的底部跟随；反复 jumpTo 会打断用户滚轮动画，
        // 导致向上滚动的连续目标无法累计，表现为向上比向下吃力。
        if (cancelFollowAnimation) _scroll.jumpTo(_scroll.offset);
      }
      return false;
    }
    if (notification is! ScrollNotification &&
        notification is! ScrollMetricsNotification) {
      return false;
    }
    final metrics = notification is ScrollNotification
        ? notification.metrics
        : (notification as ScrollMetricsNotification).metrics;
    // 只处理聊天主滚动区域，详情和横向代码块不影响底部跟随。
    final depth = notification is ScrollNotification
        ? notification.depth
        : (notification as ScrollMetricsNotification).depth;
    if (metrics.axis != Axis.vertical || depth != 0) return false;
    if ((notification is UserScrollNotification &&
            notification.direction == ScrollDirection.forward) ||
        (notification is ScrollUpdateNotification &&
            (notification.scrollDelta ?? 0) < 0)) {
      // 公共滚轮和中键滚动使用程序位移，不一定发送 UserScrollNotification。
      // 向上位移同样表示退出跟随，同时作废旧动画后等待布局的回底部任务。
      _followLatest = false;
      _scrollToEndVersion++;
      _scrollToEndPending = false;
    } else if (notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0) > 0 &&
        metrics.extentAfter <= 1) {
      _followLatest = true;
    }
    if (notification is ScrollMetricsNotification && notification.depth == 0) {
      _updateLatestButton();
      if (_followLatest &&
          notification.metrics.extentAfter > 1 &&
          context.read<AiAssistantProvider>().busy) {
        _scrollToEnd();
      }
    }
    return false;
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    _conversationSelectionFocus.dispose();
    _inputScroll.dispose();
    super.dispose();
  }

  Future<void> _send(
    AiAssistantProvider assistant, {
    required bool fromKeyboard,
  }) async {
    final text = _input.text;
    final continuing =
        text.trim().isEmpty && _attachments.isEmpty && assistant.canContinue;
    if ((text.trim().isEmpty && _attachments.isEmpty && !continuing) ||
        !assistant.canSendMessage) {
      return;
    }
    if (!assistant.busy && !assistant.hasApiKey) {
      context.read<AppNavigationProvider>().openAiSettings();
      return;
    }
    if ((_attachments.isNotEmpty && !assistant.canAcceptImages()) ||
        !assistant.canSendImageHistory) {
      showAppNotice(
        ScaffoldMessenger.of(context),
        context.l10n.aiImageUnsupported,
      );
      return;
    }
    _input.clear();
    final attachments = _attachments;
    setState(() => _attachments = const []);
    final request = continuing
        ? assistant.continueGeneration()
        : assistant.sendMessage(text, attachments: attachments);
    if (fromKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    } else {
      _inputFocus.unfocus();
    }
    _scrollToEnd(force: true);
    await request;
    if (_followLatest) _scrollToEnd();
  }

  void _scrollToEnd({bool force = false}) {
    if (force) _followLatest = true;
    if (!_followLatest || _scrollToEndPending) return;
    _scrollToEndPending = true;
    final version = ++_scrollToEndVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // 图片解码或响应输出可能继续改变内容高度。
        // 同一次跟随等待布局后校正，不因每次高度通知重复启动动画。
        for (var attempt = 0; attempt < 8; attempt++) {
          if (!mounted ||
              !_scroll.hasClients ||
              !_followLatest ||
              version != _scrollToEndVersion) {
            return;
          }
          final target = _scroll.position.maxScrollExtent;
          if (_scroll.position.extentAfter <= 1) return;
          if (MediaQuery.disableAnimationsOf(context)) {
            _scroll.jumpTo(target);
          } else {
            await _scroll.animateTo(
              target,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
          if (!mounted ||
              !_scroll.hasClients ||
              !_followLatest ||
              version != _scrollToEndVersion) {
            return;
          }
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted ||
              !_scroll.hasClients ||
              !_followLatest ||
              version != _scrollToEndVersion) {
            return;
          }
          _updateLatestButton();
          if (_scroll.position.extentAfter <= 1) return;
        }
      } finally {
        if (version == _scrollToEndVersion) _scrollToEndPending = false;
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
              child: CustomMultiChildLayout(
                delegate: _ConversationLayout(hasMessages: messages.isNotEmpty),
                children: [
                  LayoutId(
                    id: _ConversationSlot.messages,
                    child: messages.isEmpty
                        ? _Welcome(theme: theme)
                        : TextFieldTapRegion(
                            onTapOutside: (event) {
                              if (event.buttons == kPrimaryMouseButton &&
                                  _conversationSelectionFocus.hasFocus) {
                                _conversationSelectionFocus.unfocus();
                              }
                            },
                            child: SelectionArea(
                              focusNode: _conversationSelectionFocus,
                              contextMenuBuilder:
                                  AppTextSelectionMenu.buildRegion,
                              child: NotificationListener<Notification>(
                                onNotification: _handleScrollNotification,
                                child: Scrollbar(
                                  controller: _scroll,
                                  child: ShaderMask(
                                    blendMode: BlendMode.dstIn,
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.white,
                                            Colors.transparent,
                                          ],
                                          stops: [0, 1],
                                        ).createShader(
                                          Rect.fromLTWH(
                                            0,
                                            bounds.height - 64,
                                            bounds.width,
                                            64,
                                          ),
                                        ),
                                    child: ScrollConfiguration(
                                      behavior: const AppScrollBehavior(
                                        scrollbars: false,
                                      ),
                                      child: SingleChildScrollView(
                                        key: const ValueKey(
                                          'ai-message-scroll',
                                        ),
                                        controller: _scroll,
                                        padding: const EdgeInsets.fromLTRB(
                                          24,
                                          16,
                                          24,
                                          56,
                                        ),
                                        // 使用实际总高度，避免变高消息的懒加载估算导致拖动滑块跳位。
                                        child: Column(
                                          children: [
                                            for (final message in messages)
                                              Center(
                                                child: ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                        maxWidth: 772,
                                                      ),
                                                  child: _MessageView(
                                                    key: ValueKey(message.id),
                                                    message: message,
                                                    theme: theme,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  LayoutId(
                    id: _ConversationSlot.composer,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: 1,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
                          child: ChatComposer(
                            input: _input,
                            focusNode: _inputFocus,
                            scrollController: _inputScroll,
                            theme: theme,
                            assistant: assistant,
                            ready: ready,
                            onSend: (fromKeyboard) =>
                                _send(assistant, fromKeyboard: fromKeyboard),
                            attachments: _attachments,
                            onAttachmentsChanged: (attachments) =>
                                setState(() => _attachments = attachments),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (messages.isNotEmpty)
                    LayoutId(
                      id: _ConversationSlot.latest,
                      child: IgnorePointer(
                        ignoring: !_showLatest,
                        child: ExcludeFocus(
                          excluding: !_showLatest,
                          child: ExcludeSemantics(
                            excluding: !_showLatest,
                            child: AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : PopupMenuTransition.duration,
                              switchInCurve:
                                  InteractionDecoration.animationCurve,
                              switchOutCurve:
                                  InteractionDecoration.animationCurve,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                              child: _showLatest
                                  ? AppTooltip(
                                      key: const ValueKey('ai-latest-visible'),
                                      message: l10n.aiScrollToLatest,
                                      child: Semantics(
                                        label: l10n.aiScrollToLatest,
                                        button: true,
                                        child: TitleBarIconButton(
                                          key: const ValueKey(
                                            'ai-scroll-to-latest',
                                          ),
                                          theme: theme,
                                          isFocused: true,
                                          icon: Symbols.arrow_downward_rounded,
                                          size: 28,
                                          iconSize: 18,
                                          backgroundColor:
                                              theme.iconBackgroundColor,
                                          surfaceColor: theme.secondary,
                                          hoverColor: theme
                                              .interactionHoverColor(
                                                theme.iconBackgroundColor,
                                              ),
                                          onPressed: () =>
                                              _scrollToEnd(force: true),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ConversationSlot { messages, composer, latest }

/// Lay out the composer first so the fade follows its actual, variable height.
/// Messages extend behind its top edge rather than ending at a separate seam.
class _ConversationLayout extends MultiChildLayoutDelegate {
  _ConversationLayout({required this.hasMessages});

  final bool hasMessages;

  @override
  void performLayout(Size size) {
    final composerSize = layoutChild(
      _ConversationSlot.composer,
      BoxConstraints(maxWidth: size.width, maxHeight: size.height),
    );
    final composerTop = size.height - composerSize.height;
    final overlap = hasMessages ? 16.0 : 0.0;
    layoutChild(
      _ConversationSlot.messages,
      BoxConstraints.tight(Size(size.width, composerTop + overlap)),
    );
    positionChild(_ConversationSlot.messages, Offset.zero);
    positionChild(_ConversationSlot.composer, Offset(0, composerTop));
    if (hasChild(_ConversationSlot.latest)) {
      final buttonSize = layoutChild(
        _ConversationSlot.latest,
        BoxConstraints.tight(const Size(32, 32)),
      );
      final rightInset = ((size.width - 820) / 2).clamp(24.0, size.width);
      positionChild(
        _ConversationSlot.latest,
        Offset(
          (size.width - rightInset - buttonSize.width).clamp(0, size.width),
          (composerTop - buttonSize.height - 4).clamp(0, size.height),
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_ConversationLayout oldDelegate) =>
      hasMessages != oldDelegate.hasMessages;
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
                      Center(
                        child: SvgPicture.asset(
                          'assets/images/branding/lilygobox_logo.svg',
                          width: 56,
                          height: 56,
                          fit: BoxFit.contain,
                          colorFilter: ColorFilter.mode(
                            theme.textColorPrimary,
                            BlendMode.srcIn,
                          ),
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(height: 16),
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
  const _MessageView({super.key, required this.message, required this.theme});

  final AiMessage message;
  final AppTheme theme;

  @override
  State<_MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<_MessageView> {
  bool _detailsExpanded = false;
  bool _detailsHovered = false;
  bool _detailsFocused = false;
  final _detailsScroll = ScrollController();

  @override
  void dispose() {
    _detailsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.role == 'user';
    final turnFinished = switch (message.status) {
      AiResponseStatus.completed ||
      AiResponseStatus.failed ||
      AiResponseStatus.stopped => true,
      _ => false,
    };
    final content = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isUser ? widget.theme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: message.attachments.isNotEmpty
                ? const EdgeInsets.all(12)
                : EdgeInsets.symmetric(
                    horizontal: isUser ? 12 : 14,
                    vertical: isUser ? 9 : 11,
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.attachments.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final attachment in message.attachments)
                        ImageClipboardMenu(
                          bytes: attachment.bytes,
                          theme: widget.theme,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ColoredBox(
                              color: widget.theme.secondary,
                              child: Image.memory(
                                attachment.bytes,
                                width: 100,
                                height: 100,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                if (message.attachments.isNotEmpty &&
                    message.content.isNotEmpty)
                  const SizedBox(height: 8),
                // 纯图片消息不构建空正文，避免空正文占用一行高度。
                if (message.content.isNotEmpty || message.attachments.isEmpty)
                  ChatMessageBody(
                    message: message,
                    theme: widget.theme,
                    useParentSelectionArea: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (isUser || message.elapsed == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          if (isUser || turnFinished)
            ChatMessageActions(message: message, theme: widget.theme),
        ],
      );
    }
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('ai-response-details-${message.id}'),
          onTap: () {
            final selection = context
                .findAncestorStateOfType<SelectionAreaState>();
            selection?.selectableRegion.clearSelection();
            selection?.selectableRegion.hideToolbar();
            setState(() => _detailsExpanded = !_detailsExpanded);
          },
          onHover: (hovered) => setState(() => _detailsHovered = hovered),
          onFocusChange: (focused) => setState(() => _detailsFocused = focused),
          mouseCursor: SystemMouseCursors.click,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InteractionDecoration.color(
            palette: widget.theme,
            color: _detailsHovered || _detailsFocused
                ? widget.theme.textColorPrimary
                : widget.theme.textColorTertiary,
            builder: (context, color) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _responseStatusText(context, message),
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _detailsExpanded ? .25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Symbols.chevron_right_rounded,
                      size: 16,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: widget.theme.dividerColor),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _detailsExpanded
              ? Padding(
                  key: const ValueKey('ai-response-details-expanded'),
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
                      if (message.reasoningEffort case final effort?)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l10n.aiResponseReasoningEffort(
                              reasoningEffortLabel(l10n, effort),
                            ),
                            key: ValueKey('ai-response-effort-${message.id}'),
                            style: TextStyle(
                              color: widget.theme.textColorSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (message.processEvents.isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: Scrollbar(
                            controller: _detailsScroll,
                            child: SingleChildScrollView(
                              controller: _detailsScroll,
                              primary: false,
                              padding: const EdgeInsetsDirectional.only(
                                end: 20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final event in message.processEvents)
                                    if (event.type !=
                                            AiProcessEventType.assistant &&
                                        event.type !=
                                            AiProcessEventType.guidance &&
                                        !(turnFinished &&
                                            event.type ==
                                                AiProcessEventType.status &&
                                            event.status ==
                                                AiResponseStatus.thinking))
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
                    ],
                  ),
                )
              : const SizedBox(
                  key: ValueKey('ai-response-details-collapsed'),
                  width: double.infinity,
                ),
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
                  fill: 1,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${l10n.aiTurnFailed}  ${aiErrorText(l10n, error)}',
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
        if (turnFinished)
          ChatMessageActions(message: message, theme: widget.theme),
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
    AiResponseStatus.accessingWeb => l10n.aiAccessingWeb,
    AiResponseStatus.awaitingApproval => l10n.aiAwaitingApproval,
    AiResponseStatus.retrying => l10n.aiRetryingRequest(
      retryAttempt,
      ChatCompletionClient.maxRetries,
    ),
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
    final toolName = action?.name ?? event.toolName;
    final retry = event.retry;
    final isWeb =
        action?.name == 'read_webpage' ||
        event.status == AiResponseStatus.accessingWeb;
    final failed =
        action?.succeeded == false || event.status == AiResponseStatus.failed;
    final label = switch (event.type) {
      AiProcessEventType.status =>
        _responseStatusLabel(context, event.status) ?? l10n.aiProcessCompleted,
      AiProcessEventType.reasoning =>
        isThinking ? l10n.aiAssistantThinking : l10n.aiProcessReasoning,
      AiProcessEventType.action when action?.name == 'read_webpage' =>
        action!.succeeded
            ? l10n.aiWebSucceeded(action.arguments['url'].toString())
            : l10n.aiWebFailed(action.arguments['url'].toString()),
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
      // 兼容旧数据；新回合不会再生成这两类过程事件。
      AiProcessEventType.assistant || AiProcessEventType.guidance => '',
    };
    final modelNote = event.type == AiProcessEventType.reasoning;
    final statusIcon = switch (event.status) {
      AiResponseStatus.connecting => Symbols.cloud_sync_rounded,
      AiResponseStatus.awaitingReply => Symbols.hourglass_top_rounded,
      AiResponseStatus.thinking => Symbols.neurology_rounded,
      AiResponseStatus.streaming => Symbols.edit_note_rounded,
      AiResponseStatus.preparingTools => Symbols.pending_actions_rounded,
      AiResponseStatus.executingTools => Symbols.play_circle_rounded,
      AiResponseStatus.accessingWeb => Symbols.language_rounded,
      AiResponseStatus.awaitingApproval => Symbols.verified_user_rounded,
      AiResponseStatus.retrying => Symbols.refresh_rounded,
      AiResponseStatus.completed => Symbols.check_rounded,
      AiResponseStatus.failed => Symbols.error_outline_rounded,
      AiResponseStatus.stopped => Symbols.stop_circle_rounded,
      null => Symbols.circle_rounded,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Transform.flip(
              flipY: false,
              child: Icon(
                failed
                    ? Symbols.error_outline_rounded
                    : isWeb
                    ? Symbols.language_rounded
                    : toolName != null
                    ? _toolIcon(toolName)
                    : modelNote
                    ? isThinking
                          ? Symbols.neurology_rounded
                          : Symbols.blur_on
                    : event.type == AiProcessEventType.retry
                    ? Symbols.refresh_rounded
                    : statusIcon,
                fill:
                    (!failed && isWeb) ||
                        (modelNote && isThinking) ||
                        event.status == AiResponseStatus.thinking
                    ? 0
                    : modelNote
                    ? null
                    : 1,
                size: 12,
                color: failed
                    ? Theme.of(context).colorScheme.error
                    : theme.textColorTertiary,
              ),
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
                      child: Text(
                        label,
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
                if (action?.webFailure case final failure?) ...[
                  const SizedBox(height: 5),
                  Text(
                    aiErrorText(l10n, failure),
                    style: TextStyle(
                      color: theme.textColorSecondary,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
                if (event.text.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    event.text,
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

/// 以实际操作选择图标，执行阶段和完成记录使用同一套映射。
IconData _toolIcon(String name) => switch (name) {
  'read_file' => Symbols.description_rounded,
  'list_directory' => Symbols.folder_open_rounded,
  'write_file' => Symbols.edit_document_rounded,
  'get_current_time' => Symbols.schedule_rounded,
  'read_webpage' => Symbols.language_rounded,
  'set_theme' => Symbols.palette_rounded,
  'set_language' => Symbols.translate_rounded,
  'set_font' => Symbols.font_download_rounded,
  'set_sidebar_visibility' ||
  'set_sidebar_width' ||
  'set_settings_sidebar_width' => Symbols.side_navigation_rounded,
  'set_content_split_width' => Symbols.view_column_rounded,
  _ => Symbols.play_circle_rounded,
};

String _formatElapsed(Duration duration) {
  final totalMilliseconds = duration.inMilliseconds;
  final totalSeconds = totalMilliseconds ~/ 1000;
  final totalMinutes = totalSeconds ~/ 60;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  final seconds = totalSeconds % 60;
  final milliseconds = totalMilliseconds % 1000;
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  String threeDigits(int value) => value.toString().padLeft(3, '0');
  final time =
      '${twoDigits(minutes)}:${twoDigits(seconds)}:${threeDigits(milliseconds)}';
  return hours == 0 ? time : '${twoDigits(hours)}:$time';
}

String _aiActionSummary(
  BuildContext context,
  String? name,
  Map<String, Object?> args,
) {
  final l10n = context.l10n;
  return switch (name) {
    'get_current_time' => l10n.aiToolTime,
    'read_webpage' => '${l10n.aiToolWeb}: ${args['url']}',
    'list_directory' => '${l10n.aiToolList}: ${args['path']}',
    'read_file' => '${l10n.aiToolRead}: ${args['path']}',
    'write_file' => '${l10n.aiToolWrite}: ${args['path']}',
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
