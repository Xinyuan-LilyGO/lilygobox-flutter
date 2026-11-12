import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:lilygobox/core/theme/definition.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/process_event_view.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

Widget host(
  AiProcessEvent event, {
  ThemeType type = ThemeType.light,
  String locale = 'en',
  bool thinking = false,
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
        child: SizedBox(
          width: 320,
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
          expect(find.text('Initial thought'), findsNothing);
          await tester.tap(find.byType(InkWell));
          await tester.pumpAndSettle();
          expect(find.text('Initial thought'), findsOneWidget);
          const next = AiProcessEvent(
            type: AiProcessEventType.reasoning,
            elapsed: Duration.zero,
            text: 'Initial thought plus more',
          );
          await tester.pumpWidget(host(next, type: type, locale: locale));
          await tester.pumpAndSettle();
          expect(find.text('Initial thought plus more'), findsOneWidget);
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
          expect(find.text('Initial thought plus more'), findsNothing);
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
      expect(find.text('Writing file · a.txt'), findsOneWidget);
      expect(find.textContaining('New file text'), findsNothing);
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.textContaining('New file text'), findsNothing);
      expect(find.text('Writing file'), findsOneWidget);
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
      expect(find.text('Wrote file · a.txt'), findsOneWidget);
      expect(find.text('Writing file · a.txt'), findsNothing);
      expect(find.text('Write completed'), findsNothing);
      expect(
        find.text('Wrote the content to the target file.'),
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
      expect(find.text('Listing directory · folder'), findsOneWidget);
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
      expect(find.text('Access denied details'), findsNothing);
      expect(find.text('Failed: Read file: a.txt'), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.text('Access denied details'), findsOneWidget);
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
    expect(find.text('A short note.'), findsNothing);
    expect(find.byType(InkWell), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(find.text('Read the file content.'), findsOneWidget);
    expect(find.text('A short note.'), findsNothing);
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
    expect(find.text('Accessed webpage docs.example.com'), findsOneWidget);
    expect(find.text('Preparing tool calls'), findsNothing);
    expect(find.text(url), findsNothing);
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(find.text('Preparing tool calls'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.text('Accessing webpage'), findsOneWidget);
    expect(find.text(url), findsOneWidget);
    expect(find.text('Read the webpage content.'), findsOneWidget);
    expect(find.textContaining('RAW_HTTP_MARKER'), findsNothing);
    expect(find.textContaining('"url"'), findsNothing);
    expect(
      tester.widget<Icon>(find.byIcon(Symbols.safety_check_rounded)).fill,
      1,
    );
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
      await tester.pumpWidget(host(thought, type: type));
      await tester.pumpAndSettle();
      final theme = MaterialPalette.create(type);
      Color? titleColor() =>
          tester.widget<Text>(find.text('Model reasoning')).style?.color;
      Color? arrowColor() =>
          tester.widget<Icon>(find.byIcon(Symbols.chevron_right_rounded)).color;
      expect(titleColor(), theme.textColorTertiary);
      expect(arrowColor(), theme.textColorTertiary);
      var rotation = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation),
      );
      expect(rotation.turns, 0);
      expect(rotation.duration, const Duration(milliseconds: 150));
      expect(
        tester.getTopLeft(find.byIcon(Symbols.chevron_right_rounded)).dx -
            tester.getTopRight(find.text('Model reasoning')).dx,
        closeTo(4, .1),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(760, 550));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Model reasoning')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(titleColor(), isNot(theme.textColorTertiary));
      await tester.pumpAndSettle();
      expect(titleColor(), theme.textColorPrimary);
      expect(arrowColor(), theme.textColorPrimary);
      await tester.tap(find.text('Model reasoning'));
      await tester.pumpAndSettle();
      rotation = tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
      expect(rotation.turns, .25);
      expect(find.text('A real reasoning excerpt.'), findsOneWidget);
      await mouse.moveTo(const Offset(760, 550));
      await tester.pumpAndSettle();
      expect(titleColor(), theme.textColorTertiary);
      expect(arrowColor(), theme.textColorTertiary);
      expect(tester.takeException(), isNull);
    });
  }
}
