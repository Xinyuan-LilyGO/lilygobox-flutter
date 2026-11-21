import 'package:lilygobox/core/l10n/delegates.dart';

import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/definition.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/code_block.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/command_display.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/process_event_view.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_symbols_icons/symbols.dart';

Finder processText(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      (widget.data ??
              widget.textSpan?.toPlainText(includePlaceholders: false)) ==
          text,
);

Widget host(
  AiProcessEvent event, {
  ThemeType type = ThemeType.light,
  String locale = 'en',
  bool thinking = false,
  bool disableAnimations = false,
  double width = 320,
  ValueChanged<SelectedContent?>? onSelectionChanged,
  List<AiProcessEvent> stages = const [],
}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: appLocalizationDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        size: const Size(340, 700),
        textScaler: const TextScaler.linear(1.3),
      ),
      child: SelectionArea(
        onSelectionChanged: onSelectionChanged,
        child: SizedBox(
          width: width,
          child: AiProcessEventView(
            key: const ValueKey('stable-operation'),
            event: event,
            theme: MaterialPalette.create(type),
            isThinking: thinking,
            operationEvents: stages,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'automatic compaction distinguishes its duration from turn elapsed time',
    (tester) async {
      final event = AiProcessEvent(
        type: AiProcessEventType.action,
        elapsed: const Duration(seconds: 12),
        action: AiProcessingStep(
          name: 'compact_context',
          arguments: {
            'trigger': 'auto',
            'durationMicros': 3200000,
            'outcome': 'compacted',
          },
          succeeded: true,
        ),
      );
      await tester.pumpWidget(host(event, locale: 'zh'));
      expect(processText('自动压缩上下文 · 耗时 3.2 秒'), findsOneWidget);
      expect(find.text('00:12:000'), findsOneWidget);
    },
  );
  testWidgets('compaction details preserve the service error and HTTP status', (
    tester,
  ) async {
    final event = AiProcessEvent(
      type: AiProcessEventType.action,
      elapsed: const Duration(seconds: 1),
      action: AiProcessingStep(
        name: 'compact_context',
        arguments: {
          'trigger': 'manual',
          'outcome': 'failed',
          'httpStatus': 404,
          'providerCode': 'model_not_found',
        },
        output: 'The requested model was not found.',
        succeeded: false,
      ),
    );
    await tester.pumpWidget(host(event));
    await tester.tap(processText('Context compaction failed'));
    await tester.pumpAndSettle();
    final block = tester.widget<ChatCodeBlock>(find.byType(ChatCodeBlock));
    expect(block.text, contains('The requested model was not found.'));
    expect(block.text, contains('HTTP 404'));
    expect(block.text, contains('Service error code: model_not_found'));
  });

  for (final (tool, label, output, summary) in [
    ('search_chat_history', '搜索原始聊天记录', '{"matches":[]}', '返回了 0 条匹配消息'),
    (
      'read_chat_history',
      '读取聊天原文',
      '{"message":{"message_id":"msg-2"}}',
      '已读取消息 msg-2',
    ),
    ('read_chat_history', '读取聊天原文', '{"message":null}', '当前对话中未找到该消息。'),
  ]) {
    testWidgets('shows the original history action and result: $summary', (
      tester,
    ) async {
      final stage = AiProcessEvent(
        type: AiProcessEventType.status,
        status: AiResponseStatus.executingTools,
        toolName: tool,
        operationId: 'op',
        elapsed: Duration.zero,
      );
      final action = AiProcessEvent(
        type: AiProcessEventType.action,
        operationId: 'op',
        elapsed: const Duration(seconds: 1),
        action: AiProcessingStep(
          name: tool,
          arguments: {},
          succeeded: true,
          output: output,
        ),
      );
      await tester.pumpWidget(host(action, locale: 'zh', stages: [stage]));
      expect(processText('已执行：$label'), findsOneWidget);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(processText(label), findsOneWidget);
      expect(processText(summary), findsOneWidget);
    });
  }
  testWidgets(
    'latest process summary follows steps and final status overrides stale steps',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      const running = AiProcessEvent(
        type: AiProcessEventType.status,
        elapsed: Duration.zero,
        status: AiResponseStatus.executingTools,
        toolName: 'read_file',
        toolArguments: {'path': 'config.json'},
      );
      const reply = AiMessage(
        id: 'latest',
        role: 'assistant',
        content: '',
        status: AiResponseStatus.executingTools,
        processEvents: [running],
      );
      final internal = aiProcessEventSummary(context, running);
      expect(aiMessageProcessSummary(context, reply), internal);
      expect(internal.label, 'Reading file · config.json');
      expect(internal.icon, Symbols.description_rounded);
      final done = aiMessageProcessSummary(
        context,
        reply.copyWith(status: AiResponseStatus.completed),
      );
      expect(done!.label, 'Completed');
      expect(done.icon, Symbols.check_circle_rounded);
      expect(done.fill, 1);
      final stopped = aiMessageProcessSummary(
        context,
        reply.copyWith(status: AiResponseStatus.stopped),
      );
      expect(stopped!.label, 'Stopped');
    },
  );

  for (final reasoning in [true, false]) {
    testWidgets(
      'detail rows fade and resize in both directions (reasoning=$reasoning)',
      (tester) async {
        final event = reasoning
            ? const AiProcessEvent(
                type: AiProcessEventType.reasoning,
                elapsed: Duration.zero,
                text: 'Animated reasoning',
              )
            : AiProcessEvent(
                type: AiProcessEventType.action,
                elapsed: Duration.zero,
                action: AiProcessingStep(
                  name: 'read_file',
                  arguments: {'path': 'D:/project/config.txt'},
                  succeeded: true,
                  output: 'File read',
                ),
              );
        await tester.pumpWidget(host(event));
        await tester.pumpAndSettle();
        final view = find.byType(AnimatedSwitcher);
        final collapsedHeight = tester.getSize(view).height;
        await tester.tap(find.byType(InkWell).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final content = find.byKey(
          const ValueKey('ai-process-details-expanded'),
        );
        final fade = find
            .ancestor(of: content, matching: find.byType(FadeTransition))
            .first;
        final size = find
            .ancestor(of: content, matching: find.byType(SizeTransition))
            .first;
        expect(
          tester.widget<FadeTransition>(fade).opacity.value,
          inExclusiveRange(0, 1),
        );
        expect(
          tester.widget<SizeTransition>(size).sizeFactor.value,
          inExclusiveRange(0, 1),
        );
        expect(tester.getSize(view).height, greaterThan(collapsedHeight));
        await tester.pumpAndSettle();
        final expandedHeight = tester.getSize(view).height;
        await tester.tap(find.byType(InkWell).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(content, findsOneWidget);
        expect(
          tester.widget<FadeTransition>(fade).opacity.value,
          inExclusiveRange(0, 1),
        );
        expect(tester.getSize(view).height, lessThan(expandedHeight));
        final outgoing = find.ancestor(
          of: content,
          matching: find.byType(IgnorePointer),
        );
        expect(
          tester
              .widgetList<IgnorePointer>(outgoing)
              .any((widget) => widget.ignoring),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(content, findsNothing);
        expect(tester.getSize(view).height, collapsedHeight);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('detail rows switch immediately when animations are disabled', (
    tester,
  ) async {
    const event = AiProcessEvent(
      type: AiProcessEventType.reasoning,
      elapsed: Duration.zero,
      text: 'Reduced motion reasoning',
    );
    await tester.pumpWidget(host(event, disableAnimations: true));
    await tester.tap(find.byType(InkWell));
    await tester.pump();
    final expanded = find.byKey(const ValueKey('ai-process-details-expanded'));
    expect(expanded, findsOneWidget);
    final fade = find
        .ancestor(of: expanded, matching: find.byType(FadeTransition))
        .first;
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(expanded, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('question details show readable answers and remain selectable', (
    tester,
  ) async {
    final event = AiProcessEvent(
      type: AiProcessEventType.action,
      elapsed: const Duration(seconds: 1),
      action: AiProcessingStep(
        name: 'request_user_input',
        arguments: {
          'questions': [
            {'id': 'target', 'question': 'Which folder?'},
          ],
        },
        succeeded: true,
        output: jsonEncode({
          'cancelled': false,
          'answers': {
            'target': {
              'answers': ['Project', 'Use the current folder'],
            },
          },
        }),
      ),
    );
    String? selected;
    await tester.pumpWidget(
      host(
        event,
        onSelectionChanged: (content) => selected = content?.plainText,
      ),
    );
    await tester.pumpAndSettle();
    expect(processText('Answers received'), findsOneWidget);
    expect(find.textContaining('Which folder?'), findsNothing);
    await tester.tap(find.byIcon(Symbols.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Questions and answers'), findsOneWidget);
    expect(
      find.text('Which folder?\nAnswer: Project\nUse the current folder'),
      findsOneWidget,
    );
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.toolbar);
    await tester.pump();
    expect(selected, contains('Use the current folder'));
    expect(selected, isNot(contains('"answers"')));
  });

  testWidgets('cancelled questions do not render tool JSON as an error', (
    tester,
  ) async {
    final output = jsonEncode({'cancelled': true, 'answers': {}});
    final event = AiProcessEvent(
      type: AiProcessEventType.action,
      elapsed: Duration.zero,
      action: AiProcessingStep(
        name: 'request_user_input',
        arguments: {
          'questions': [
            {'id': 'target', 'question': 'Which folder?'},
          ],
        },
        succeeded: false,
        output: output,
      ),
    );
    await tester.pumpWidget(host(event));
    await tester.pumpAndSettle();
    expect(processText('Question cancelled'), findsOneWidget);
    await tester.tap(find.byIcon(Symbols.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text(output), findsNothing);
    expect(find.byType(ChatCodeBlock), findsNothing);
    expect(find.text('Which folder?\nQuestion cancelled'), findsOneWidget);
  });

  testWidgets(
    'full command preserves scripts, arguments and working directory in selection',
    (tester) async {
      const args = <String, Object?>{
        'executable': 'C:/Program Files/PowerShell/pwsh.exe',
        'arguments': [
          '-NoProfile',
          '-Command',
          "Write-Output 'hello world'\nWrite-Output done",
          '',
        ],
        'working_directory': 'C:/firmware/project',
      };
      final event = AiProcessEvent(
        type: AiProcessEventType.action,
        elapsed: Duration.zero,
        action: AiProcessingStep(
          name: 'run_command',
          arguments: args,
          succeeded: true,
          output: jsonEncode({'exit_code': 0, 'running': false}),
        ),
      );
      String? selected;
      await tester.pumpWidget(
        host(event, onSelectionChanged: (value) => selected = value?.plainText),
      );
      await tester.pumpAndSettle();
      final command = formatAiCommand(args);
      expect(processText(command), findsNothing);
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(processText('Full command'), findsOneWidget);
      expect(processText('Target'), findsNothing);
      expect(processText(command), findsOneWidget);
      expect(
        tester
            .widget<ChatCodeBlock>(find.byType(ChatCodeBlock))
            .initialSoftWrap,
        isTrue,
      );
      expect(tester.widget<Text>(processText(command)).softWrap, isTrue);
      expect(processText('Working directory'), findsOneWidget);
      expect(processText(args['working_directory'] as String), findsOneWidget);
      expect(processText(args['executable'] as String), findsNothing);
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      region.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(selected, contains(command));
      expect(selected, contains('C:/firmware/project'));
      expect(tester.takeException(), isNull);
    },
  );

  for (final type in ThemeType.values) {
    for (final locale in ['en', 'zh']) {
      testWidgets(
        'reasoning expands, streams without closing, and deselects when hidden ($type/$locale)',
        (tester) async {
          const first = AiProcessEvent(
            type: AiProcessEventType.reasoning,
            elapsed: Duration.zero,
            text: 'Initial thought',
          );
          await tester.pumpWidget(
            host(first, type: type, locale: locale, thinking: true),
          );
          await tester.pumpAndSettle();
          expect(processText('Initial thought'), findsNothing);
          final trigger = tester.getRect(find.byType(InkWell));
          final timestamp = tester.getRect(processText('00:00:000'));
          expect(trigger.right, lessThan(timestamp.left));
          await tester.tapAt(
            Offset((trigger.right + timestamp.left) / 2, trigger.center.dy),
          );
          await tester.pumpAndSettle();
          expect(processText('Initial thought'), findsNothing);
          await tester.tap(processText('00:00:000'));
          await tester.pumpAndSettle();
          expect(processText('Initial thought'), findsNothing);
          final selection = tester.state<SelectableRegionState>(
            find.byType(SelectableRegion),
          );
          selection.clearSelection();
          selection.hideToolbar();
          await tester.pumpAndSettle();
          await tester.tap(find.byType(InkWell));
          await tester.pumpAndSettle();
          expect(processText('Initial thought'), findsOneWidget);
          const next = AiProcessEvent(
            type: AiProcessEventType.reasoning,
            elapsed: Duration.zero,
            text: 'Initial thought plus more',
          );
          await tester.pumpWidget(host(next, type: type, locale: locale));
          await tester.pumpAndSettle();
          expect(processText('Initial thought plus more'), findsOneWidget);
          final region = tester.state<SelectableRegionState>(
            find.byType(SelectableRegion),
          );
          bool hasSelection() => find
              .byType(RichText)
              .evaluate()
              .any(
                (element) => (element.renderObject! as RenderParagraph)
                    .selections
                    .any((range) => !range.isCollapsed),
              );
          region.selectAll(SelectionChangedCause.toolbar);
          await tester.pump();
          expect(hasSelection(), isTrue);
          region.hideToolbar();
          await tester.pumpAndSettle();
          await tester.tap(find.byType(InkWell));
          await tester.pumpAndSettle();
          expect(processText('Initial thought plus more'), findsNothing);
          expect(hasSelection(), isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'open operation stays open when its running row becomes a result',
    (tester) async {
      const start = AiProcessEvent(
        type: AiProcessEventType.status,
        elapsed: Duration.zero,
        operationId: 'one',
        toolName: 'write_file',
        toolArguments: {'path': 'a.txt', 'content': 'New file text'},
        status: AiResponseStatus.executingTools,
      );
      await tester.pumpWidget(host(start, stages: [start]));
      await tester.pumpAndSettle();
      expect(processText('Writing file · a.txt'), findsOneWidget);
      expect(find.textContaining('New file text'), findsNothing);
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.textContaining('New file text'), findsNothing);
      expect(processText('Writing file'), findsOneWidget);
      final finish = AiProcessEvent(
        type: AiProcessEventType.action,
        elapsed: const Duration(seconds: 1),
        operationId: 'one',
        action: AiProcessingStep(
          name: 'write_file',
          arguments: {'path': 'a.txt', 'content': 'New file text'},
          succeeded: true,
          output: 'Write completed',
        ),
      );
      await tester.pumpWidget(host(finish, stages: [start, finish]));
      await tester.pumpAndSettle();
      expect(processText('Wrote file · a.txt'), findsOneWidget);
      expect(processText('Writing file · a.txt'), findsNothing);
      expect(processText('Write completed'), findsNothing);
      expect(
        processText('Wrote the content to the target file.'),
        findsOneWidget,
      );
      expect(find.byType(InkWell), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'simple stages and target-only operations have no expansion affordance',
    (tester) async {
      const start = AiProcessEvent(
        type: AiProcessEventType.status,
        elapsed: Duration.zero,
        toolName: 'list_directory',
        toolArguments: {'path': 'folder'},
        status: AiResponseStatus.executingTools,
      );
      await tester.pumpWidget(host(start));
      await tester.pumpAndSettle();
      expect(processText('Listing directory · folder'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
      expect(find.byIcon(Symbols.chevron_right_rounded), findsNothing);
      const approval = AiProcessEvent(
        type: AiProcessEventType.status,
        elapsed: Duration.zero,
        status: AiResponseStatus.awaitingApproval,
      );
      await tester.pumpWidget(host(approval));
      await tester.pumpAndSettle();
      final shield = tester.widget<Icon>(
        find.byIcon(Symbols.safety_check_rounded),
      );
      expect(shield.fill, 1);
      expect(find.byType(InkWell), findsNothing);
    },
  );

  testWidgets(
    'failure keeps summary visible and exposes actual error on expansion',
    (tester) async {
      final failure = AiProcessEvent(
        type: AiProcessEventType.action,
        elapsed: Duration.zero,
        action: AiProcessingStep(
          name: 'read_file',
          arguments: {'path': 'a.txt'},
          succeeded: false,
          output: 'Access denied details',
        ),
      );
      await tester.pumpWidget(host(failure));
      await tester.pumpAndSettle();
      expect(processText('Access denied details'), findsNothing);
      expect(processText('Failed: Read file: a.txt'), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(processText('Access denied details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('file content is not used as the operation description', (
    tester,
  ) async {
    final event = AiProcessEvent(
      type: AiProcessEventType.action,
      elapsed: Duration.zero,
      action: AiProcessingStep(
        name: 'read_file',
        arguments: {'path': 'note.txt'},
        succeeded: true,
        output: 'A short note.',
      ),
    );
    await tester.pumpWidget(host(event));
    await tester.pumpAndSettle();
    expect(processText('A short note.'), findsNothing);
    expect(find.byType(InkWell), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(processText('Read the file content.'), findsOneWidget);
    expect(processText('A short note.'), findsNothing);
  });

  for (final (status, label) in [
    (AiResponseStatus.permissionReviewApproved, '自动审批通过'),
    (AiResponseStatus.permissionReviewDenied, '自动审批拒绝'),
    (AiResponseStatus.permissionReviewFailed, '自动审批失败'),
    (AiResponseStatus.manualApprovalGranted, '人工审批通过'),
    (AiResponseStatus.manualApprovalDenied, '人工审批拒绝'),
    (AiResponseStatus.manualApprovalCancelled, '人工审批已取消'),
    (AiResponseStatus.manualApprovalTimedOut, '人工审批超时'),
    (AiResponseStatus.customApprovalGranted, '自定义审批通过'),
    (AiResponseStatus.customApprovalNotGranted, '自定义规则未直接放行'),
  ]) {
    testWidgets('a file operation shows $label in its elapsed details', (
      tester,
    ) async {
      final (stageStatus, stageLabel) = switch (status) {
        AiResponseStatus.manualApprovalGranted ||
        AiResponseStatus.manualApprovalDenied ||
        AiResponseStatus.manualApprovalCancelled ||
        AiResponseStatus.manualApprovalTimedOut => (
          AiResponseStatus.awaitingApproval,
          '等待批准',
        ),
        AiResponseStatus.customApprovalGranted ||
        AiResponseStatus.customApprovalNotGranted => (
          AiResponseStatus.preparingTools,
          '正在准备工具调用',
        ),
        _ => (AiResponseStatus.reviewingPermission, '正在自动审批'),
      };
      final model = switch (status) {
        AiResponseStatus.permissionReviewApproved => 'gpt-5.4',
        AiResponseStatus.permissionReviewDenied => 'review-model',
        _ => null,
      };
      final effort = status == AiResponseStatus.permissionReviewApproved
          ? AiReasoningEffort.none
          : null;
      final reviewing = AiProcessEvent(
        type: AiProcessEventType.status,
        elapsed: const Duration(seconds: 1),
        status: stageStatus,
        operationId: 'file',
        toolName: 'read_file',
        model: model,
        reasoningEffort: effort,
      );
      final outcome = AiProcessEvent(
        type: AiProcessEventType.status,
        elapsed: const Duration(seconds: 2),
        status: status,
        operationId: 'file',
        toolName: 'read_file',
      );
      final finish = AiProcessEvent(
        type: AiProcessEventType.action,
        elapsed: const Duration(seconds: 3),
        operationId: 'file',
        action: AiProcessingStep(
          name: 'read_file',
          arguments: {'path': 'note.txt'},
          succeeded:
              status == AiResponseStatus.permissionReviewApproved ||
              status == AiResponseStatus.manualApprovalGranted ||
              status == AiResponseStatus.customApprovalGranted,
        ),
      );
      await tester.pumpWidget(
        host(finish, locale: 'zh', stages: [reviewing, outcome, finish]),
      );
      expect(processText(label), findsNothing);
      expect(find.textContaining('模型：'), findsNothing);
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(processText(stageLabel), findsOneWidget);
      expect(processText(label), findsOneWidget);
      if (model != null) {
        final modelLine = find.text('模型：$model');
        expect(modelLine, findsOneWidget);
        expect(
          tester.getTopLeft(modelLine).dy,
          lessThan(tester.getTopLeft(processText(stageLabel)).dy),
        );
      } else {
        expect(find.textContaining('模型：'), findsNothing);
      }
      expect(
        find.text('思考强度：关闭'),
        effort == null ? findsNothing : findsOneWidget,
      );
      expect(find.text('00:01:000'), findsOneWidget);
      expect(find.text('00:02:000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a skipped approval shows the configured reviewer as not called',
    (tester) async {
      const skipped = AiProcessEvent(
        type: AiProcessEventType.status,
        status: AiResponseStatus.permissionReviewSkipped,
        operationId: 'file',
        toolName: 'read_file',
        model: 'deepseek-flash',
        reasoningEffort: AiReasoningEffort.none,
        elapsed: Duration(seconds: 1),
      );
      await tester.pumpWidget(host(skipped, stages: [skipped]));
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(
        find.text('Configured approval model: deepseek-flash (not called)'),
        findsOneWidget,
      );
      expect(find.text('Reasoning effort: Off'), findsOneWidget);
      expect(find.text('Model: deepseek-flash'), findsNothing);
    },
  );

  testWidgets('a web operation expands its stages, not HTTP content or JSON', (
    tester,
  ) async {
    const url = 'https://docs.example.com/path/index.html';
    const prepare = AiProcessEvent(
      type: AiProcessEventType.status,
      elapsed: Duration.zero,
      status: AiResponseStatus.preparingTools,
      operationId: 'web',
      toolName: 'read_webpage',
    );
    const approval = AiProcessEvent(
      type: AiProcessEventType.status,
      elapsed: Duration(seconds: 1),
      status: AiResponseStatus.awaitingApproval,
      operationId: 'web',
      toolName: 'read_webpage',
    );
    const running = AiProcessEvent(
      type: AiProcessEventType.status,
      elapsed: Duration(seconds: 2),
      status: AiResponseStatus.accessingWeb,
      operationId: 'web',
      toolName: 'read_webpage',
    );
    final finish = AiProcessEvent(
      type: AiProcessEventType.action,
      elapsed: const Duration(seconds: 3),
      operationId: 'web',
      action: AiProcessingStep(
        name: 'read_webpage',
        arguments: {'url': url},
        succeeded: true,
        output: '<!DOCTYPE html><html>RAW_HTTP_MARKER</html>',
      ),
    );
    await tester.pumpWidget(
      host(finish, stages: [prepare, approval, running, finish]),
    );
    await tester.pumpAndSettle();
    expect(processText('Accessed webpage docs.example.com'), findsOneWidget);
    expect(processText('Preparing tool calls'), findsNothing);
    expect(processText(url), findsNothing);
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(processText('Preparing tool calls'), findsOneWidget);
    expect(processText('Waiting for approval'), findsOneWidget);
    expect(processText('Accessing webpage'), findsOneWidget);
    expect(processText(url), findsOneWidget);
    expect(processText('Read the webpage content.'), findsOneWidget);
    expect(find.textContaining('RAW_HTTP_MARKER'), findsNothing);
    expect(find.textContaining('"url"'), findsNothing);
    expect(
      tester.widget<Icon>(find.byIcon(Symbols.safety_check_rounded)).fill,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['en', 'zh']) {
    for (final state in [
      'running',
      'exited',
      'failed',
      'timeout',
      'stopped',
      'stopping',
      'invalid_result',
    ]) {
      testWidgets(
        'command displays a short target and actual result: $locale/$state',
        (tester) async {
          const executable = 'C:/tools/flasher.exe';
          final succeeded = ![
            'failed',
            'timeout',
            'stopped',
            'stopping',
          ].contains(state);
          final event = AiProcessEvent(
            type: AiProcessEventType.action,
            elapsed: const Duration(seconds: 2),
            action: AiProcessingStep(
              name: 'run_command',
              arguments: {'executable': executable},
              succeeded: succeeded,
              output: state == 'invalid_result'
                  ? 'Invalid result'
                  : jsonEncode({
                      'ok': succeeded,
                      'process_id': 'process-0',
                      'running': state == 'running' || state == 'stopping',
                      'exit_code': state == 'exited'
                          ? 0
                          : state == 'failed'
                          ? 7
                          : null,
                      'timed_out': state == 'timeout',
                      'stopped': [
                        'stopped',
                        'stopping',
                        'timeout',
                      ].contains(state),
                      'output': state == 'failed' ? 'Device not found' : '',
                    }),
            ),
          );
          await tester.pumpWidget(host(event, locale: locale, width: 540));
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(AiProcessEventView)),
          );
          final label = switch (state) {
            'running' => l10n.aiCommandStarted('flasher.exe'),
            'exited' => l10n.aiCommandFinished('flasher.exe'),
            'failed' => l10n.aiCommandFailed('flasher.exe'),
            'stopping' => l10n.aiCommandStopping('flasher.exe'),
            'timeout' => l10n.aiCommandTimedOut('flasher.exe'),
            'stopped' => l10n.aiProcessStoppedLabel('flasher.exe'),
            _ => l10n.aiActionUnknown,
          };
          expect(processText(label), findsOneWidget);
          expect(processText(executable), findsNothing);
          await tester.tap(find.byType(InkWell));
          await tester.pumpAndSettle();
          expect(processText(executable), findsOneWidget);
          final summary = switch (state) {
            'running' => l10n.aiProcessRunningSummary,
            'exited' => l10n.aiProcessExitedSummary(0),
            'failed' => l10n.aiProcessExitedSummary(7),
            'timeout' => l10n.aiProcessTimedOutSummary,
            'stopped' => l10n.aiProcessStoppedSummary,
            'stopping' => l10n.aiProcessStoppingSummary,
            _ => null,
          };
          expect(
            processText(l10n.aiOperationSummary),
            summary == null ? findsNothing : findsOneWidget,
          );
          if (summary != null) expect(processText(summary), findsOneWidget);
          expect(find.textContaining('"process_id"'), findsNothing);
          if (state == 'failed') {
            expect(processText('Device not found'), findsOneWidget);
            final errorBlock = tester.widget<ChatCodeBlock>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is ChatCodeBlock &&
                    widget.text == 'Device not found',
              ),
            );
            expect(errorBlock.language, 'text');
            expect(errorBlock.maxBodyHeight, 160);
            expect(errorBlock.initialSoftWrap, isTrue);
          }
          expect(processText('Run local command: $executable'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'process output detail reports process state without repeating the operation',
    (tester) async {
      final event = AiProcessEvent(
        type: AiProcessEventType.action,
        elapsed: Duration.zero,
        action: AiProcessingStep(
          name: 'read_process',
          arguments: {'process_id': 'process-0'},
          succeeded: true,
          output: jsonEncode({
            'running': false,
            'exit_code': 0,
            'output': 'Done',
          }),
        ),
      );
      await tester.pumpWidget(host(event));
      await tester.pumpAndSettle();
      expect(processText('Read process output · process-0'), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(processText('process-0'), findsOneWidget);
      expect(processText('The process exited with code 0.'), findsOneWidget);
      expect(processText('Read process output: process-0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wrapped operation keeps disclosure beside the final text line', (
    tester,
  ) async {
    const executable =
        'C:/tools/firmware_download_tools/flash_download_tool_3.9.7/firmware_download_run.exe';
    final event = AiProcessEvent(
      type: AiProcessEventType.action,
      elapsed: const Duration(seconds: 1),
      action: AiProcessingStep(
        name: 'run_command',
        arguments: {'executable': executable},
        succeeded: true,
        output: jsonEncode({'running': true, 'process_id': 'process-0'}),
      ),
    );
    String? selected;
    await tester.pumpWidget(
      host(
        event,
        onSelectionChanged: (content) => selected = content?.plainText,
      ),
    );
    await tester.pumpAndSettle();
    final title = processText('Process started · firmware_download_run.exe');
    final titleText = tester
        .widget<Text>(title)
        .textSpan!
        .toPlainText(includePlaceholders: false);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: title, matching: find.byType(RichText)).first,
    );
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: titleText.length),
    );
    expect(boxes.length, greaterThan(1));
    final last = boxes.last;
    final end = paragraph.localToGlobal(
      Offset(last.right, (last.top + last.bottom) / 2),
    );
    final arrow = tester.getRect(find.byIcon(Symbols.chevron_right_rounded));
    expect(arrow.left - end.dx, closeTo(4 * 1.3, .1));
    expect(arrow.center.dy, closeTo(end.dy, 4));
    final timestamp = tester.getRect(processText('00:01:000'));
    expect(arrow.right, lessThan(timestamp.left));
    await tester.tap(find.byIcon(Symbols.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(processText(executable), findsOneWidget);
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.toolbar);
    await tester.pump();
    expect(selected, contains(executable));
    expect(selected, isNot(contains('\uFFFC')));
    expect(tester.takeException(), isNull);
  });

  for (final type in ThemeType.values) {
    testWidgets('disclosure arrow and hover match elapsed header ($type)', (
      tester,
    ) async {
      const thought = AiProcessEvent(
        type: AiProcessEventType.reasoning,
        elapsed: Duration.zero,
        text: 'A real reasoning excerpt.',
      );
      await tester.pumpWidget(host(thought, type: type, width: 440));
      await tester.pumpAndSettle();
      final theme = MaterialPalette.create(type);
      Color? titleColor() =>
          tester.widget<Text>(processText('Model reasoning')).style?.color;
      Color? arrowColor() =>
          tester.widget<Icon>(find.byIcon(Symbols.chevron_right_rounded)).color;
      expect(titleColor(), theme.textColorTertiary);
      expect(arrowColor(), theme.textColorTertiary);
      var rotation = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation),
      );
      expect(rotation.turns, 0);
      expect(rotation.duration, const Duration(milliseconds: 150));
      final titleParagraph = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: processText('Model reasoning'),
              matching: find.byType(RichText),
            )
            .first,
      );
      final lastBox = titleParagraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 15),
          )
          .last;
      expect(
        tester.getTopLeft(find.byIcon(Symbols.chevron_right_rounded)).dx -
            titleParagraph.localToGlobal(Offset(lastBox.right, 0)).dx,
        closeTo(4 * 1.3, .1),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(760, 550));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(processText('Model reasoning')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(titleColor(), isNot(theme.textColorTertiary));
      await tester.pumpAndSettle();
      expect(titleColor(), theme.textColorPrimary);
      expect(arrowColor(), theme.textColorPrimary);
      await tester.tap(processText('Model reasoning'));
      await tester.pumpAndSettle();
      rotation = tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
      expect(rotation.turns, .25);
      expect(processText('A real reasoning excerpt.'), findsOneWidget);
      await mouse.moveTo(const Offset(760, 550));
      await tester.pumpAndSettle();
      expect(titleColor(), theme.textColorTertiary);
      expect(arrowColor(), theme.textColorTertiary);
      expect(tester.takeException(), isNull);
    });
  }
}
