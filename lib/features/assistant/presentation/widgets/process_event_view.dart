import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/interaction_decoration.dart';
import '../../data/chat_completion_client.dart';
import '../../domain/models.dart';
import 'code_block.dart';
import 'command_display.dart';
import 'command_policy_text.dart';
import 'error_text.dart';

String? aiResponseStatusLabel(
  BuildContext context,
  AiResponseStatus? status, {
  int retryAttempt = 1,
  String? toolName,
}) {
  final l10n = context.l10n;
  return switch (status) {
    AiResponseStatus.connecting => l10n.aiConnecting,
    AiResponseStatus.awaitingReply => l10n.aiAwaitingReply,
    AiResponseStatus.thinking => l10n.aiAssistantThinking,
    AiResponseStatus.streaming => l10n.aiStreaming,
    AiResponseStatus.preparingTools => l10n.aiPreparingTools,
    AiResponseStatus.executingTools => switch (toolName) {
      'list_directory' => l10n.aiExecutingListDirectory,
      'read_file' => l10n.aiExecutingReadFile,
      'write_file' => l10n.aiExecutingWriteFile,
      'run_command' => l10n.aiToolCommand,
      'read_process' => l10n.aiToolProcessRead,
      'write_process_input' => l10n.aiToolProcessInput,
      'stop_process' => l10n.aiToolProcessStop,
      'get_execution_environment' => l10n.aiToolEnvironment,
      'get_current_time' => l10n.aiExecutingReadTime,
      'request_user_input' => l10n.aiAskUser,
      'read_webpage' => l10n.aiAccessingWeb,
      'set_theme' => l10n.aiExecutingSetTheme,
      'set_language' => l10n.aiExecutingSetLanguage,
      'set_font' => l10n.aiExecutingSetFont,
      'set_sidebar_visibility' => l10n.aiExecutingSetSidebarVisibility,
      'set_sidebar_width' ||
      'set_settings_sidebar_width' => l10n.aiExecutingSetSidebarWidth,
      'set_content_split_width' => l10n.aiExecutingSetContentSplitWidth,
      null => l10n.aiExecutingTools,
      _ => l10n.aiExecutingNamedTool(toolName),
    },
    AiResponseStatus.accessingWeb => l10n.aiAccessingWeb,
    AiResponseStatus.awaitingApproval => l10n.aiAwaitingApproval,
    AiResponseStatus.awaitingUserInput => l10n.aiAwaitingUserInput,
    AiResponseStatus.retrying => l10n.aiRetryingRequest(
      retryAttempt,
      ChatCompletionClient.maxRetries,
    ),
    AiResponseStatus.failed => l10n.aiResponseFailed,
    AiResponseStatus.stopped => l10n.aiResponseStopped,
    AiResponseStatus.completed || null => null,
  };
}

/// 用时中的单条记录：简短阶段直接展示，思考和操作详情按需展开。
class AiProcessEventView extends StatefulWidget {
  const AiProcessEventView({
    super.key,
    required this.event,
    required this.theme,
    this.isThinking = false,
    this.operationEvents = const [],
    this.detailsEnabled = true,
  });

  final AiProcessEvent event;
  final AppTheme theme;
  final bool isThinking;
  final List<AiProcessEvent> operationEvents;
  final bool detailsEnabled;

  @override
  State<AiProcessEventView> createState() => _AiProcessEventViewState();
}

class _AiProcessEventViewState extends State<AiProcessEventView> {
  bool _expanded = false;
  bool _hovered = false;
  bool _focused = false;

