import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/interaction_decoration.dart';
import '../../data/chat_completion_client.dart';
import '../../domain/models.dart';
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
      'get_current_time' => l10n.aiExecutingReadTime,
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
    final failed =
        action?.succeeded == false || event.status == AiResponseStatus.failed;
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
      AiResponseStatus.retrying => Symbols.refresh_rounded,
      AiResponseStatus.completed => Symbols.check_rounded,
      AiResponseStatus.failed => Symbols.error_outline_rounded,
      AiResponseStatus.stopped => Symbols.stop_circle_rounded,
      null => Symbols.circle_rounded,
    };

    final args =
        action?.arguments ?? event.toolArguments ?? const <String, Object?>{};
    final target = args['path'] ?? args['url'];
    final title =
        widget.detailsEnabled &&
            event.type == AiProcessEventType.status &&
            target is String
        ? '$label · ${_shortOperationTarget(target, web: toolName == 'read_webpage')}'
        : label;
    final failure = action?.webFailure;
    final stages = widget.operationEvents
        .where((step) => step.type == AiProcessEventType.status)
        .toList();
    // 折叠展示一次操作做了什么，而不是显示工具返回的网页源码、文件正文或 JSON。
    final sections = <({String? title, String text})>[
      if (event.text.isNotEmpty) (title: null, text: event.text),
      if (target is String && target.isNotEmpty)
        (title: l10n.aiOperationTarget, text: target),
      if (action != null && action.succeeded)
        (
          title: l10n.aiOperationSummary,
          text: _operationSummary(context, action),
        ),
      if (failure != null)
        (title: l10n.aiOperationError, text: aiErrorText(l10n, failure))
      else if (action != null && !action.succeeded && action.output.isNotEmpty)
        (title: l10n.aiOperationError, text: action.output),
    ];
    final hasDetails =
        widget.detailsEnabled &&
        (event.text.isNotEmpty ||
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
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              failed
                  ? Symbols.error_outline_rounded
                  : isWeb
                  ? Symbols.language_rounded
                  : event.status == AiResponseStatus.awaitingApproval ||
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
          Expanded(
            child: InteractionDecoration.color(
              palette: theme,
              color: labelColor,
              builder: (context, color) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(color: color, fontSize: 12, height: 1.5),
                    ),
                  ),
                  if (hasDetails) ...[
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? .25 : 0,
                      duration: arrowDuration,
                      child: Icon(
                        Symbols.chevron_right_rounded,
                        size: 16,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
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
          if (hasDetails)
            Semantics(
              expanded: _expanded,
              child: InkWell(
                onTap: _toggle,
                onHover: (value) => setState(() => _hovered = value),
                onFocusChange: (value) => setState(() => _focused = value),
                mouseCursor: SystemMouseCursors.click,
                hoverColor: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                child: row,
              ),
            )
          else
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
  final rawTarget = args['path'] ?? args['url'];
  final target = rawTarget is String
      ? _shortOperationTarget(rawTarget, web: action.name == 'read_webpage')
      : '';
  if (!action.succeeded) {
    return action.name == 'read_webpage'
        ? l10n.aiWebFailed(target)
        : l10n.aiProcessActionFailed(
            _aiActionSummary(context, action.name, {
              ...args,
              if (args.containsKey('path')) 'path': target,
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

String _operationSummary(BuildContext context, AiProcessingStep action) {
  final l10n = context.l10n;
  return switch (action.name) {
    'read_webpage' => l10n.aiWebReadSummary,
    'list_directory' => l10n.aiDirectoryReadSummary,
    'read_file' => l10n.aiFileReadSummary,
    'write_file' => l10n.aiFileWriteSummary,
    'get_current_time' => l10n.aiTimeReadCompleted,
    _ => _aiActionSummary(context, action.name, action.arguments),
  };
}
