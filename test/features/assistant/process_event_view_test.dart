import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/definition.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
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
  double width = 320,
  ValueChanged<SelectedContent?>? onSelectionChanged,
  List<AiProcessEvent> stages = const [],
}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: MediaQuery(
      data: const MediaQueryData(
        size: Size(340, 700),
        textScaler: TextScaler.linear(1.3),
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
          output: 'legacy',
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
      'legacy',
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
              output: state == 'legacy'
                  ? 'Legacy result'
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
            _ => l10n.aiCommandRan('flasher.exe'),
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
        output: 'Started',
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
    final title = processText('Ran command · firmware_download_run.exe');
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