  void _toggle() {
    final selection = context.findAncestorStateOfType<SelectionAreaState>();
    selection?.selectableRegion.clearSelection();
    selection?.selectableRegion.hideToolbar();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final theme = widget.theme;
    final isThinking = widget.isThinking;
    final l10n = context.l10n;
    final action = event.action;
    final toolName = action?.name ?? event.toolName;
    final retry = event.retry;
    final isWeb =
        action?.name == 'read_webpage' ||
        event.status == AiResponseStatus.accessingWeb;
    final questionCancelled = action != null && _questionWasCancelled(action);
    final failed =
        (action?.succeeded == false && !questionCancelled) ||
        event.status == AiResponseStatus.failed;
    final label = switch (event.type) {
      AiProcessEventType.status =>
        aiResponseStatusLabel(context, event.status, toolName: toolName) ??
            l10n.aiProcessCompleted,
      AiProcessEventType.reasoning =>
        isThinking ? l10n.aiAssistantThinking : l10n.aiProcessReasoning,
      AiProcessEventType.action => _operationResultLabel(context, action!),
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
      AiResponseStatus.awaitingApproval => Symbols.safety_check_rounded,
      AiResponseStatus.awaitingUserInput => Symbols.help_rounded,
      AiResponseStatus.retrying => Symbols.refresh_rounded,
      AiResponseStatus.completed => Symbols.check_rounded,
      AiResponseStatus.failed => Symbols.error_outline_rounded,
      AiResponseStatus.stopped => Symbols.stop_circle_rounded,
      null => Symbols.circle_rounded,
    };

    final args =
        action?.arguments ?? event.toolArguments ?? const <String, Object?>{};
    final target =
        args['path'] ?? args['url'] ?? args['executable'] ?? args['process_id'];
    final title =
        widget.detailsEnabled &&
            event.type == AiProcessEventType.status &&
            target is String
        ? '$label · ${_shortOperationTarget(target, web: toolName == 'read_webpage')}'
        : label;
    final failure = action?.webFailure;
    final resultSummary = action == null
        ? null
        : _operationSummary(context, action);
    final processResult = action == null ? null : _processResult(action);
    final questionDetails = action?.name == 'request_user_input'
        ? _questionAnswerDetails(context, action!)
        : null;
    final stages = widget.operationEvents
        .where((step) => step.type == AiProcessEventType.status)
        .toList();
    // 折叠展示一次操作做了什么，而不是显示工具返回的网页源码、文件正文或 JSON。
    final sections = <({String? title, String text})>[
      if (event.text.isNotEmpty) (title: null, text: event.text),
      if (toolName == 'run_command') ...[
        (title: l10n.aiCommandFull, text: formatAiCommand(args)),
        if (args['working_directory'] case final String directory)
          (title: l10n.aiCommandDirectory, text: directory),
      ] else if (target is String && target.isNotEmpty)
        (title: l10n.aiOperationTarget, text: target),
      if (questionDetails != null)
        (title: l10n.aiQuestionAnswerDetails, text: questionDetails),
      if (resultSummary != null)
        (title: l10n.aiOperationSummary, text: resultSummary),
      if (failure != null)
        (title: l10n.aiOperationError, text: aiErrorText(l10n, failure))
      else if (action != null &&
          !questionCancelled &&
          !action.succeeded &&
          (processResult == null
              ? action.output.isNotEmpty
              : (processResult['output'] as String? ?? '').isNotEmpty))
        (
          title: l10n.aiOperationError,
          text: processResult != null
              ? processResult['output'] as String
              : action.name == 'run_command'
              ? aiCommandPolicyOutputText(l10n, action.output) ?? action.output
              : action.output,
        ),
    ];
    final hasDetails =
        widget.detailsEnabled &&
        (questionDetails != null ||
            event.text.isNotEmpty ||
            (action != null && target is String) ||
            failure != null ||
            (action != null && !action.succeeded && action.output.isNotEmpty) ||
            (event.operationId != null && stages.isNotEmpty));
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final arrowDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);
    final labelColor = failed
        ? Theme.of(context).colorScheme.error
        : hasDetails && (_hovered || _focused)
        ? theme.textColorPrimary
        : hasDetails
        ? theme.textColorTertiary
        : theme.textColorSecondary;
    final titleView = InteractionDecoration.color(
      palette: theme,
      color: labelColor,
      // 箭头参与文字排版，换行后紧跟末行，而不是占据独立的右侧列。
      builder: (context, color) => Text.rich(
        TextSpan(
          text: title,
          children: [
            if (hasDetails)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: AnimatedRotation(
                    turns: _expanded ? .25 : 0,
                    duration: arrowDuration,
                    child: Icon(
                      Symbols.chevron_right_rounded,
                      size: 16,
                      color: color,
                    ),
                  ),
                ),
              ),
          ],
        ),
        style: TextStyle(color: color, fontSize: 12, height: 1.5),
      ),
    );
    final summary = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            failed
                ? Symbols.error_outline_rounded
                : isWeb
                ? Symbols.language_rounded
                : event.status == AiResponseStatus.awaitingUserInput ||
                      event.status == AiResponseStatus.awaitingApproval ||
                      event.status == AiResponseStatus.preparingTools
                ? statusIcon
                : toolName != null
                ? _toolIcon(toolName)
                : modelNote
                ? (isThinking ? Symbols.neurology_rounded : Symbols.blur_on)
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
        const SizedBox(width: 8),
        Flexible(child: titleView),
      ],
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            // 点击范围只包含图标、标题和箭头，右侧留白与时间不参与折叠。
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: hasDetails
                  ? Semantics(
                      expanded: _expanded,
                      child: InkWell(
                        onTap: _toggle,
                        onHover: (value) => setState(() => _hovered = value),
                        onFocusChange: (value) =>
                            setState(() => _focused = value),
                        mouseCursor: SystemMouseCursors.click,
                        hoverColor: Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        child: summary,
                      ),
                    )
                  : summary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatAiElapsed(event.elapsed),
            style: TextStyle(
              color: theme.textColorTertiary,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          // 收起后移除正文，避免全选选到未显示的思考、参数和返回内容。
          ClipRect(
            child: AnimatedSize(
              duration: duration,
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: !_expanded || !hasDetails
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(
                        left: 20,
                        top: 5,
                        bottom: 4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final stage in stages)
                            AiProcessEventView(
                              event: stage,
                              theme: theme,
                              detailsEnabled: false,
                            ),
                          for (final section in sections) ...[
                            if (section.title case final sectionTitle?)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  sectionTitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.textColorTertiary,
                                  ),
                                ),
                              ),
                            if ((toolName == 'run_command' &&
                                    section.title == l10n.aiCommandFull) ||
                                section.title == l10n.aiOperationError)
                              ChatCodeBlock(
                                text: section.text,
                                language: section.title == l10n.aiCommandFull
                                    ? aiCommandDisplayLanguage
                                    : 'text',
                                theme: theme,
                                maxBodyHeight: 160,
                                initialSoftWrap: true,
                              )
                            else
                              Text(
                                section.text,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                  color: theme.textColorSecondary,
                                ),
                              ),
                            const SizedBox(height: 6),
                          ],
                        ],
                      ),
                    ),
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
  'request_user_input' => Symbols.help_rounded,
  'list_directory' => Symbols.folder_open_rounded,
  'write_file' => Symbols.edit_document_rounded,
  'get_current_time' => Symbols.schedule_rounded,
  'read_webpage' => Symbols.language_rounded,
  'run_command' => Symbols.terminal_rounded,
  'get_execution_environment' => Symbols.computer_rounded,
  'read_process' => Symbols.article_rounded,
  'write_process_input' => Symbols.keyboard_rounded,
  'stop_process' => Symbols.stop_circle_rounded,
  'set_theme' => Symbols.palette_rounded,
  'set_language' => Symbols.translate_rounded,
  'set_font' => Symbols.font_download_rounded,
  'set_sidebar_visibility' ||
  'set_sidebar_width' ||
  'set_settings_sidebar_width' => Symbols.side_navigation_rounded,
  'set_content_split_width' => Symbols.view_column_rounded,
  _ => Symbols.play_circle_rounded,
};

