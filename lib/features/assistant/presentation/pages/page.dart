/*
 * @Description: 提供 LilygoBox AI 对话主页与设置操作确认。
 */

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/image_clipboard_menu.dart';
import '../../../../core/widgets/interaction_decoration.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/popup_menu_transition.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../../speech/data/speech_aec3.dart';
import '../../../speech/domain/speech_model.dart';
import '../../../speech/domain/speech_reply_text.dart';
import '../../../speech/presentation/speech_labels.dart';
import '../../../speech/state/speech_provider.dart';
import '../../domain/models.dart';
import '../../domain/process_timeline.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/provider.dart';
import '../widgets/agent_message_source.dart';
import '../widgets/chat_bottom_fade.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_history_selection.dart';
import '../widgets/chat_history_window.dart';
import '../widgets/conversation_scroll_controller.dart';
import '../widgets/error_text.dart';
import '../widgets/message_content.dart';
import '../widgets/process_details_scroll_view.dart';
import '../widgets/process_event_view.dart';
import '../widgets/reasoning_effort_label.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    this.readOnly = false,
    this.speechActive,
    this.initialDraft = '',
    this.onManageContext,
  });

  final bool readOnly;
  final bool? speechActive;
  final String initialDraft;
  final VoidCallback? onManageContext;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();
  final _speechConversation = SpeechConversation();
  SpeechProvider? _speech;
  bool _canKeepRecording = false;
  String? _recognitionModelId;
  String? _synthesisModelId;
  late final _scroll = ConversationScrollController(
    pinToLatest: () =>
        _initialScrollPositionApplied &&
        _followLatest &&
        !(_scrollToEndPending && _animateScrollToEnd),
  );
  final _inputFocus = FocusNode();
  final _conversationSelectionFocus = FocusNode(skipTraversal: true);
  final _inputScroll = ScrollController();
  final _historyWindow = GlobalKey<ChatHistoryWindowState>();
  final _historySelection = GlobalKey<ChatHistorySelectionState>();
  bool _showLatest = false;
  // 仅在用户仍停留在底部时跟随流式内容；手动向上滚动后暂停跟随。
  bool _followLatest = true;
  bool _initialScrollPositionApplied = false;
  bool _scrollToEndPending = false;
  bool _animateScrollToEnd = false;
  bool _latestButtonUpdatePending = false;
  int _scrollToEndVersion = 0;
  List<AiImageAttachment> _attachments = const [];
  String? _lastAutoReadMessageId;
  bool _autoReadInitialized = false;
  bool _continuousStartPending = false;
  bool _continuousErrorBlocked = false;
  bool _wasContinuousMode = false;
  bool _wasPlaying = false;
  bool _inPlaybackCooldown = false;
  Timer? _playbackCooldownTimer;
  bool _bargedInDuringPlayback = false;
  Timer? _wakeIdleTimer;
  int? _lastIdleTimeoutSeconds;
  double? _continuousSilenceSeconds;
  double? _continuousMicGain;
  final _messageViews = <String, (AiMessage, AppTheme, Widget)>{};

  Widget _messageView(AiMessage message, AppTheme theme) {
    final cached = _messageViews[message.id];
    if (cached != null &&
        identical(cached.$1, message) &&
        identical(cached.$2, theme)) {
      return cached.$3;
    }
    final view = Center(
      key: PageStorageKey(message.id),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 772),
        child: _MessageRepaintBoundary(
          key: ValueKey('ai-message-paint-${message.id}'),
          enabled: !ChatMessageBody.usesContentSegments(message),
          child: Provider<SpeechConversation>.value(
            value: _speechConversation,
            child: _MessageView(
              key: ValueKey(message.id),
              message: message,
              theme: theme,
            ),
          ),
        ),
      ),
    );
    _messageViews[message.id] = (message, theme, view);
    return view;
  }

  @override
  void initState() {
    super.initState();
    _input.text = widget.initialDraft;
    _scroll.addListener(_updateLatestButton);
  }

  void _updateLatestButton() {
    if (!mounted || !_scroll.hasClients) return;
    final show =
        _scroll.position.extentAfter > 120 ||
        (_historyWindow.currentState?.hasLater ?? false);
    if (show == _showLatest || _latestButtonUpdatePending) return;
    _latestButtonUpdatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _latestButtonUpdatePending = false;
      if (!mounted || !_scroll.hasClients) return;
      final latest =
          _scroll.position.extentAfter > 120 ||
          (_historyWindow.currentState?.hasLater ?? false);
      if (latest != _showLatest) setState(() => _showLatest = latest);
    });
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
      _followLatest = false;
      _scrollToEndVersion++;
      _scrollToEndPending = false;
    } else if (notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0) > 0 &&
        metrics.extentAfter <= 1 &&
        !(_historyWindow.currentState?.hasLater ?? false)) {
      _followLatest = true;
    }
    if (notification is ScrollMetricsNotification && notification.depth == 0) {
      if (!_initialScrollPositionApplied) {
        _initialScrollPositionApplied = true;
        _followLatest =
            _scroll.initiallyFollowsLatest &&
            !(_historyWindow.currentState?.hasLater ?? false);
      }
      _updateLatestButton();
    }
    return false;
  }

  @override
  void dispose() {
    _playbackCooldownTimer?.cancel();
    _wakeIdleTimer?.cancel();
    final speech = _speech;
    scheduleMicrotask(() => speech?.stopConversation(_speechConversation));
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    _conversationSelectionFocus.dispose();
    _inputScroll.dispose();
    super.dispose();
  }

  Future<void> _transcribe(SpeechProvider speech) async {
    final modelId = context.read<AiAssistantProvider>().speechRecognitionId;
    if (modelId == null) return;
    final draft = _input.text;
    final separator = draft.trimRight().length == draft.length ? '\n' : '';
    void updateInput(String text, {bool focus = false}) {
      if (!mounted ||
          !_canKeepRecording ||
          context.read<AiAssistantProvider>().speechRecognitionId != modelId) {
        return;
      }
      final value = draft.isEmpty || text.isEmpty
          ? '$draft$text'
          : '$draft$separator$text';
      if (_input.text != value) {
        _input.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
      if (focus) _inputFocus.requestFocus();
    }

    final (:text, :error) = await speech.startRecording(
      _speechConversation,
      modelId: modelId,
      onPartial: updateInput,
    );
    if (!mounted ||
        !_canKeepRecording ||
        context.read<AiAssistantProvider>().speechRecognitionId != modelId) {
      return;
    }
    if (text != null) {
      updateInput(text, focus: true);
    } else if (error != null) {
      showAppNotice(
        ScaffoldMessenger.of(context),
        speechErrorLabel(context.l10n, error),
      );
    }
  }

  void _resetWakeIdleTimer() {
    _wakeIdleTimer?.cancel();
    if (!mounted) return;
    final assistant = context.read<AiAssistantProvider>();
    final timeoutSeconds = assistant.speechIdleTimeoutSeconds;
    _lastIdleTimeoutSeconds = timeoutSeconds;
    if (!assistant.speechContinuousRecognition ||
        timeoutSeconds <= 0 ||
        assistant.speechContinuousPaused ||
        _continuousErrorBlocked) {
      return;
    }
    if (assistant.speechWakeWords.isNotEmpty && !assistant.speechWakeActive) {
      return;
    }
    _wakeIdleTimer = Timer(Duration(seconds: timeoutSeconds), () {
      if (!mounted) return;
      final current = context.read<AiAssistantProvider>();
      if (!current.speechContinuousRecognition) return;
      if (current.speechWakeWords.isNotEmpty) {
        if (current.speechWakeActive) {
          current.setSpeechContinuousState(wakeActive: false);
        }
      } else {
        current.setSpeechContinuousState(paused: true, wakeActive: false);
        _speech?.stopConversation(_speechConversation, kind: .recognition);
      }
    });
  }

  Future<void> _sendRecognized(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || widget.readOnly || !mounted) return;
    final assistant = context.read<AiAssistantProvider>();
    if (assistant.busy && assistant.speechInterruptStopsGeneration) {
      assistant.stopGeneration();
      for (var i = 0; i < 60 && mounted && assistant.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (!mounted) return;
    }
    if (!assistant.canSendMessage) return;
    _input.value = TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
    await _send(
      assistant,
      fromKeyboard: false,
      steerIfBusy: assistant.busy && assistant.canGuideNow,
    );
  }

  Future<void> _runContinuousListening(SpeechProvider speech) async {
    if (_continuousStartPending || !mounted) return;
    final assistant = context.read<AiAssistantProvider>();
    final modelId = assistant.speechRecognitionId;
    if (modelId == null ||
        !_canKeepRecording ||
        !assistant.speechContinuousRecognition ||
        assistant.speechContinuousPaused ||
        _continuousErrorBlocked ||
        (!assistant.speechVoiceInterrupt &&
            (_inPlaybackCooldown || speech.hasPlayback || assistant.busy)) ||
        speech.busy ||
        speech.hasCapture) {
      return;
    }
    _continuousStartPending = true;
    var activeStart = false;
    final silenceSeconds = assistant.speechSendSilenceSeconds;
    final micGain = assistant.speechMicGain;
    _continuousSilenceSeconds = silenceSeconds;
    _continuousMicGain = micGain;
    final error = await () async {
      try {
        activeStart = true;
        return await speech.startContinuousListening(
          _speechConversation,
          modelId: modelId,
          allowDuringPlayback: assistant.speechVoiceInterrupt,
          silenceSeconds: silenceSeconds,
          micGain: micGain,
          onPartial: (partial) {
            if (!mounted) return;
            final current = context.read<AiAssistantProvider>();
            final wakeWords = current.speechWakeWords;
            final playingText = speech.playingText;
            if (playingText != null || current.busy) {
              if (wakeWords.isNotEmpty) {
                final match = matchSpeechWakeWord(partial, wakeWords);
                if (!match.matched ||
                    isLikelyPlaybackEcho(
                      partial,
                      playingText,
                      rejectShort: false,
                    )) {
                  return;
                }
                _bargedInDuringPlayback = true;
                if (playingText != null) {
                  speech.stopConversation(
                    _speechConversation,
                    kind: .synthesis,
                  );
                }
                current.setSpeechContinuousState(wakeActive: true);
                _resetWakeIdleTimer();
                if (match.command.isNotEmpty && _input.text != match.command) {
                  _input.value = TextEditingValue(
                    text: match.command,
                    selection: TextSelection.collapsed(
                      offset: match.command.length,
                    ),
                  );
                }
                return;
              }
              final minLength = current.speechMinTriggerLength;
              if (playingText == null) {
                if (current.busy &&
                    current.speechInterruptStopsGeneration &&
                    partial.trim().runes.length >= minLength) {
                  _bargedInDuringPlayback = true;
                  current.stopGeneration();
                }
              } else if (isLikelyPlaybackEcho(
                    partial,
                    playingText,
                    rejectShort: true,
                  ) ||
                  partial.trim().runes.length < minLength) {
                return;
              } else {
                _bargedInDuringPlayback = true;
                if (current.busy && current.speechInterruptStopsGeneration) {
                  current.stopGeneration();
                }
                speech.stopConversation(_speechConversation, kind: .synthesis);
              }
            }
            if (wakeWords.isNotEmpty && !current.speechWakeActive) {
              return;
            }
            if (speech.activeOrRecentPlayingText case final recent?
                when isLikelyPlaybackEcho(
                  partial,
                  recent,
                  rejectShort: false,
                )) {
              return;
            }
            if (partial.trim().isNotEmpty) _resetWakeIdleTimer();
            if (partial.isNotEmpty && _input.text != partial) {
              _input.value = TextEditingValue(
                text: partial,
                selection: TextSelection.collapsed(offset: partial.length),
              );
            }
          },
          onUtterance: (utterance) {
            if (!mounted) return;
            final current = context.read<AiAssistantProvider>();
            final wakeWords = current.speechWakeWords;
            final echoSource = speech.activeOrRecentPlayingText;
            final wasBargeIn = _bargedInDuringPlayback;
            _bargedInDuringPlayback = false;
            if (echoSource != null && !wasBargeIn) {
              final stillPlaying = speech.playingText != null;
              final hasAec3 = WebRtcAec3Library.tryLoad() != null;
              if (wakeWords.isNotEmpty) {
                final match = matchSpeechWakeWord(utterance, wakeWords);
                if (!match.matched ||
                    isLikelyPlaybackEcho(
                      utterance,
                      echoSource,
                      rejectShort: false,
                    )) {
                  return;
                }
                if (stillPlaying) {
                  speech.stopConversation(
                    _speechConversation,
                    kind: .synthesis,
                  );
                }
                current.setSpeechContinuousState(wakeActive: true);
                if (match.command.isNotEmpty) {
                  speech.stopConversation(
                    _speechConversation,
                    kind: .recognition,
                  );
                  unawaited(_sendRecognized(match.command));
                } else {
                  _resetWakeIdleTimer();
                }
                return;
              }
              if (isLikelyPlaybackEcho(
                utterance,
                echoSource,
                rejectShort: stillPlaying && !hasAec3,
              )) {
                _input.clear();
                return;
              }
              if (stillPlaying) {
                speech.stopConversation(_speechConversation, kind: .synthesis);
              }
              speech.clearRecentPlayingText();
            } else if (echoSource == null) {
              speech.clearRecentPlayingText();
            }
            if (wakeWords.isEmpty || current.speechWakeActive) {
              if (wakeWords.isNotEmpty && wasBargeIn) {
                final match = matchSpeechWakeWord(utterance, wakeWords);
                final command = match.matched ? match.command : utterance;
                if (command.isEmpty) {
                  _input.clear();
                  _resetWakeIdleTimer();
                  return;
                }
                _wakeIdleTimer?.cancel();
                speech.stopConversation(
                  _speechConversation,
                  kind: .recognition,
                );
                unawaited(_sendRecognized(command));
                return;
              }
              if (utterance.trim().runes.length <
                  current.speechMinTriggerLength) {
                _input.clear();
                return;
              }
              _wakeIdleTimer?.cancel();
              if (!current.speechWakeActive) {
                current.setSpeechContinuousState(wakeActive: true);
              }
              speech.stopConversation(_speechConversation, kind: .recognition);
              unawaited(_sendRecognized(utterance));
              return;
            }
            final match = matchSpeechWakeWord(utterance, wakeWords);
            if (!match.matched) return;
            current.setSpeechContinuousState(wakeActive: true);
            if (match.command.isNotEmpty) {
              speech.stopConversation(_speechConversation, kind: .recognition);
              unawaited(_sendRecognized(match.command));
            } else {
              _resetWakeIdleTimer();
            }
          },
        );
      } finally {
        if (activeStart) _continuousStartPending = false;
      }
    }();
    if (!mounted) return;
    if (error != null) {
      setState(() => _continuousErrorBlocked = true);
      showAppNotice(
        ScaffoldMessenger.of(context),
        speechErrorLabel(context.l10n, error),
      );
    }
  }

  Future<void> _autoPlayReply(
    SpeechProvider speech,
    Object owner,
    String text,
    SpeechVoiceSelection selection, {
    required bool allowContinuousCapture,
    required double gain,
    required double speed,
  }) async {
    final error = await speech.play(
      owner,
      text,
      selection: selection,
      allowContinuousCapture: allowContinuousCapture,
      gain: gain,
      speed: speed,
    );
    if (error != null && mounted) {
      showAppNotice(
        ScaffoldMessenger.of(context),
        speechErrorLabel(context.l10n, error),
      );
    }
  }

  Future<void> _send(
    AiAssistantProvider assistant, {
    required bool fromKeyboard,
    bool steerIfBusy = false,
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
        : assistant.sendMessage(
            text,
            attachments: attachments,
            steer: steerIfBusy,
          );
    if (fromKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    } else {
      _inputFocus.unfocus();
    }
    _scrollToEnd(force: true);
    try {
      await request;
    } catch (_) {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          context.l10n.aiRequestFailed,
        );
      }
    }
    if (_followLatest) _scrollToEnd();
  }

  void _scrollToEnd({bool force = false, bool animate = false}) {
    if (force) {
      _followLatest = true;
      _historyWindow.currentState?.showLatest();
    }
    if (!_followLatest || _scrollToEndPending) return;
    _scrollToEndPending = true;
    _animateScrollToEnd = animate && !MediaQuery.disableAnimationsOf(context);
    final version = ++_scrollToEndVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // 图片解码或响应输出可能继续改变内容高度。
        // 同一次跟随等待布局后校正，不因每次高度通知重复启动动画。
        for (var attempt = 0; attempt < 8; attempt++) {
          if (!mounted ||
              !_scroll.hasClients ||
              !_followLatest ||
              version != _scrollToEndVersion ||
              !_scroll.position.hasContentDimensions ||
              !_scroll.position.hasViewportDimension) {
            return;
          }
          final target = _scroll.position.maxScrollExtent;
          if (_scroll.position.extentAfter <= 1) return;
          if (!_animateScrollToEnd) {
            _scroll.jumpTo(target);
          } else {
            await _scroll.animateTo(
              target,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
          if (!mounted ||
              !_scroll.hasClients ||
              !_followLatest ||
              version != _scrollToEndVersion ||
              !_scroll.position.hasContentDimensions ||
              !_scroll.position.hasViewportDimension) {
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
    final visible = TickerMode.valuesOf(context).enabled;
    final speechActive = widget.speechActive ?? visible;
    final assistant = context.read<AiAssistantProvider>();
    context.select<AiAssistantProvider, Object>(
      (value) => visible
          ? value.revision
          : speechActive
          ? (
              value.busy,
              value.speechBindings,
              value.speechContinuousPaused,
              value.speechWakeActive,
              value.pendingApproval != null,
              value.pendingUserInput != null,
              value.messages.lastOrNull?.id,
              value.messages.lastOrNull?.finishedAt != null,
              value.messages.lastOrNull?.requestError == null,
              value.messages.lastOrNull?.content.contains('</speech>') ?? false,
            )
          : -1,
    );
    // 其他子智能体占用或释放运行槽后，同步刷新当前会话的发送可用状态。
    context.select<AiWorkspaceProvider?, int>(
      (workspaces) =>
          visible || speechActive ? workspaces?.runningCount ?? 0 : -1,
    );
    final messages = assistant.messages;
    final l10n = context.l10n;
    final ready = assistant.credentialLoaded && assistant.hasApiKey;
    final recognitionId = assistant.speechRecognitionId;
    final synthesisId = assistant.speechVoice?.modelId;
    final (speech, hasModel, phase, canRecord, hasPlayback, isContinuous) =
        context.select(
          (SpeechProvider? voice) => (
            voice,
            voice?.library.recognitionModel(recognitionId) != null,
            voice?.capturePhase(_speechConversation),
            voice != null && !voice.busy && !voice.hasCapture,
            voice?.hasPlayback ?? false,
            voice?.isContinuousListening(_speechConversation) ?? false,
          ),
        );
    _speech = speech;
    _speechConversation.agent = assistant;
    final liveStandby =
        assistant.speechContinuousRecognition &&
        assistant.speechWakeWords.isNotEmpty &&
        !assistant.speechWakeActive;
    if (speech != null && _speechConversation.standby != liveStandby) {
      scheduleMicrotask(
        () => speech.updateConversationStandby(_speechConversation, liveStandby),
      );
    }
    final canKeepRecording =
        speechActive &&
        !widget.readOnly &&
        assistant.pendingApproval == null &&
        assistant.pendingUserInput == null;
    if (!speechActive) {
      scheduleMicrotask(
        () => speech?.stopConversation(_speechConversation, kind: .recognition),
      );
    } else {
      if (phase != null &&
          (!hasModel ||
              recognitionId != _recognitionModelId ||
              (_canKeepRecording && !canKeepRecording))) {
        scheduleMicrotask(
          () =>
              speech?.stopConversation(_speechConversation, kind: .recognition),
        );
      }
      if (_synthesisModelId != null && synthesisId != _synthesisModelId) {
        scheduleMicrotask(
          () => speech?.stopConversation(_speechConversation, kind: .synthesis),
        );
      }
    }
    if (speechActive && synthesisId != null && synthesisId != _synthesisModelId) {
      final selection = assistant.speechVoice;
      if (selection != null) {
        scheduleMicrotask(() => speech?.warmUpSynthesis(selection));
      }
    }
    _recognitionModelId = recognitionId;
    _synthesisModelId = synthesisId;
    _canKeepRecording = canKeepRecording;
    final latestStreaming = messages
        .where(
          (message) =>
              message.role == 'assistant' &&
              message.finishedAt == null &&
              !message.isRoleplayOpening &&
              message.requestError == null,
        )
        .lastOrNull;
    final latestFinished = messages
        .where(
          (message) =>
              message.role == 'assistant' &&
              message.finishedAt != null &&
              !message.isRoleplayOpening &&
              message.requestError == null,
        )
        .lastOrNull;
    final voiceInterrupt = assistant.speechVoiceInterrupt;
    var willAutoPlay = false;
    if (!_autoReadInitialized) {
      _autoReadInitialized = true;
      _lastAutoReadMessageId = latestFinished?.id;
    } else if (speechActive &&
        speech != null &&
        !speech.busy &&
        !speech.hasManualCapture) {
      final selection = assistant.speechVoice;
      if (selection != null &&
          speech.library.synthesisModel(selection) != null) {
        if (latestStreaming != null &&
            latestStreaming.id != _lastAutoReadMessageId &&
            !speech.hasAutoRead(latestStreaming.id) &&
            assistant.speechAutoPlay) {
          final parsed = parseSpeechReply(latestStreaming.content);
          final spoken = parsed.speech;
          if (!parsed.pendingSpeech &&
              spoken != null &&
              spoken.isNotEmpty) {
            _lastAutoReadMessageId = latestStreaming.id;
            speech.markAutoRead(latestStreaming.id);
            willAutoPlay = true;
            final owner = (_speechConversation, latestStreaming.id);
            scheduleMicrotask(
              () => _autoPlayReply(
                speech,
                owner,
                spoken,
                selection,
                allowContinuousCapture: voiceInterrupt,
                gain: assistant.speechSynthesisGain,
                speed: assistant.speechSynthesisSpeed,
              ),
            );
          } else {
            // 若上一次打断杀掉了常驻合成进程，趁模型思考/流式吐字期间提前热身。
            scheduleMicrotask(() => speech.warmUpSynthesis(selection));
          }
        } else if (latestFinished != null &&
            latestFinished.id != _lastAutoReadMessageId &&
            !speech.hasAutoRead(latestFinished.id)) {
          _lastAutoReadMessageId = latestFinished.id;
          speech.markAutoRead(latestFinished.id);
          final finishedAt = latestFinished.finishedAt;
          final justFinished =
              finishedAt != null &&
              DateTime.now().difference(finishedAt).abs() <
                  const Duration(seconds: 5);
          if (justFinished) {
            final parsed = parseSpeechReply(latestFinished.content);
            final spoken =
                parsed.speech ??
                (assistant.speechFallbackReadBody
                    ? speechReplyText(latestFinished.content)
                    : null);
            if (spoken != null && spoken.isNotEmpty) {
              if (assistant.speechAutoPlay) {
                willAutoPlay = true;
                final owner = (_speechConversation, latestFinished.id);
                scheduleMicrotask(
                  () => _autoPlayReply(
                    speech,
                    owner,
                    spoken,
                    selection,
                    allowContinuousCapture: voiceInterrupt,
                    gain: assistant.speechSynthesisGain,
                    speed: assistant.speechSynthesisSpeed,
                  ),
                );
              } else {
                scheduleMicrotask(
                  () => speech.preSynthesize(
                    spoken,
                    selection: selection,
                    gain: assistant.speechSynthesisGain,
                    speed: assistant.speechSynthesisSpeed,
                  ),
                );
              }
            }
          }
        }
      }
    } else if (!assistant.speechAutoPlay) {
      _lastAutoReadMessageId = latestFinished?.id;
    }
    final continuousMode = assistant.speechContinuousRecognition;
    if (hasPlayback) {
      _wasPlaying = true;
      _playbackCooldownTimer?.cancel();
      _inPlaybackCooldown = false;
    } else if (_wasPlaying) {
      _wasPlaying = false;
      if (!voiceInterrupt &&
          continuousMode &&
          speechActive &&
          !assistant.speechContinuousPaused) {
        _inPlaybackCooldown = true;
        _playbackCooldownTimer?.cancel();
        final cooldown = WebRtcAec3Library.tryLoad() != null
            ? const Duration(milliseconds: 200)
            : const Duration(milliseconds: 1500);
        _playbackCooldownTimer = Timer(cooldown, () {
          if (!mounted) return;
          setState(() => _inPlaybackCooldown = false);
        });
      }
    }
    if (continuousMode != _wasContinuousMode) {
      _wasContinuousMode = continuousMode;
      _continuousErrorBlocked = false;
      if (!continuousMode) {
        _playbackCooldownTimer?.cancel();
        _inPlaybackCooldown = false;
        _wakeIdleTimer?.cancel();
        if (isContinuous) {
          scheduleMicrotask(
            () => speech?.stopConversation(
              _speechConversation,
              kind: .recognition,
            ),
          );
        }
      }
    }
    if (speechActive &&
        continuousMode &&
        canKeepRecording &&
        hasModel &&
        !assistant.speechContinuousPaused &&
        !_continuousErrorBlocked &&
        speech != null) {
      final shouldListen =
          !speech.busy &&
          (voiceInterrupt ||
              (!assistant.busy &&
                  !hasPlayback &&
                  !willAutoPlay &&
                  !_inPlaybackCooldown));
      if (shouldListen) {
        if (isContinuous &&
            (_continuousSilenceSeconds != assistant.speechSendSilenceSeconds ||
                _continuousMicGain != assistant.speechMicGain)) {
          scheduleMicrotask(
            () => speech.stopConversation(
              _speechConversation,
              kind: .recognition,
            ),
          );
        } else if (!speech.hasCapture && !_continuousStartPending) {
          scheduleMicrotask(() => _runContinuousListening(speech));
        }
        final idleTimeout = assistant.speechIdleTimeoutSeconds;
        if (idleTimeout <= 0 ||
            hasPlayback ||
            (assistant.speechWakeWords.isNotEmpty &&
                !assistant.speechWakeActive)) {
          _wakeIdleTimer?.cancel();
        } else if (!(_wakeIdleTimer?.isActive ?? false) ||
            _lastIdleTimeoutSeconds != idleTimeout) {
          _resetWakeIdleTimer();
        }
      } else {
        _wakeIdleTimer?.cancel();
        if (isContinuous) {
          scheduleMicrotask(
            () => speech.stopConversation(
              _speechConversation,
              kind: .recognition,
            ),
          );
        }
      }
    } else {
      _wakeIdleTimer?.cancel();
    }
    final voiceButton =
        speech == null || !canKeepRecording || (!hasModel && phase == null)
        ? null
        : _voiceButton(
            speech,
            assistant,
            phase,
            canRecord,
            hasPlayback,
            isContinuous,
            theme,
          );

    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
      child: ColoredBox(
        color: theme.secondary,
        child: Column(
          children: [
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
                            child: ChatHistorySelection(
                              key: _historySelection,
                              focusNode: _conversationSelectionFocus,
                              messages: messages,
                              onSelectionChanged: () => _historyWindow
                                  .currentState
                                  ?.selectionChanged(),
                              hasUnloadedMessages: () =>
                                  (_historyWindow.currentState?.hasEarlier ??
                                      false) ||
                                  (_historyWindow.currentState?.hasLater ??
                                      false) ||
                                  (_historyWindow
                                          .currentState
                                          ?.hasUnloadedContent ??
                                      false),
                              child: NotificationListener<Notification>(
                                key: PageStorageKey(
                                  'assistant-history-${assistant.memoryOwner}',
                                ),
                                onNotification: _handleScrollNotification,
                                child: ChatHistoryWindow(
                                  key: _historyWindow,
                                  messages: messages,
                                  controller: _scroll,
                                  scrollbar: true,
                                  historyId: assistant.memoryOwner,
                                  followsLatest: () => _followLatest,
                                  hasSelection: () =>
                                      _historySelection
                                          .currentState
                                          ?.hasSelection ??
                                      false,
                                  onContentRangeChanged: _updateLatestButton,
                                  itemBuilder: (message) =>
                                      _messageView(message, theme),
                                  onRangeChanged: (ids) =>
                                      _messageViews.removeWhere(
                                        (id, _) => !ids.contains(id),
                                      ),
                                  viewportBuilder: (context, child) =>
                                      ChatBottomFade(
                                        backgroundColor: theme.secondary,
                                        topFadeHeight: chatTopFadeHeight,
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
                                              chatTopFadeHeight,
                                              24,
                                              56,
                                            ),
                                            child: child,
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
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 6),
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
                                  onManageContext: widget.onManageContext,
                                  voiceButton: voiceButton,
                                  voiceRecording: phase != null,
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
                                          onPressed: () => _scrollToEnd(
                                            force: true,
                                            animate: true,
                                          ),
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

  Widget _voiceButton(
    SpeechProvider speech,
    AiAssistantProvider assistant,
    SpeechCapturePhase? phase,
    bool canRecord,
    bool hasPlayback,
    bool isContinuous,
    AppTheme theme,
  ) {
    final l10n = context.l10n;
    if (assistant.speechContinuousRecognition) {
      final hasWakeWords = assistant.speechWakeWords.isNotEmpty;
      final standby = hasWakeWords && !assistant.speechWakeActive;
      final paused =
          assistant.speechContinuousPaused || _continuousErrorBlocked;
      final surface = theme.primary;
      final directListening = !paused && !standby;
      final background = directListening
          ? theme.materialColors.error
          : !paused && standby
          ? theme.basePrimary
          : surface;
      final hover = directListening || (!paused && standby)
          ? theme.hoverColorForBackground(background)
          : null;
      final tooltip = paused
          ? l10n.speechResumeListening
          : standby
          ? l10n.speechStandbyListening
          : hasPlayback
          ? l10n.speechInterruptAndListen
          : l10n.speechContinuousListening;

      void handlePrimaryPress() {
        if (hasPlayback && !isContinuous) {
          _playbackCooldownTimer?.cancel();
          _inPlaybackCooldown = false;
          _wasPlaying = false;
          speech.stopConversation(_speechConversation, kind: .synthesis);
          setState(() => _continuousErrorBlocked = false);
          assistant.setSpeechContinuousState(paused: false, wakeActive: true);
          _resetWakeIdleTimer();
          return;
        }
        if (paused) {
          setState(() => _continuousErrorBlocked = false);
          assistant.setSpeechContinuousState(
            paused: false,
            wakeActive: !hasWakeWords,
          );
          if (!hasWakeWords) _resetWakeIdleTimer();
          return;
        }
        if (standby) {
          assistant.setSpeechContinuousState(wakeActive: true);
          _resetWakeIdleTimer();
          return;
        }
        _wakeIdleTimer?.cancel();
        assistant.setSpeechContinuousState(paused: true, wakeActive: false);
        speech.stopConversation(_speechConversation, kind: .recognition);
      }

      return GestureDetector(
        onSecondaryTapUp: paused
            ? null
            : (_) {
                _wakeIdleTimer?.cancel();
                assistant.setSpeechContinuousState(
                  paused: true,
                  wakeActive: false,
                );
                speech.stopConversation(
                  _speechConversation,
                  kind: .recognition,
                );
              },
        child: AppTooltip(
          message: tooltip,
          child: Semantics(
            label: tooltip,
            button: true,
            child: MenuItemSurface(
              key: const ValueKey('ai-voice-input'),
              theme: theme,
              surfaceColor: surface,
              backgroundColor: background,
              hoverColor: hover,
              borderRadius: BorderRadius.circular(15),
              onPressed: handlePrimaryPress,
              child: SizedBox(
                width: 30,
                height: 30,
                child: Icon(
                  paused ? Symbols.mic_rounded : Symbols.graphic_eq_rounded,
                  fill: paused ? 1 : 0,
                  size: 19,
                  color: directListening
                      ? theme.materialColors.onError
                      : !paused && standby
                      ? theme.materialColors.onPrimary
                      : theme.textColorPrimary,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final manualPhase = isContinuous ? null : phase;
    final manualLabel = switch (manualPhase) {
      .recording => l10n.speechStopRecording,
      .starting => l10n.speechLoading,
      .transcribing => l10n.speechTranscribing,
      null => l10n.speechStartRecording,
    };
    final manualOnPressed = switch (manualPhase) {
      .recording => () => speech.finishRecording(_speechConversation),
      null when canRecord => () => unawaited(_transcribe(speech)),
      _ => null,
    };
    final manualRecording = manualPhase == .recording;
    final manualActiveColor = theme.materialColors.error;
    return AppTooltip(
      message: manualLabel,
      child: Semantics(
        label: manualLabel,
        button: true,
        enabled: manualOnPressed != null,
        child: MenuItemSurface(
          key: const ValueKey('ai-voice-input'),
          theme: theme,
          surfaceColor: theme.primary,
          backgroundColor: manualRecording
              ? manualActiveColor
              : theme.primary,
          hoverColor: manualRecording
              ? theme.hoverColorForBackground(manualActiveColor)
              : null,
          borderRadius: BorderRadius.circular(15),
          onPressed: manualOnPressed,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(
              switch (manualPhase) {
                .recording => Symbols.stop_rounded,
                .starting || .transcribing => Symbols.hourglass_top_rounded,
                null => Symbols.mic_rounded,
              },
              fill: manualPhase == null || manualPhase == .recording ? 1 : 0,
              size: 19,
              color: manualRecording
                  ? theme.materialColors.onError
                  : manualPhase == null
                  ? theme.textColorPrimary
                  : theme.textColorSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageRepaintBoundary extends RepaintBoundary {
  const _MessageRepaintBoundary({
    required super.key,
    required super.child,
    required this.enabled,
  });

  final bool enabled;

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _RenderMessageRepaintBoundary(enabled);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMessageRepaintBoundary renderObject,
  ) => renderObject.enabled = enabled;
}

class _RenderMessageRepaintBoundary extends RenderRepaintBoundary {
  _RenderMessageRepaintBoundary(this._enabled);

  bool _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => _enabled;
}

enum _ConversationSlot { messages, composer, latest }

/// 先布局输入区，使渐变范围跟随输入区的实际可变高度。
/// 消息延伸到输入区上缘后方，避免产生单独的接缝。
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
  bool _detailsRestored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_detailsRestored) return;
    _detailsRestored = true;
    _detailsExpanded =
        PageStorage.maybeOf(context)?.readState(
          context,
          identifier: ValueKey('chat-details-${widget.message.id}'),
        ) ==
        true;
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.role == 'user';
    final isCompaction = message.role == 'compaction';
    final l10n = context.l10n;
    final requestError = message.requestError;
    final errorText = isCompaction && message.status == AiResponseStatus.failed
        ? '${l10n.aiCompactionFailed}  ${switch (message.processingSteps.lastOrNull) {
            final step? => aiCompactionFailureText(l10n, step).split('\n').first,
            _ => requestError == null ? l10n.aiCompactionNoRecordedReason : aiErrorText(l10n, requestError),
          }}'
        : requestError == null
        ? null
        : '${l10n.aiTurnFailed}  ${aiErrorText(l10n, requestError)}';
    final events = isCompaction && message.processEvents.isEmpty
        ? [
            AiProcessEvent(
              type: message.processingSteps.isEmpty
                  ? AiProcessEventType.status
                  : AiProcessEventType.action,
              status: message.processingSteps.isEmpty ? message.status : null,
              toolName: 'compact_context',
              operationId: message.id,
              elapsed: message.elapsed ?? Duration.zero,
              action: message.processingSteps.lastOrNull,
            ),
          ]
        : message.processEvents;
    final unchanged =
        isCompaction &&
        message.processingSteps.lastOrNull?.arguments['outcome'] == 'unchanged';
    final timeline = buildAiProcessTimeline(
      unchanged
          ? [
              for (final event in events)
                if (event.status != AiResponseStatus.completed) event,
            ]
          : events,
    );
    final turnFinished = switch (message.status) {
      AiResponseStatus.completed ||
      AiResponseStatus.failed ||
      AiResponseStatus.stopped => true,
      _ => false,
    };
    final messageContent = Align(
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
                if (message.toolName == 'agent_message')
                  AgentMessageSource(
                    message: message,
                    theme: widget.theme,
                    linkToAgent: true,
                  ),
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
                    allowExternalContent: !message.isRoleplayOpening,
                    useParentSelectionArea: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final content = Semantics(
      container: true,
      explicitChildNodes: true,
      child: messageContent,
    );
    if (isUser || (!isCompaction && message.elapsed == null)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message.role == 'assistant')
            SpeechReplyCard(
              key: ValueKey('ai-voice-reply-${message.id}'),
              message: message,
              theme: widget.theme,
            ),
          content,
          if (isUser || turnFinished)
            ChatMessageActions(message: message, theme: widget.theme),
        ],
      );
    }
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
              PageStorage.maybeOf(context)?.writeState(
                context,
                _detailsExpanded,
                identifier: ValueKey('chat-details-${message.id}'),
              );
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
                        [
                          ?processSummary?.label,
                          l10n.aiResponseElapsed(
                            formatAiElapsed(message.elapsed ?? Duration.zero),
                          ),
                        ].join(' · '),
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
            alignment: Alignment.topCenter,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _detailsExpanded
              ? Padding(
                  key: const ValueKey('ai-response-details-expanded'),
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (message.model != null)
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
                      if (events.isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: ProcessDetailsScrollView(
                            active: !turnFinished,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final entry in timeline)
                                  if (!(turnFinished &&
                                      entry.event.type ==
                                          AiProcessEventType.status &&
                                      entry.event.status ==
                                          AiResponseStatus.thinking))
                                    AiProcessEventView(
                                      key: ValueKey(entry.id),
                                      event: entry.event,
                                      theme: widget.theme,
                                      operationEvents: entry.events,
                                      inlineCompaction: !isCompaction,
                                      isThinking:
                                          message.status ==
                                              AiResponseStatus.thinking &&
                                          identical(entry.event, events.last),
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
        if (message.role == 'assistant')
          SpeechReplyCard(
            key: ValueKey('ai-voice-reply-${message.id}'),
            message: message,
            theme: widget.theme,
          ),
        if (message.content.isNotEmpty) content,
        if (errorText != null)
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
                    errorText,
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
          ChatMessageActions(
            message: message,
            theme: widget.theme,
            visibleError: errorText,
          ),
      ],
    );
  }
}
