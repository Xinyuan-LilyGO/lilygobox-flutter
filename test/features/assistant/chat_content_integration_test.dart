import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/data/agent_package.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_content_window.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_scrollbar.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_selection.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_window.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/code_block.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/conversation_scroll_controller.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/message_content.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

const _viewportKey = ValueKey('content-integration-scroll');

String _paragraph(int index) =>
    'PARA-${index.toString().padLeft(4, '0')} '
    '${'A **formatted** paragraph preserves its text and reading position. ' * 4}';

String _longMarkdown() => List.generate(1000, _paragraph).join('\n\n');

class _ChatContentHarness {
  _ChatContentHarness(this.messages);

  final List<AiMessage> messages;
  final theme = ThemeProvider();
  final controller = ConversationScrollController();
  final focus = FocusNode();
  final history = GlobalKey<ChatHistoryWindowState>();
  final selection = GlobalKey<ChatHistorySelectionState>();
  final bucket = PageStorageBucket();
  bool followsLatest = false;
  bool scrollbar = false;

  Widget build() => ChangeNotifierProvider.value(
    value: theme,
    child: MaterialApp(
      theme: scrollbar
          ? ThemeData(
              platform: TargetPlatform.windows,
              scrollbarTheme: const ScrollbarThemeData(
                thumbVisibility: WidgetStatePropertyAll(true),
              ),
            )
          : null,
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      scrollBehavior: const AppScrollBehavior(scrollbars: false)
          .copyWith(platform: scrollbar ? TargetPlatform.windows : null),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 480,
            height: 320,
            child: PageStorage(
              bucket: bucket,
              child: ChatHistorySelection(
                key: selection,
                focusNode: focus,
                messages: messages,
                hasUnloadedMessages: () =>
                    (history.currentState?.hasEarlier ?? false) ||
                    (history.currentState?.hasLater ?? false) ||
                    (history.currentState?.hasUnloadedContent ?? false),
                onSelectionChanged: () =>
                    history.currentState?.selectionChanged(),
                child: ChatHistoryWindow(
                  key: history,
                  historyId: messages.first.id,
                  messages: messages,
                  controller: controller,
                  scrollbar: scrollbar,
                  followsLatest: () => followsLatest,
                  hasSelection: () =>
                      selection.currentState?.hasSelection ?? false,
                  onRangeChanged: (_) {},
                  itemBuilder: (message) => Padding(
                    key: PageStorageKey(message.id),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ChatMessageBody(
                      message: message,
                      theme: theme.themeData,
                      useParentSelectionArea: true,
                    ),
                  ),
                  viewportBuilder: (context, child) {
                    final viewport = SingleChildScrollView(
                      key: _viewportKey,
                      controller: controller,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: child,
                    );
                    return viewport;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void dispose() {
    controller.dispose();
    focus.dispose();
    theme.dispose();
  }
}

Future<_ChatContentHarness> _showMessage(
  WidgetTester tester,
  AiMessage message,
) => _showMessages(tester, [message]);

Future<_ChatContentHarness> _showMessages(
  WidgetTester tester,
  List<AiMessage> messages,
) async {
  final harness = _ChatContentHarness(messages);
  addTearDown(() async {
    ContextMenuController.removeAny();
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });
  await tester.pumpWidget(harness.build());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return harness;
}

class _ClipboardCapture {
  String? text;
}

_ClipboardCapture _captureClipboard(WidgetTester tester) {
  final capture = _ClipboardCapture();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        capture.text = (call.arguments as Map)['text'] as String;
      }
      if (call.method == 'Clipboard.hasStrings') return {'value': true};
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return capture;
}

Finder _bodyRichText() => find.descendant(
  of: find.byType(ChatMessageBody),
  matching: find.byType(RichText),
);

Finder _visibleRichText(WidgetTester tester, {String? containing}) {
  final viewport = tester.getRect(find.byKey(_viewportKey));
  for (final element in _bodyRichText().evaluate()) {
    final widget = element.widget as RichText;
    final text = widget.text.toPlainText();
    if (text.trim().isEmpty ||
        (containing != null && !text.contains(containing))) {
      continue;
    }
    final finder = find.byWidget(widget);
    final rect = tester.getRect(finder);
    if (rect.bottom > viewport.top + 20 &&
        rect.top < viewport.bottom - 20 &&
        rect.right > viewport.left &&
        rect.left < viewport.right) {
      return find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == text,
      );
    }
  }
  throw StateError('The chat viewport has no visible text');
}

Offset _visibleTextPoint(WidgetTester tester) {
  final viewport = tester.getRect(find.byKey(_viewportKey));
  final paragraph = tester.getRect(_visibleRichText(tester));
  return Offset(
    math.max(paragraph.left, viewport.left) + 10,
    math.max(paragraph.top, viewport.top) + 10,
  );
}

Future<void> _keyboardCopyAll(
  WidgetTester tester,
  _ChatContentHarness harness,
) async {
  harness.focus.requestFocus();
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _rightClickVisibleText(WidgetTester tester) async {
  await tester.tapAt(
    _visibleTextPoint(tester),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilMounted(
  WidgetTester tester,
  _ChatContentHarness harness,
  Finder target,
) async {
  for (var attempt = 0; attempt < 160 && target.evaluate().isEmpty; attempt++) {
    harness.controller.jumpTo(
      math.min(160, harness.controller.position.maxScrollExtent),
    );
    await tester.pumpAndSettle();
  }
  expect(target, findsOneWidget);
}

Finder _codeContaining(String text) => find.byWidgetPredicate(
  (widget) => widget is ChatCodeBlock && widget.text.contains(text),
);

bool _wordWrapped(WidgetTester tester, Finder code) => tester
    .widgetList<Semantics>(
      find.descendant(of: code, matching: find.byType(Semantics)),
    )
    .singleWhere((widget) => widget.properties.toggled != null)
    .properties
    .toggled!;

bool _hasFontLargerThan(InlineSpan span, double size) {
  var found = (span.style?.fontSize ?? 0) > size;
  span.visitChildren((child) {
    found |= (child.style?.fontSize ?? 0) > size;
    return true;
  });
  return found;
}

bool _hasBoldText(InlineSpan span) {
  final weight = span.style?.fontWeight?.value ?? FontWeight.normal.value;
  var found = weight >= FontWeight.w600.value;
  if (span is TextSpan) {
    for (final child in span.children ?? const <InlineSpan>[]) {
      found |= _hasBoldText(child);
    }
  }
  return found;
}

bool _hasLinkRecognizer(InlineSpan span) {
  var found = span is TextSpan && span.recognizer != null;
  if (span is TextSpan) {
    for (final child in span.children ?? const <InlineSpan>[]) {
      found |= _hasLinkRecognizer(child);
    }
  }
  return found;
}

ChatContentWindowState _messageWindow(WidgetTester tester, String messageId) =>
    tester.state<ChatContentWindowState>(
      find.descendant(
        of: find.byKey(PageStorageKey(messageId)),
        matching: find.byType(ChatContentWindow),
      ),
    );

Future<void> _scrollMessageToBeginning(
  WidgetTester tester,
  _ChatContentHarness harness,
  String messageId,
) async {
  final message = find.byKey(PageStorageKey(messageId));
  for (
    var attempt = 0;
    attempt < 160 && _messageWindow(tester, messageId).hasEarlier;
    attempt++
  ) {
    final viewport = tester.getRect(find.byKey(_viewportKey));
    final messageTop = tester.getTopLeft(message).dy;
    final target = harness.controller.offset + messageTop - viewport.top + 160;
    harness.controller.jumpTo(
      target.clamp(0, harness.controller.position.maxScrollExtent),
    );
    await tester.pumpAndSettle();
  }
  expect(_messageWindow(tester, messageId).hasEarlier, isFalse);
}

void main() {
  testWidgets(
    'dragged thumb retains its position after loading more body sections',
    (tester) async {
      final harness = _ChatContentHarness([
        AiMessage(
          id: 'thumb-body',
          role: 'assistant',
          content: _longMarkdown(),
        ),
      ])..scrollbar = true;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.dispose();
      });
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byKey(_viewportKey));
      final logical = tester
          .widget<Scrollbar>(find.byType(Scrollbar))
          .controller!;
      final from = Offset(viewport.right - 4, viewport.bottom - 22);
      final thumb = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      final initialOffset = logical.offset;
      final firstSection = _messageWindow(tester, 'thumb-body').firstChildIndex;
      await thumb.moveBy(const Offset(0, -190));
      await tester.pumpAndSettle();
      expect(logical.offset, lessThan(initialOffset));
      await thumb.moveBy(const Offset(0, -20));
      await tester.pumpAndSettle();
      final fraction = logical.offset / logical.position.maxScrollExtent;
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.foregroundPainter)
          .whereType<ScrollbarPainter>()
          .single;
      final thumbOffset = painter.getThumbScrollOffset();
      final anchor = _visibleRichText(tester);
      final anchorTop = tester.getTopLeft(anchor).dy;
      await thumb.up();
      await tester.pumpAndSettle();
      expect(
        _messageWindow(tester, 'thumb-body').firstChildIndex,
        lessThan(firstSection),
      );
      expect(tester.getTopLeft(anchor).dy, closeTo(anchorTop, .01));
      expect(painter.getThumbScrollOffset(), closeTo(thumbOffset, .01));
      expect(
        logical.offset / logical.position.maxScrollExtent,
        closeTo(fraction, .01),
      );
      final second = await tester.startGesture(
        Offset(
          viewport.right - 4,
          viewport.top + 18 + fraction * (viewport.height - 36),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await second.moveBy(const Offset(0, 50));
      await tester.pumpAndSettle();
      final secondFraction = logical.offset / logical.position.maxScrollExtent;
      final secondThumbOffset = painter.getThumbScrollOffset();
      expect(secondFraction, greaterThan(fraction));
      await second.up();
      await tester.pumpAndSettle();
      expect(
        logical.offset / logical.position.maxScrollExtent,
        closeTo(secondFraction, .01),
      );
      expect(painter.getThumbScrollOffset(), closeTo(secondThumbOffset, .01));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'history thumb seeks across ten thousand messages without rebounding',
    (tester) async {
      final harness = _ChatContentHarness(
        List.generate(
          10000,
          (index) => AiMessage(
            id: 'seek-$index',
            role: 'user',
            content: 'MESSAGE-$index ${'A short line. ' * 8}',
          ),
        ),
      )..scrollbar = true;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.dispose();
      });
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byKey(_viewportKey));
      final logical = tester
          .widget<Scrollbar>(find.byType(Scrollbar))
          .controller!;
      final gesture = await tester.startGesture(
        Offset(viewport.right - 4, viewport.bottom - 18),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(Offset(0, -(viewport.height - 36) * .6));
      await tester.pumpAndSettle();
      final fraction = logical.offset / logical.position.maxScrollExtent;
      expect(fraction, closeTo(.4, .03));
      final visible = tester
          .widget<RichText>(_visibleRichText(tester))
          .text
          .toPlainText();
      final messageIndex = int.parse(
        RegExp(r'MESSAGE-(\d+)').firstMatch(visible)!.group(1)!,
      );
      expect(messageIndex, inInclusiveRange(3600, 4400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        logical.offset / logical.position.maxScrollExtent,
        closeTo(fraction, .001),
      );
      expect(
        harness.history.currentState!.loadedMessageCount,
        lessThanOrEqualTo(ChatHistoryWindowState.maximumMessages),
      );
      harness.history.currentState!.showLatest();
      await tester.pumpAndSettle();
      harness.controller.jumpTo(harness.controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(logical.offset / logical.position.maxScrollExtent, 1);
      expect(
        find.textContaining('MESSAGE-9999', findRichText: true),
        findsOneWidget,
      );
      final topGesture = await tester.startGesture(
        Offset(viewport.right - 4, viewport.bottom - 18),
        kind: PointerDeviceKind.mouse,
      );
      await topGesture.moveBy(Offset(0, -viewport.height));
      await tester.pumpAndSettle();
      await topGesture.up();
      await tester.pumpAndSettle();
      expect(logical.offset, 0);
      expect(
        find.textContaining('MESSAGE-0 ', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history thumb reaches the track top on the first page', (
    tester,
  ) async {
    final harness = _ChatContentHarness(
      List.generate(
        10000,
        (index) => AiMessage(
          id: 'top-$index',
          role: 'assistant',
          content: 'TOP-$index ${'A short line. ' * 8}',
        ),
      ),
    )..scrollbar = true;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    tester
        .widget<ChatHistoryScrollbar>(find.byType(ChatHistoryScrollbar))
        .seek(0, true);
    await tester.pumpAndSettle();
    final logical = tester
        .widget<Scrollbar>(find.byType(Scrollbar))
        .controller!;
    expect(harness.history.currentState!.hasEarlier, isFalse);
    expect(logical.offset, closeTo(0, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('history thumb reaches the top with long message bodies', (
    tester,
  ) async {
    final body = List.generate(120, _paragraph).join('\n\n');
    final harness = _ChatContentHarness(
      List.generate(
        12,
        (index) =>
            AiMessage(id: 'long-top-$index', role: 'assistant', content: body),
      ),
    )..scrollbar = true;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byKey(_viewportKey));
    final logical = tester
        .widget<Scrollbar>(find.byType(Scrollbar))
        .controller!;
    final gesture = await tester.startGesture(
      Offset(viewport.right - 4, viewport.bottom - 18),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(Offset(0, -viewport.height * 2));
    await tester.pumpAndSettle();
    expect(logical.offset, closeTo(0, .01));
    expect(
      find.textContaining('PARA-0000', findRichText: true),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(logical.offset, closeTo(0, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short and paged histories follow the same continuous wheel trajectory',
    (tester) async {
      final messages = List.generate(
        10000,
        (index) => AiMessage(
          id: 'trace-$index',
          role: 'assistant',
          content: _paragraph(index),
        ),
      );
      Future<(String, List<double>)> trace(List<AiMessage> history) async {
        final harness = _ChatContentHarness(history)..scrollbar = true;
        try {
          await tester.pumpWidget(harness.build());
          await tester.pumpAndSettle();
          final viewport = tester.getRect(find.byKey(_viewportKey));
          harness.controller.jumpTo(
            viewport.height * ChatHistoryWindowState.preloadScreens + 40,
          );
          await tester.pumpAndSettle();
          final anchor = _visibleRichText(tester, containing: 'PARA-');
          final text = tester.widget<RichText>(anchor).text.toPlainText();
          final initialY = tester.getTopLeft(anchor).dy;
          final state = harness.history.currentState!;
          final initialCount = state.loadedMessageCount;
          final bar = tester
              .widget<Scrollbar>(find.byType(Scrollbar))
              .controller!;
          var lastThumb = bar.offset / bar.position.maxScrollExtent;
          final positions = <double>[];
          for (var frame = 0; frame < 40; frame++) {
            if (frame == 0 || frame == 5 || frame == 10) {
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  kind: PointerDeviceKind.mouse,
                  position: viewport.center,
                  timeStamp: Duration(milliseconds: frame * 8 + 1),
                  scrollDelta: const Offset(0, -160),
                ),
              );
              if (frame == 0) await tester.pump();
            }
            await tester.pump(const Duration(milliseconds: 8));
            positions.add(tester.getTopLeft(anchor).dy - initialY);
            final thumb = bar.offset / bar.position.maxScrollExtent;
            expect(
              thumb,
              lessThanOrEqualTo(lastThumb + 1e-8),
              reason: 'thumb frame $frame',
            );
            lastThumb = thumb;
            if (frame == 32 && history.length > initialCount) {
              expect(state.loadedMessageCount, greaterThan(initialCount));
            }
          }
          return (text, positions);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          harness.dispose();
        }
      }

      final (shortText, short) = await trace(
        messages.sublist(
          messages.length - ChatHistoryWindowState.initialMessages,
        ),
      );
      final (longText, long) = await trace(messages);
      expect(shortText, longText);
      expect(short.last, closeTo(992, .01));
      for (var frame = 0; frame < short.length; frame++) {
        expect(
          long[frame],
          closeTo(short[frame], .01),
          reason: 'visible text frame $frame',
        );
      }
    },
  );
  testWidgets('a short conversation has no artificial scroll range', (
    tester,
  ) async {
    final harness = await _showMessage(
      tester,
      AiMessage(
        id: 'short-scroll',
        role: 'user',
        content: 'Short conversation',
      ),
    );
    harness.scrollbar = true;
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    final logical = tester
        .widget<Scrollbar>(find.byType(Scrollbar))
        .controller!;
    expect(logical.position.maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a fully mounted conversation keeps pixel scrollbar mapping', (
    tester,
  ) async {
    final harness = await _showMessages(
      tester,
      List.generate(
        12,
        (index) => AiMessage(
          id: 'full-$index',
          role: 'user',
          content: 'Fully mounted $index ${'A line of text. ' * 8}',
        ),
      ),
    );
    harness.scrollbar = true;
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    final physical = harness.controller;
    final logical = tester
        .widget<Scrollbar>(find.byType(Scrollbar))
        .controller!;
    physical.jumpTo(physical.position.maxScrollExtent * .3);
    await tester.pumpAndSettle();
    expect(logical.offset, closeTo(physical.offset, .001));
    expect(logical.position.maxScrollExtent, physical.position.maxScrollExtent);
  });
  testWidgets(
    'short Markdown reply scrolls its thumb by actual pixels after preload',
    (tester) async {
      final harness = _ChatContentHarness([
        AiMessage(id: 'question', role: 'user', content: 'Report the result.'),
        AiMessage(
          id: 'answer',
          role: 'assistant',
          content: [
            for (var index = 0; index < 6; index++)
              'Step $index: ${'A short result. ' * 3}',
            '| Test | Result |\n| --- | --- |\n| A | OK |',
            '```text\nOLD-014\n```',
          ].join('\n\n'),
        ),
      ])..scrollbar = true;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.dispose();
      });
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      expect(harness.history.currentState!.hasUnloadedContent, isFalse);
      final bar = tester
          .widget<Scrollbar>(find.byType(Scrollbar).first)
          .controller!;
      final extent = harness.controller.position.maxScrollExtent;
      expect(extent, greaterThan(0));
      expect(bar.position.maxScrollExtent, closeTo(extent, .01));
      final viewport = tester.getRect(find.byKey(_viewportKey));
      harness.controller.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: viewport.center,
          scrollDelta: Offset(0, math.min(80, extent)),
        ),
      );
      await tester.pump();
      final offsets = <double>{};
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        offsets.add(bar.offset);
        expect(bar.offset, closeTo(harness.controller.offset, .01));
      }
      expect(offsets.length, greaterThan(5));
    },
  );
  testWidgets(
    'changing history during a thumb drag releases the navigation position',
    (tester) async {
      final harness = await _showMessage(
        tester,
        AiMessage(
          id: 'old-history',
          role: 'assistant',
          content: _longMarkdown(),
        ),
      );
      harness.scrollbar = true;
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byKey(_viewportKey));
      final gesture = await tester.startGesture(
        Offset(viewport.right - 4, viewport.bottom - 18),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -100));
      await tester.pumpAndSettle();
      harness.messages
        ..clear()
        ..add(
          AiMessage(id: 'new-history', role: 'user', content: 'New history'),
        );
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(find.text('New history', findRichText: true), findsOneWidget);
      expect(
        tester
            .widget<Scrollbar>(find.byType(Scrollbar))
            .controller!
            .position
            .maxScrollExtent,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );
  const packagePath = String.fromEnvironment('LONG_CHAT_PACKAGE');
  testWidgets(
    'short Markdown in a long history renders formatting without creating nested scroll windows',
    (tester) async {
      final harness = await _showMessages(
        tester,
        List.generate(
          10000,
          (index) => AiMessage(
            id: 'review-$index',
            role: 'assistant',
            content:
                'Entry $index\n\n- One\n- Two\n\n**Note:** short response.',
          ),
        ),
      );
      expect(harness.history.currentState!.hasEarlier, isTrue);
      expect(
        find.textContaining('short response.', findRichText: true),
        findsWidgets,
      );
      expect(find.byType(ChatContentWindow), findsNothing);
    },
  );
  testWidgets('a compact list with many items still loads in blocks', (
    tester,
  ) async {
    final content = List.generate(120, (index) => '- Item $index').join('\n');
    expect(content.length, lessThan(2048));
    await _showMessage(
      tester,
      AiMessage(id: 'compact-list', role: 'assistant', content: content),
    );
    final window = tester.state<ChatContentWindowState>(
      find.byType(ChatContentWindow),
    );
    expect(window.hasEarlier, isTrue);
    expect(find.text('Item 119', findRichText: true), findsOneWidget);
    expect(find.text('Item 0', findRichText: true), findsNothing);
  });
  if (packagePath.isNotEmpty) {
    testWidgets(
      'the delivered 10k-message package preserves wheel travel and thumb location',
      (tester) async {
        final package = (await tester.runAsync(
          () => AgentPackage.read(packagePath),
        ))!;
        final record = (package['workflow']['sessions'] as List).single;
        final messages = (record['conversation']['messages'] as List)
            .cast<Map>()
            .map(ConversationCodec.read)
            .toList();
        expect(messages, hasLength(10000));
        final harness = await _showMessages(tester, messages);
        harness.scrollbar = true;
        await tester.pumpWidget(harness.build());
        await tester.pumpAndSettle();
        final history = harness.history.currentState!;
        expect(
          history.loadedMessageCount,
          lessThanOrEqualTo(ChatHistoryWindowState.maximumMessages),
        );
        final end = find.textContaining('END-10000', findRichText: true);
        expect(end, findsOneWidget);
        final before = tester.getTopLeft(end).dy;
        final viewport = tester.getRect(find.byKey(_viewportKey));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: viewport.center,
            scrollDelta: const Offset(0, -100),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(end).dy - before, closeTo(100, .01));
        harness.controller.jumpTo(harness.controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final bar = find.byType(Scrollbar).first;
        final logical = tester.widget<Scrollbar>(bar).controller!;
        final gesture = await tester.startGesture(
          Offset(viewport.right - 4, viewport.bottom - 18),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(Offset(0, -viewport.height * .45));
        await tester.pumpAndSettle();
        final fraction = logical.offset / logical.position.maxScrollExtent;
        expect(fraction, inExclusiveRange(.3, .7));
        final anchor = _visibleRichText(tester, containing: 'MSG-');
        final anchorTop = tester.getTopLeft(anchor).dy;
        expect(
          tester.widget<RichText>(anchor).text.toPlainText(),
          contains('MSG-'),
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          logical.offset / logical.position.maxScrollExtent,
          closeTo(fraction, .001),
        );
        expect(tester.getTopLeft(anchor).dy, closeTo(anchorTop, .01));

        tester
            .widget<ChatHistoryScrollbar>(find.byType(ChatHistoryScrollbar))
            .seek(.63, true);
        await tester.pumpAndSettle();
        final middle = _visibleRichText(tester, containing: 'MSG-');
        final middleTop = tester.getTopLeft(middle).dy;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: viewport.center,
            scrollDelta: const Offset(0, -100),
          ),
        );
        await tester.pump();
        var previous = 0.0;
        for (var frame = 1; frame <= 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final distance = tester.getTopLeft(middle).dy - middleTop;
          expect(distance, greaterThan(previous), reason: 'frame $frame');
          previous = distance;
        }
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(middle).dy - middleTop, closeTo(100, .01));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'a thousand Markdown paragraphs mount a tail and preload by anchor',
    (tester) async {
      final harness = await _showMessage(
        tester,
        AiMessage(
          id: 'markdown-tail',
          role: 'assistant',
          content: _longMarkdown(),
        ),
      );
      harness.scrollbar = true;
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      final content = tester.state<ChatContentWindowState>(
        find.byType(ChatContentWindow),
      );
      final initialFirst = content.firstChildIndex;

      expect(harness.history.currentState!.loadedMessageCount, 1);
      expect(harness.history.currentState!.hasEarlier, isTrue);
      expect(harness.history.currentState!.hasLater, isFalse);
      expect(content.loadedChildCount, lessThan(100));
      expect(_bodyRichText().evaluate().length, lessThan(100));
      expect(
        find.textContaining('PARA-0999', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('PARA-0000', findRichText: true),
        findsNothing,
      );
      expect(harness.controller.position.extentAfter, closeTo(0, .01));

      harness.controller.jumpTo(160);
      await tester.pump();
      final anchor = _visibleRichText(tester);
      final before = tester.getTopLeft(anchor).dy;
      await tester.pumpAndSettle();

      expect(content.firstChildIndex, lessThan(initialFirst));
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
      expect(_bodyRichText().evaluate().length, lessThan(150));

      harness.controller.jumpTo(
        harness.controller.position.viewportDimension *
                ChatContentWindowState.preloadScreens +
            60,
      );
      await tester.pumpAndSettle();
      final firstBeforeWheel = content.firstChildIndex;
      final wheelAnchor = _visibleRichText(tester, containing: 'PARA-');
      final initialTop = tester.getTopLeft(wheelAnchor).dy;
      final bar = tester.widget<Scrollbar>(find.byType(Scrollbar)).controller!;
      var previousFraction = bar.offset / bar.position.maxScrollExtent;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byKey(_viewportKey)),
          scrollDelta: const Offset(0, -100),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      for (var frame = 1; frame <= 25; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        final remaining = 1 - frame / 25;
        final expected = 100 * (1 - remaining * remaining * remaining);
        expect(
          tester.getTopLeft(wheelAnchor).dy - initialTop,
          closeTo(expected, .01),
          reason: 'Markdown block preload, frame $frame',
        );
        final fraction = bar.offset / bar.position.maxScrollExtent;
        expect(
          fraction,
          lessThanOrEqualTo(previousFraction + 1e-8),
          reason: 'Markdown thumb frame $frame',
        );
        previousFraction = fraction;
      }
      expect(content.firstChildIndex, lessThan(firstBeforeWheel));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('one partially mounted Markdown message copies its full source', (
    tester,
  ) async {
    final clipboard = _captureClipboard(tester);
    final markdown = _longMarkdown();
    final harness = await _showMessage(
      tester,
      AiMessage(id: 'markdown-copy', role: 'assistant', content: markdown),
    );

    expect(harness.history.currentState!.loadedMessageCount, 1);
    expect(harness.history.currentState!.hasEarlier, isTrue);
    expect(find.textContaining('PARA-0000', findRichText: true), findsNothing);
    await _keyboardCopyAll(tester, harness);

    expect(clipboard.text, markdown);
    expect(harness.selection.currentState!.hasSelection, isTrue);
    expect(find.textContaining('PARA-0000', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'closing a chat during wheel motion releases its scroll activity',
    (tester) async {
      final harness = await _showMessage(
        tester,
        AiMessage(
          id: 'close-scrolling',
          role: 'assistant',
          content: _longMarkdown(),
        ),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(find.byKey(_viewportKey)),
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(harness.controller.position.isScrollingNotifier.value, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('right-click select all copies unmounted Markdown paragraphs', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final clipboard = _captureClipboard(tester);
    final markdown = _longMarkdown();
    final harness = await _showMessage(
      tester,
      AiMessage(id: 'markdown-menu', role: 'assistant', content: markdown),
    );

    await _rightClickVisibleText(tester);
    expect(find.text('Select all'), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(harness.selection.currentState!.hasSelection, isTrue);
    await _rightClickVisibleText(tester);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(clipboard.text, markdown);
    expect(harness.history.currentState!.hasEarlier, isTrue);
    expect(find.textContaining('PARA-0000', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'a long CRLF user message mounts segments and copies every line',
    (tester) async {
      final clipboard = _captureClipboard(tester);
      final text = List.generate(
        2000,
        (index) =>
            'USER-${index.toString().padLeft(4, '0')}: '
            '中文 e\u0301 👩🏽‍💻 ${'complete original text ' * 4}',
      ).join('\r\n');
      final harness = await _showMessage(
        tester,
        AiMessage(id: 'user-segments', role: 'user', content: text),
      );
      final content = tester.state<ChatContentWindowState>(
        find.byType(ChatContentWindow),
      );

      expect(content.loadedChildCount, lessThan(content.widget.childCount));
      expect(harness.history.currentState!.hasEarlier, isTrue);
      expect(
        find.textContaining('USER-0000:', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('USER-1999:', findRichText: true),
        findsWidgets,
      );
      expect(find.text(text), findsNothing);
      await _keyboardCopyAll(tester, harness);

      expect(clipboard.text, text);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a single long user line mounts in chunks and copies the complete source',
    (tester) async {
      final clipboard = _captureClipboard(tester);
      final text = '${'USER-WORD ${'unicode 中文 👩🏽‍💻 ' * 20}' * 600}END';
      final harness = await _showMessage(
        tester,
        AiMessage(id: 'user-single-line', role: 'user', content: text),
      );
      final content = tester.state<ChatContentWindowState>(
        find.byType(ChatContentWindow),
      );

      expect(content.widget.childCount, greaterThan(20));
      expect(content.loadedChildCount, lessThan(content.widget.childCount));
      expect(
        find.textContaining('USER-WORD', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('USER-WORD', findRichText: true).evaluate().length,
        lessThan(content.widget.childCount),
      );
      await _keyboardCopyAll(tester, harness);

      expect(clipboard.text, text);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a single long Markdown paragraph mounts inline-preserving chunks',
    (tester) async {
      final clipboard = _captureClipboard(tester);
      final markdown =
          '${'Assistant sentence with **bold wording** and [linked words](https://example.test). ' * 1800}'
          '**TAIL-BOLD**';
      final harness = await _showMessage(
        tester,
        AiMessage(
          id: 'markdown-single-paragraph',
          role: 'assistant',
          content: markdown,
        ),
      );
      final content = tester.state<ChatContentWindowState>(
        find.byType(ChatContentWindow),
      );

      expect(content.widget.childCount, greaterThan(20));
      expect(content.loadedChildCount, lessThan(content.widget.childCount));
      expect(
        find.textContaining('Assistant sentence', findRichText: true),
        findsWidgets,
      );
      final styledParagraph = tester
          .widgetList<RichText>(_bodyRichText())
          .firstWhere(
            (paragraph) =>
                paragraph.text.toPlainText().contains('bold wording'),
          );
      expect(_hasBoldText(styledParagraph.text), isTrue);
      expect(_hasLinkRecognizer(styledParagraph.text), isTrue);
      await _keyboardCopyAll(tester, harness);

      expect(clipboard.text, markdown);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'mixed Markdown blocks retain styling and code wrap after unloading',
    (tester) async {
      final markdown = List.generate(20, (index) {
        final label = index.toString().padLeft(2, '0');
        return '## HEADING-$label\n\n'
            '| Key | Value |\n| --- | --- |\n| CELL-$label | Value-$label |\n\n'
            '- ITEM-$label\n- Second item-$label\n\n'
            '> QUOTE-$label with **emphasis**.\n\n'
            '```dart\nprint("CODE-$label ${'argument ' * 40}");\n```\n\n'
            '${_paragraph(index)}\n\n';
      }).join();
      final harness = await _showMessage(
        tester,
        AiMessage(id: 'mixed-blocks', role: 'assistant', content: markdown),
      );
      final lastCode = _codeContaining('CODE-19');
      final wrap = find.descendant(
        of: lastCode,
        matching: find.byKey(const ValueKey('ai-code-wrap')),
      );
      expect(lastCode, findsOneWidget);
      final originalKey = tester.widget<ChatCodeBlock>(lastCode).key;
      expect(
        originalKey,
        const PageStorageKey('ai-message-code-mixed-blocks-19'),
      );
      expect(_wordWrapped(tester, lastCode), isFalse);
      await tester.ensureVisible(wrap);
      await tester.tap(wrap);
      await tester.pumpAndSettle();
      expect(_wordWrapped(tester, lastCode), isTrue);

      final firstHeading = find.text('HEADING-00');
      await _scrollUntilMounted(tester, harness, firstHeading);
      await tester.ensureVisible(firstHeading);
      await tester.pumpAndSettle();

      expect(lastCode, findsNothing);
      expect(harness.history.currentState!.hasLater, isTrue);
      expect(find.byType(Table), findsWidgets);
      expect(find.text('CELL-00'), findsOneWidget);
      expect(find.text('ITEM-00'), findsOneWidget);
      expect(
        find.textContaining('QUOTE-00', findRichText: true),
        findsOneWidget,
      );
      final heading = tester.widget<RichText>(
        find.descendant(of: firstHeading, matching: find.byType(RichText)),
      );
      expect(_hasFontLargerThan(heading.text, 14), isTrue);

      harness.history.currentState!.showLatest();
      await tester.pumpAndSettle();
      expect(lastCode, findsOneWidget);
      expect(tester.widget<ChatCodeBlock>(lastCode).key, originalKey);
      expect(_wordWrapped(tester, lastCode), isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'one large code block mounts line segments and copies complete code',
    (tester) async {
      final clipboard = _captureClipboard(tester);
      final code =
          '${List.generate(2000, (index) => 'CODE-LINE-${index.toString().padLeft(4, '0')} ${'argument ' * 20}').join('\n')}\n';
      final markdown = '```text\n$code```';
      final harness = await _showMessage(
        tester,
        AiMessage(id: 'code-segments', role: 'assistant', content: markdown),
      );
      final codeBlock = find.byType(ChatCodeBlock);
      final lineWindow = find.descendant(
        of: codeBlock,
        matching: find.byType(ChatContentWindow),
      );
      final content = tester.state<ChatContentWindowState>(lineWindow);

      expect(content.loadedChildCount, lessThan(content.widget.childCount));
      expect(harness.history.currentState!.loadedMessageCount, 1);
      expect(harness.history.currentState!.hasEarlier, isTrue);
      expect(
        find.textContaining('CODE-LINE-0000', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('CODE-LINE-1999', findRichText: true),
        findsWidgets,
      );
      await _keyboardCopyAll(tester, harness);
      expect(clipboard.text, markdown);

      final copy = find.descendant(
        of: codeBlock,
        matching: find.byKey(const ValueKey('ai-copy-code')),
      );
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pump();

      expect(clipboard.text, code);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final start in [1, 37]) {
    testWidgets(
      'a thousand ordered items retain their original numbering from $start',
      (tester) async {
        final markdown = List.generate(
          1000,
          (index) => '${start + index}. LIST-${index + 1}',
        ).join('\n');
        final harness = await _showMessage(
          tester,
          AiMessage(
            id: 'ordered-items-$start',
            role: 'assistant',
            content: markdown,
          ),
        );

        expect(find.text('LIST-1000'), findsOneWidget);
        expect(find.text('${start + 999}.'), findsOneWidget);
        expect(find.text('LIST-1'), findsNothing);
        expect(find.text('$start.'), findsNothing);
        expect(_bodyRichText().evaluate().length, lessThan(200));
        expect(harness.history.currentState!.hasEarlier, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an older partial body does not mark the latest message as unloaded later',
    (tester) async {
      final clipboard = _captureClipboard(tester);
      final first = AiMessage(
        id: 'earlier-body',
        role: 'assistant',
        content: List.generate(
          160,
          (index) => 'A-${_paragraph(index)}',
        ).join('\n\n'),
      );
      final last = AiMessage(
        id: 'latest-body',
        role: 'assistant',
        content: List.generate(
          20,
          (index) => 'B-${_paragraph(index)}',
        ).join('\n\n'),
      );
      final harness = await _showMessages(tester, [first, last]);
      await _scrollMessageToBeginning(tester, harness, first.id);

      expect(_messageWindow(tester, first.id).hasLater, isTrue);
      await _scrollMessageToBeginning(tester, harness, last.id);
      harness.controller.jumpTo(harness.controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(_messageWindow(tester, first.id).hasEarlier, isFalse);
      expect(_messageWindow(tester, first.id).hasLater, isTrue);
      expect(_messageWindow(tester, last.id).hasEarlier, isFalse);
      expect(_messageWindow(tester, last.id).hasLater, isFalse);
      expect(harness.history.currentState!.hasEarlier, isFalse);
      expect(harness.history.currentState!.hasLater, isFalse);
      expect(harness.history.currentState!.hasUnloadedContent, isTrue);
      expect(harness.controller.position.extentAfter, closeTo(0, .01));
      expect(
        find.textContaining('B-PARA-0019', findRichText: true),
        findsOneWidget,
      );
      await _keyboardCopyAll(tester, harness);

      expect(clipboard.text, '${first.content}\n\n${last.content}');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'identical bodies with different message IDs restore independent ranges',
    (tester) async {
      final markdown = List.generate(160, _paragraph).join('\n\n');
      final first = AiMessage(
        id: 'same-text-a',
        role: 'assistant',
        content: markdown,
      );
      final last = AiMessage(
        id: 'same-text-b',
        role: 'assistant',
        content: markdown,
      );
      final harness = await _showMessages(tester, [first, last]);
      final lastStart = _messageWindow(tester, last.id).firstChildIndex;
      final lastEnd = _messageWindow(tester, last.id).lastChildIndex;
      await _scrollMessageToBeginning(tester, harness, first.id);
      final firstEnd = _messageWindow(tester, first.id).lastChildIndex;

      expect(_messageWindow(tester, first.id).firstChildIndex, 0);
      expect(_messageWindow(tester, first.id).hasLater, isTrue);
      expect(_messageWindow(tester, last.id).firstChildIndex, lastStart);
      expect(_messageWindow(tester, last.id).lastChildIndex, lastEnd);
      expect(lastStart, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      expect(_messageWindow(tester, first.id).firstChildIndex, 0);
      expect(_messageWindow(tester, first.id).lastChildIndex, firstEnd);
      expect(_messageWindow(tester, last.id).firstChildIndex, lastStart);
      expect(_messageWindow(tester, last.id).lastChildIndex, lastEnd);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'code horizontal width and offset survive unloading the widest segment',
    (tester) async {
      final theme = ThemeProvider();
      final vertical = ConversationScrollController();
      final registry = ChatContentRegistry(
        controller: vertical,
        followsLatest: () => false,
        hasSelection: () => false,
        onChanged: () {},
        storageId: 'wide-code',
      );
      final code = List.generate(
        2000,
        (index) => index == 1000
            ? 'WIDE-TARGET ${'argument ' * 300}'
            : 'code-$index ${'short ' * 6}',
      ).join('\n');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        registry.dispose();
        vertical.dispose();
        theme.dispose();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            scrollBehavior: const AppScrollBehavior(scrollbars: false),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 480,
                  height: 320,
                  child: ChatContentScope(
                    state: registry,
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        controller: vertical,
                        child: ChatCodeBlock(
                          key: const PageStorageKey('wide-code-block'),
                          text: code,
                          language: 'text',
                          theme: theme.themeData,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final blockState = tester.state(find.byType(ChatCodeBlock));
      final content = tester.state<ChatContentWindowState>(
        find.byType(ChatContentWindow),
      );
      final wide = find.byWidgetPredicate(
        (widget) =>
            widget is Text && (widget.data?.contains('WIDE-TARGET') ?? false),
      );
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('ai-code-horizontal-scroll')),
          )
          .controller!;

      for (
        var attempt = 0;
        attempt < 120 && wide.evaluate().isEmpty;
        attempt++
      ) {
        vertical.jumpTo(math.min(160, vertical.position.maxScrollExtent));
        await tester.pumpAndSettle();
      }
      expect(wide, findsOneWidget);
      final widestExtent = horizontal.position.maxScrollExtent;
      expect(widestExtent, greaterThan(120));
      horizontal.jumpTo(120);
      await tester.pumpAndSettle();

      for (var attempt = 0; attempt < 120 && content.hasLater; attempt++) {
        vertical.jumpTo(math.max(0, vertical.position.maxScrollExtent - 160));
        await tester.pumpAndSettle();
      }

      expect(content.hasLater, isFalse);
      expect(wide, findsNothing);
      expect(tester.state(find.byType(ChatCodeBlock)), same(blockState));
      expect(
        horizontal.position.maxScrollExtent,
        greaterThanOrEqualTo(widestExtent - .01),
      );
      expect(horizontal.offset, closeTo(120, .01));

      for (
        var attempt = 0;
        attempt < 120 && wide.evaluate().isEmpty;
        attempt++
      ) {
        vertical.jumpTo(math.min(160, vertical.position.maxScrollExtent));
        await tester.pumpAndSettle();
      }

      expect(wide, findsOneWidget);
      expect(tester.state(find.byType(ChatCodeBlock)), same(blockState));
      expect(horizontal.offset, closeTo(120, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'streaming past 2048 characters retains the existing reading window',
    (tester) async {
      final initial = List.generate(
        20,
        (index) => 'READ-$index A **formatted** paragraph ${'words ' * 6}',
      ).join('\n\n');
      expect(initial.length, lessThan(2048));
      final message = AiMessage(
        id: 'streaming-threshold',
        role: 'assistant',
        content: initial,
        status: AiResponseStatus.streaming,
      );
      final harness = await _showMessage(tester, message);
      harness.followsLatest = true;
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      expect(harness.controller.position.maxScrollExtent, greaterThan(160));
      expect(harness.controller.position.extentAfter, closeTo(0, .01));
      harness.controller.jumpTo(80);
      harness.followsLatest = false;
      await tester.pumpAndSettle();
      final markdownState = tester.state(find.byType(ChatMarkdownBody));
      final content = _messageWindow(tester, message.id);
      final anchor = _visibleRichText(tester);
      final anchorTop = tester.getTopLeft(anchor).dy;
      final offset = harness.controller.offset;
      final extended = '$initial\n\n${_longMarkdown()}';
      expect(extended.length, greaterThan(2048));
      harness.messages[0] = message.copyWith(content: extended);
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      expect(tester.state(find.byType(ChatMarkdownBody)), same(markdownState));
      expect(_messageWindow(tester, message.id), same(content));
      expect(tester.getTopLeft(anchor).dy, closeTo(anchorTop, .01));
      expect(harness.controller.offset, closeTo(offset, .01));
      expect(content.widget.childCount, greaterThan(1000));
      expect(content.loadedChildCount, lessThan(60));
      expect(
        find.textContaining('PARA-0999', findRichText: true),
        findsNothing,
      );
      expect(harness.history.currentState!.hasLater, isTrue);
      expect(harness.history.currentState!.hasUnloadedContent, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