String formatAiElapsed(Duration duration) {
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
    'request_user_input' => l10n.aiAskUser,
    'run_command' => '${l10n.aiToolCommand}: ${args['executable']}',
    'get_execution_environment' => l10n.aiToolEnvironment,
    'read_process' => '${l10n.aiToolProcessRead}: ${args['process_id']}',
    'write_process_input' =>
      '${l10n.aiToolProcessInput}: ${args['process_id']}',
    'stop_process' => '${l10n.aiToolProcessStop}: ${args['process_id']}',
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

String _shortOperationTarget(String target, {required bool web}) {
  if (web) {
    final uri = Uri.tryParse(target);
    return uri != null && uri.host.isNotEmpty ? uri.host : target;
  }
  final parts = target
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty);
  return parts.lastOrNull ?? target;
}

String _operationResultLabel(BuildContext context, AiProcessingStep action) {
  final l10n = context.l10n;
  final args = action.arguments;
  final rawTarget =
      args['path'] ?? args['url'] ?? args['executable'] ?? args['process_id'];
  final target = rawTarget is String
      ? _shortOperationTarget(rawTarget, web: action.name == 'read_webpage')
      : '';
  if (action.name == 'request_user_input') {
    if (action.succeeded) return l10n.aiQuestionAnswered;
    if (_questionWasCancelled(action)) return l10n.aiQuestionCancelled;
    return l10n.aiProcessActionFailed(l10n.aiAskUser);
  }
  final process = _processResult(action);
  if (action.name == 'run_command') {
    if (process?['timed_out'] == true) return l10n.aiCommandTimedOut(target);
    if (process?['stopped'] == true) {
      return process?['running'] == true
          ? l10n.aiCommandStopping(target)
          : l10n.aiProcessStoppedLabel(target);
    }
    final exitCode = process?['exit_code'];
    if (!action.succeeded || (exitCode is int && exitCode != 0)) {
      return l10n.aiCommandFailed(target);
    }
    if (exitCode is int) return l10n.aiCommandFinished(target);
    if (process?['running'] == true) return l10n.aiCommandStarted(target);
    return l10n.aiCommandRan(target);
  }
  if (action.name == 'read_process' && action.succeeded) {
    return l10n.aiProcessOutputRead(target);
  }
  if (!action.succeeded) {
    return action.name == 'read_webpage'
        ? l10n.aiWebFailed(target)
        : l10n.aiProcessActionFailed(
            _aiActionSummary(context, action.name, {
              ...args,
              if (args.containsKey('path')) 'path': target,
              if (args.containsKey('executable')) 'executable': target,
            }),
          );
  }
  return switch (action.name) {
    'read_webpage' => l10n.aiWebSucceeded(target),
    'list_directory' => l10n.aiDirectoryListed(target),
    'read_file' => l10n.aiFileReadCompleted(target),
    'write_file' => l10n.aiFileWriteCompleted(target),
    'get_current_time' => l10n.aiTimeReadCompleted,
    _ => l10n.aiProcessActionSucceeded(
      _aiActionSummary(context, action.name, args),
    ),
  };
}

