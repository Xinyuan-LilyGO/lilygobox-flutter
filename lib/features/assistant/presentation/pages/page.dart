/*
 * @Description: 提供 LilygoBox AI 对话主页与设置操作确认。
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
import '../../domain/models.dart';
import '../../domain/process_timeline.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/provider.dart';
import '../widgets/chat_composer.dart';
import '../widgets/error_text.dart';
import '../widgets/message_content.dart';
import '../widgets/process_details_scroll_view.dart';
import '../widgets/process_event_view.dart';
import '../widgets/reasoning_effort_label.dart';
import '../widgets/task_navigation_scope.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    this.readOnly = false,
    this.initialDraft = '',
  });

  final bool readOnly;
  final String initialDraft;

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
    _input.text = widget.initialDraft;
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
    if (widget.readOnly) return;
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
    // 其他子智能体占用或释放运行槽后，同步刷新当前会话的发送可用状态。
    context.select<AiWorkspaceProvider?, int>(
      (workspaces) => workspaces?.runningCount ?? 0,
    );
    final messages = assistant.messages;
    final l10n = context.l10n;
    final ready = assistant.credentialLoaded && assistant.hasApiKey;

    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
      child: ColoredBox(
        color: theme.secondary,
        child: Column(
          children: [
            if (messages.isNotEmpty && !widget.readOnly)
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
                    child:
                        widget.readOnly &&
                            assistant.pendingApproval == null &&
                            assistant.pendingUserInput == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              heightFactor: 1,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 820,
                                ),
                                child: ChatComposer(
                                  input: _input,
                                  focusNode: _inputFocus,
                                  scrollController: _inputScroll,
                                  theme: theme,
                                  assistant: assistant,
                                  ready: ready,
                                  onSend: (fromKeyboard) => _send(
                                    assistant,
                                    fromKeyboard: fromKeyboard,
                                  ),
                                  attachments: _attachments,
                                  onAttachmentsChanged: (attachments) =>
                                      setState(
                                        () => _attachments = attachments,
                                      ),
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

  Widget _processEvent(
    AiProcessEvent event,
    List<AiProcessEvent> events,
    bool thinking,
    Key key,
  ) => AiProcessEventView(
    key: key,
    event: event,
    operationEvents: events,
    theme: widget.theme,
    isThinking: thinking,
  );

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.role == 'user';
    final sourceTitle = message.toolName == 'agent_message'
        ? (message.toolArguments?['source_agent_title'] as String? ??
              message.toolArguments?['source_agent_id'] as String?)
        : null;
    final sourceId = message.toolName == 'agent_message'
        ? (message.toolArguments?['source_agent_id'] as String?)
        : null;
    final timeline = buildAiProcessTimeline(message.processEvents);
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
                if (sourceTitle != null) ...[
                  InkWell(
                    onTap:
                        sourceId == null ||
                            TaskNavigationScope.maybeOf(context) == null
                        ? null
                        : () => TaskNavigationScope.maybeOf(
                            context,
                          )!.openTask(sourceId),
                    borderRadius: BorderRadius.circular(4),
                    child: Text(
                      context.l10n.aiTopologyMessageFrom(sourceTitle),
                      key: ValueKey('agent-message-source-${message.id}'),
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.theme.textColorTertiary,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                  if (sourceId != null && sourceId.isNotEmpty)
                    Text(
                      context.l10n.aiAgentIdValue(sourceId),
                      key: ValueKey('agent-message-source-id-${message.id}'),
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.theme.textColorTertiary,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  const SizedBox(height: 4),
                ],
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
    final processSummary = aiMessageProcessSummary(context, message);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: InkWell(
            key: ValueKey('ai-response-details-${message.id}'),
            onTap: () {
              final selection = context
                  .findAncestorStateOfType<SelectionAreaState>();
              selection?.selectableRegion.clearSelection();
              selection?.selectableRegion.hideToolbar();
              setState(() => _detailsExpanded = !_detailsExpanded);
            },
            onHover: (hovered) => setState(() => _detailsHovered = hovered),
            onFocusChange: (focused) =>
                setState(() => _detailsFocused = focused),
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
                    if (processSummary != null) ...[
                      Icon(
                        processSummary.icon,
                        size: 12,
                        fill: processSummary.fill,
                        color: color,
                      ),
                      const SizedBox(width: 8),
                    ],
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
                          child: ProcessDetailsScrollView(
                            active: !turnFinished,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final entry in timeline)
                                  if (entry.event.type !=
                                          AiProcessEventType.assistant &&
                                      entry.event.type !=
                                          AiProcessEventType.guidance &&
                                      !(turnFinished &&
                                          entry.event.type ==
                                              AiProcessEventType.status &&
                                          entry.event.status ==
                                              AiResponseStatus.thinking))
                                    _processEvent(
                                      entry.event,
                                      entry.events,
                                      message.status ==
                                              AiResponseStatus.thinking &&
                                          identical(
                                            entry.event,
                                            message.processEvents.last,
                                          ),
                                      ValueKey(entry.id),
                                    ),
                              ],
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
  final elapsed = formatAiElapsed(message.elapsed!);
  final summary = aiMessageProcessSummary(context, message);
  final time = l10n.aiResponseElapsed(elapsed);
  return summary == null ? time : '${summary.label} · $time';
}