// 旧记录及非进程结果不猜测状态，也不把“调用成功”当成“进程已完成”。
Map<String, dynamic>? _processResult(AiProcessingStep action) {
  if (!const {
    'run_command',
    'read_process',
    'stop_process',
  }.contains(action.name)) {
    return null;
  }
  try {
    final value = jsonDecode(action.output);
    if (value is Map<String, dynamic> &&
        value['running'] is bool &&
        (value['exit_code'] == null || value['exit_code'] is int) &&
        (value['output'] == null || value['output'] is String)) {
      return value;
    }
  } on FormatException {
    // 兼容旧版本的纯文本结果，仍保留原始错误说明。
  }
  return null;
}

String? _operationSummary(BuildContext context, AiProcessingStep action) {
  final l10n = context.l10n;
  final result = _processResult(action);
  if (result != null) {
    if (result['timed_out'] == true) return l10n.aiProcessTimedOutSummary;
    if (result['stopped'] == true) {
      return result['running'] == true
          ? l10n.aiProcessStoppingSummary
          : l10n.aiProcessStoppedSummary;
    }
    final code = result['exit_code'];
    if (code is int) return l10n.aiProcessExitedSummary(code);
    if (result['running'] == true) return l10n.aiProcessRunningSummary;
    return null;
  }
  if (!action.succeeded) return null;
  return switch (action.name) {
    'run_command' ||
    'read_process' ||
    'stop_process' ||
    'request_user_input' => null,
    'write_process_input' => l10n.aiProcessInputSentSummary,
    'read_webpage' => l10n.aiWebReadSummary,
    'list_directory' => l10n.aiDirectoryReadSummary,
    'read_file' => l10n.aiFileReadSummary,
    'write_file' => l10n.aiFileWriteSummary,
    'get_current_time' => l10n.aiTimeReadCompleted,
    _ => _aiActionSummary(context, action.name, action.arguments),
  };
}

/// 只展示用户可读的问题与回答，不把工具协议 JSON 当作错误详情。
String? _questionAnswerDetails(BuildContext context, AiProcessingStep action) {
  final questions = action.arguments['questions'];
  if (questions is! List) return null;
  Map? answers;
  try {
    final result = jsonDecode(action.output);
    if (result is Map && result['answers'] is Map) {
      answers = result['answers'] as Map;
    }
  } on FormatException {
    // 参数无效或工具失败的历史记录仍可显示实际收到的问题。
  }
  final entries = <String>[];
  for (final value in questions) {
    if (value is! Map || value['question'] is! String) continue;
    final answer = answers?[value['id']];
    final items = answer is Map ? answer['answers'] : null;
    final text = items is List ? items.whereType<String>().join('\n') : '';
    entries.add(
      [
        value['question'] as String,
        if (text.isNotEmpty) '${context.l10n.aiQuestionAnswerLabel}: $text',
        if (text.isEmpty && _questionWasCancelled(action))
          context.l10n.aiQuestionCancelled,
      ].join('\n'),
    );
  }
  return entries.isEmpty ? null : entries.join('\n\n');
}

bool _questionWasCancelled(AiProcessingStep action) {
  if (action.name != 'request_user_input' || action.succeeded) return false;
  try {
    final result = jsonDecode(action.output);
    return result is Map && result['cancelled'] == true;
  } on FormatException {
    return false;
  }
}
