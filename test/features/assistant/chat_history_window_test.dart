import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_content_window.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_scrollbar.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_selection.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_window.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_message_list.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/conversation_scroll_controller.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

List<AiMessage> _messages(int count) => List.generate(
  count,
  (index) => AiMessage(
    id: 'message-$index',
    role: index.isEven ? 'user' : 'assistant',
    content: 'History $index: a mixed-height conversation message.',
  ),
  growable: false,
);

Widget _app({
  required List<AiMessage> messages,
  required ConversationScrollController controller,
  required GlobalKey<ChatHistoryWindowState> history,
  PageStorageBucket? bucket,
  FocusNode? focus,
  GlobalKey<ChatHistorySelectionState>? selection,
  double Function(AiMessage)? messageHeight,
  bool Function()? followsLatest,
  double viewportHeight = 200,
  bool scrollbar = false,
}) => ChangeNotifierProvider(
  create: (_) => ThemeProvider(),
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: appLocalizationDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    scrollBehavior: const AppScrollBehavior(scrollbars: false),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: viewportHeight,
          child: PageStorage(
            bucket: bucket ?? PageStorageBucket(),
            child: ChatHistorySelection(
              key: selection,
              messages: messages,
              focusNode: focus ?? FocusNode(skipTraversal: true),
              hasUnloadedMessages: () =>
                  (history.currentState?.hasEarlier ?? false) ||
                  (history.currentState?.hasLater ?? false),
              child: ChatHistoryWindow(
                key: history,
                historyId: 'stress-conversation',
                messages: messages,
                controller: controller,
                scrollbar: scrollbar,
                followsLatest: followsLatest ?? () => false,
                hasSelection: () =>
                    selection?.currentState?.hasSelection ?? false,
                onRangeChanged: (_) {},
                itemBuilder: (message) => SizedBox(
                  key: ValueKey(message.id),
                  height:
                      messageHeight?.call(message) ??
                      (int.parse(message.id.split('-').last).isEven
                          ? 100
                          : 150),
                  child: Text(message.content),
                ),
                viewportBuilder: (context, child) => SingleChildScrollView(
                  key: const PageStorageKey('history-scroll'),
                  controller: controller,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

List<String> _mountedMessageIds(WidgetTester tester) {
  final list = tester.widget<ChatMessageList>(find.byType(ChatMessageList));
  return [
    for (final child in list.children)
      (child as ChatContentMessageScope).messageId,
  ];
}

Finder _visibleMessage(WidgetTester tester) {
  final middle = tester.getCenter(find.byType(SingleChildScrollView));
  for (final id in _mountedMessageIds(tester)) {
    final finder = find.byKey(ValueKey(id));
    if (tester.getRect(finder).contains(middle)) return finder;
  }
  throw StateError('The viewport has no message at its center');
}

void main() {
  final wheelMotion = ValueVariant<bool>({false, true});
  testWidgets(
    'wheel over the painted history track matches the chat viewport',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
            disableAnimations: wheelMotion.currentValue!,
          );
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final scroll = ConversationScrollController();
      final history = GlobalKey<ChatHistoryWindowState>();
      final focus = FocusNode();
      addTearDown(scroll.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _app(
          messages: _messages(10000),
          controller: scroll,
          history: history,
          focus: focus,
          scrollbar: true,
          messageHeight: (_) => 100,
        ),
      );
      await tester.pumpAndSettle();
      final viewport = find.byType(SingleChildScrollView);
      final middle = tester.getCenter(viewport);
      final bar = tester.widget<ChatHistoryScrollbar>(
        find.byType(ChatHistoryScrollbar),
      );
      bar.seek(.5, true);
      await tester.pumpAndSettle();
      final paint = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is ScrollbarPainter,
      );
      final painter = tester.widget<CustomPaint>(paint).foregroundPainter!;
      final bounds = tester.getRect(paint);
      double readOffset() =>
          tester
                  .widget<ChatMessageList>(find.byType(ChatMessageList))
                  .firstIndex *
              100.0 +
          scroll.offset;
      Future<double> wheel(Offset point) async {
        final start = readOffset();
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: point,
            kind: PointerDeviceKind.mouse,
            scrollDelta: const Offset(0, 80),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();
        return readOffset() - start;
      }

      final ordinary = await wheel(middle);
      expect(ordinary, closeTo(80, .01));
      final localTrack = [
        for (var inset = 1; inset <= 24; inset++)
          Offset(bounds.width - inset, bounds.height / 2),
      ].firstWhere((point) => painter.hitTest(point) == true);
      expect(await wheel(bounds.topLeft + localTrack), closeTo(ordinary, .01));
      expect(
        await wheel(Offset(bounds.right - 30, middle.dy)),
        closeTo(ordinary, .01),
      );
    },
    variant: wheelMotion,
  );

  testWidgets('clicking the history track moves the chat by a viewport page', (
    tester,
  ) async {
    final scroll = ConversationScrollController();
    final history = GlobalKey<ChatHistoryWindowState>();
    final focus = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(focus.dispose);
    double heightBefore(int count) =>
        count ~/ 2 * 250 + (count.isOdd ? 100 : 0);
    await tester.pumpWidget(
      _app(
        messages: _messages(10000),
        controller: scroll,
        history: history,
        focus: focus,
        viewportHeight: 800,
        scrollbar: true,
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<ChatHistoryScrollbar>(find.byType(ChatHistoryScrollbar))
        .seek(.5, true);
    await tester.pumpAndSettle();

    final paint = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.foregroundPainter is ScrollbarPainter,
    );
    final painter = tester.widget<CustomPaint>(paint).foregroundPainter!;
    final bounds = tester.getRect(paint);
    double readOffset() =>
        heightBefore(
          tester
              .widget<ChatMessageList>(find.byType(ChatMessageList))
              .firstIndex,
        ) +
        scroll.offset;
    final initial = readOffset();
    final page = scroll.position.viewportDimension * .8;
    for (final (fraction, expected) in [
      (0.25, initial - page),
      (0.75, initial),
    ]) {
      final localTrack = [
        for (var inset = 1; inset <= 24; inset++)
          Offset(bounds.width - inset, bounds.height * fraction),
      ].firstWhere((point) => painter.hitTest(point) == true);
      await tester.tapAt(
        bounds.topLeft + localTrack,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(readOffset(), closeTo(expected, .01));
    }
  });

  testWidgets(
    'fast wheel bursts through the middle of a ten-thousand-message history match an uninterrupted viewport',
    (tester) async {
      const size = Size(2048, 1220);
      const referenceKey = ValueKey('reference-viewport');
      const viewportHeight = 960.0;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final reference = ScrollController(initialScrollOffset: 400000);
      final scroll = ConversationScrollController();
      final focus = FocusNode();
      final history = GlobalKey<ChatHistoryWindowState>();
      addTearDown(reference.dispose);
      addTearDown(scroll.dispose);
      addTearDown(focus.dispose);
      Future<List<double>> trace(
        Finder viewport,
        double Function() read,
      ) async {
        final coordinates = <double>[];
        final start = read();
        final point = tester.getCenter(viewport);
        var elapsed = const Duration(seconds: 1);
        for (var frame = 0; frame < 112; frame++) {
          final frameTime = Duration(milliseconds: frame % 8 == 5 ? 48 : 16);
          final inputCount = frame % 56 < 40
              ? frameTime.inMilliseconds ~/ 8
              : 0;
          for (var input = 0; input < inputCount; input++) {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                kind: PointerDeviceKind.mouse,
                timeStamp: elapsed + Duration(milliseconds: input * 8),
                position: point,
                scrollDelta: Offset(0, frame < 56 ? -100 : 100),
              ),
            );
          }
          await tester.pump(frameTime);
          elapsed += frameTime;
          coordinates.add(read() - start);
        }
        return coordinates;
      }

      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(scrollbars: false),
          home: Center(
            child: SizedBox(
              height: viewportHeight,
              width: 400,
              child: SingleChildScrollView(
                key: referenceKey,
                controller: reference,
                child: const SizedBox(height: 1000000),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final expected = await trace(
        find.byKey(referenceKey),
        () => reference.offset,
      );
      double heightThrough(int count) =>
          (count ~/ 2) * 160.0 + (count.isOdd ? 64 : 0) + (count ~/ 20) * 160;
      await tester.pumpWidget(
        _app(
          messages: _messages(10000),
          controller: scroll,
          history: history,
          focus: focus,
          viewportHeight: viewportHeight,
          scrollbar: true,
          messageHeight: (message) {
            final index = int.parse(message.id.split('-').last);
            return heightThrough(index + 1) - heightThrough(index);
          },
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<ChatHistoryScrollbar>(find.byType(ChatHistoryScrollbar))
          .seek(.36295, true);
      await tester.pumpAndSettle();
      double logicalOffset() {
        final list = tester.widget<ChatMessageList>(
          find.byType(ChatMessageList),
        );
        expect(list.children.length, lessThanOrEqualTo(144));
        return heightThrough(list.firstIndex) + scroll.offset;
      }

      final actual = await trace(
        find.byType(SingleChildScrollView),
        logicalOffset,
      );
      expect(expected[55], lessThan(-20000));
      expect(expected.last, closeTo(0, .01));
      for (var frame = 0; frame < expected.length; frame++) {
        expect(
          actual[frame],
          closeTo(expected[frame], .01),
          reason: 'frame $frame',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final count in [10000, 100000, 1000000, 3000000]) {
    testWidgets('$count concrete message models mount only a history window', (
      tester,
    ) async {
      final creation = Stopwatch()..start();
      final messages = _messages(count);
      creation.stop();
      final scroll = ConversationScrollController();
      final focus = FocusNode();
      final history = GlobalKey<ChatHistoryWindowState>();
      addTearDown(scroll.dispose);
      addTearDown(focus.dispose);
      final mounting = Stopwatch()..start();
      await tester.pumpWidget(
        _app(
          messages: messages,
          controller: scroll,
          history: history,
          focus: focus,
        ),
      );
      await tester.pumpAndSettle();
      mounting.stop();
      expect(messages.length, count);
      expect(
        history.currentState!.loadedMessageCount,
        ChatHistoryWindowState.initialMessages,
      );
      expect(find.text(messages.first.content), findsNothing);
      expect(find.text(messages.last.content), findsOneWidget);
      expect(scroll.position.extentAfter, 0);
      expect(tester.takeException(), isNull);
      debugPrint(
        'HISTORY_WINDOW_MODELS count=$count create_us=${creation.elapsedMicroseconds} mount_us=${mounting.elapsedMicroseconds} mounted=${history.currentState!.loadedMessageCount}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'preloads earlier messages before the boundary without moving the anchor',
    (tester) async {
      final messages = _messages(10000);
      final scroll = ConversationScrollController();
      final focus = FocusNode();
      final history = GlobalKey<ChatHistoryWindowState>();
      addTearDown(scroll.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _app(
          messages: messages,
          controller: scroll,
          history: history,
          focus: focus,
        ),
      );
      await tester.pumpAndSettle();
      final initialIds = _mountedMessageIds(tester);
      scroll.jumpTo(625);
      final anchor = _visibleMessage(tester);
      final before = tester.getTopLeft(anchor).dy;
      await tester.pumpAndSettle();
      expect(
        history.currentState!.loadedMessageCount,
        initialIds.length + ChatHistoryWindowState.batchMessages,
      );
      expect(
        _mountedMessageIds(tester).skip(ChatHistoryWindowState.batchMessages),
        initialIds,
      );
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
      expect(scroll.offset, greaterThan(625));
      for (
        var batch = 0;
        batch < ChatHistoryWindowState.maximumMessages &&
            !history.currentState!.hasLater;
        batch++
      ) {
        final firstBefore = _mountedMessageIds(tester).first;
        scroll.jumpTo(625);
        await tester.pumpAndSettle();
        expect(_mountedMessageIds(tester).first, isNot(firstBefore));
        expect(
          history.currentState!.loadedMessageCount,
          lessThanOrEqualTo(
            ChatHistoryWindowState.maximumMessages +
                ChatHistoryWindowState.initialMessages,
          ),
        );
        expect(tester.takeException(), isNull);
      }
      expect(messages.length, 10000);
      expect(history.currentState!.hasLater, isTrue);
      history.currentState!.showLatest();
      await tester.pumpAndSettle();
      expect(find.text(messages.last.content), findsOneWidget);
      expect(
        history.currentState!.loadedMessageCount,
        ChatHistoryWindowState.initialMessages,
      );
    },
  );

  testWidgets(
    'short rows before a very tall row retain the visible anchor when trimming',
    (tester) async {
      final messages = _messages(1000);
      final scroll = ConversationScrollController();
      final focus = FocusNode();
      final history = GlobalKey<ChatHistoryWindowState>();
      addTearDown(scroll.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _app(
          messages: messages,
          controller: scroll,
          history: history,
          focus: focus,
          messageHeight: (message) => message == messages.last ? 5000 : 3,
        ),
      );
      await tester.pumpAndSettle();
      final firstId = _mountedMessageIds(tester).first;
      scroll.jumpTo(16);
      final anchor = find.byKey(ValueKey(firstId));
      final before = tester.getTopLeft(anchor).dy;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
      expect(find.byKey(const ValueKey('message-999')), findsOneWidget);
      expect(
        history.currentState!.loadedMessageCount,
        greaterThan(ChatHistoryWindowState.maximumMessages),
      );
      expect(scroll.position.extentBefore, greaterThanOrEqualTo(800));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'holding the pointer fixes the range while dragging the scrollbar',
    (tester) async {
      final messages = _messages(10000);
      final scroll = ConversationScrollController();
      final focus = FocusNode();
      final history = GlobalKey<ChatHistoryWindowState>();
      addTearDown(scroll.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _app(
          messages: messages,
          controller: scroll,
          history: history,
          focus: focus,
        ),
      );
      await tester.pumpAndSettle();
      final initialIds = _mountedMessageIds(tester);
      final pointer = await tester.startGesture(
        tester.getTopRight(find.byType(SingleChildScrollView)) +
            const Offset(-8, 80),
        kind: PointerDeviceKind.mouse,
      );
      final extent = scroll.position.maxScrollExtent;
      for (final fraction in [.2, .5, .8, .1, 0.0]) {
        scroll.jumpTo(extent * fraction);
        await tester.pump();
        expect(scroll.position.maxScrollExtent, closeTo(extent, .01));
        expect(scroll.offset, closeTo(extent * fraction, .01));
        expect(_mountedMessageIds(tester), initialIds);
      }
      final anchor = _visibleMessage(tester);
      final before = tester.getTopLeft(anchor).dy;
      await pointer.up();
      await tester.pumpAndSettle();
      final releasedIds = _mountedMessageIds(tester);
      final added = releasedIds.length - initialIds.length;
      expect(added, greaterThanOrEqualTo(ChatHistoryWindowState.batchMessages));
      expect(added % ChatHistoryWindowState.batchMessages, 0);
      expect(releasedIds.skip(added), initialIds);
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
      expect(scroll.offset, greaterThan(0));
    },
  );

  testWidgets('saved reading range and offset are restored together', (
    tester,
  ) async {
    final messages = _messages(10000);
    final bucket = PageStorageBucket();
    final focus = FocusNode();
    final history = GlobalKey<ChatHistoryWindowState>();
    addTearDown(focus.dispose);
    var scroll = ConversationScrollController();
    await tester.pumpWidget(
      _app(
        messages: messages,
        controller: scroll,
        history: history,
        bucket: bucket,
        focus: focus,
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(625);
    await tester.pumpAndSettle();
    final saved = scroll.offset;
    final mounted = history.currentState!.loadedMessageCount;
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    scroll = ConversationScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _app(
        messages: messages,
        controller: scroll,
        history: history,
        bucket: bucket,
        focus: focus,
      ),
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(saved, .01));
    expect(history.currentState!.loadedMessageCount, mounted);
  });

  testWidgets(
    'messages appended during a scrollbar drag stay pending until release',
    (tester) async {
      final messages = _messages(1000).toList();
      final scroll = ConversationScrollController();
      final focus = FocusNode();
      final history = GlobalKey<ChatHistoryWindowState>();
      final bucket = PageStorageBucket();
      addTearDown(scroll.dispose);
      addTearDown(focus.dispose);
      Widget app() => _app(
        messages: messages,
        controller: scroll,
        history: history,
        focus: focus,
        bucket: bucket,
        followsLatest: () => true,
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final pointer = await tester.startGesture(
        tester.getTopRight(find.byType(SingleChildScrollView)) +
            const Offset(-8, 80),
        kind: PointerDeviceKind.mouse,
      );
      final extent = scroll.position.maxScrollExtent;
      final loaded = history.currentState!.loadedMessageCount;
      messages.addAll(_messages(1040).skip(1000));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(scroll.position.maxScrollExtent, closeTo(extent, .01));
      expect(history.currentState!.loadedMessageCount, loaded);
      expect(history.currentState!.hasLater, isTrue);
      expect(find.byKey(const ValueKey('message-1039')), findsNothing);

      await pointer.up();
      await tester.pumpAndSettle();

      expect(history.currentState!.hasLater, isFalse);
      expect(find.byKey(const ValueKey('message-1039')), findsOneWidget);
      messages.addAll(_messages(1041).skip(1040));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(history.currentState!.hasLater, isFalse);
      expect(find.byKey(const ValueKey('message-1040')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'leaving between a preload range update and its layout restores the last reading position',
    (tester) async {
      final messages = _messages(10000);
      final bucket = PageStorageBucket();
      final focus = FocusNode();
      final history = GlobalKey<ChatHistoryWindowState>();
      var scroll = ConversationScrollController();
      addTearDown(focus.dispose);
      Widget app() => _app(
        messages: messages,
        controller: scroll,
        history: history,
        bucket: bucket,
        focus: focus,
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final initialIds = _mountedMessageIds(tester);
      final pendingFirst =
          messages[messages.indexWhere(
                    (message) => message.id == initialIds.first,
                  ) -
                  ChatHistoryWindowState.batchMessages]
              .id;
      scroll.jumpTo(625);
      final anchor = _visibleMessage(tester);
      final before = tester.getTopLeft(anchor).dy;
      await tester.pump();
      expect(
        history.currentState!.loadedMessageCount,
        initialIds.length + ChatHistoryWindowState.batchMessages,
      );
      expect(_mountedMessageIds(tester), initialIds);
      expect(find.byKey(ValueKey(pendingFirst)), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      scroll = ConversationScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(anchor, findsOneWidget);
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'wheel input crosses a pending history page without losing travel',
    (tester) async {
      final scroll = ConversationScrollController();
      final history = GlobalKey<ChatHistoryWindowState>();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _app(messages: _messages(10000), controller: scroll, history: history),
      );
      await tester.pumpAndSettle();
      final viewport = find.byType(SingleChildScrollView);
      Future<void> wheel(double delta) => tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(viewport),
          scrollDelta: Offset(0, delta),
        ),
      );
      scroll.jumpTo(20);
      final anchor = _visibleMessage(tester);
      final initialTop = tester.getTopLeft(anchor).dy;
      expect(history.currentState!.hasEarlier, isTrue);
      await wheel(-100);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 8));
      expect(tester.getTopLeft(anchor).dy - initialTop, closeTo(100, .01));
      scroll.jumpTo(scroll.position.maxScrollExtent - 20);
      expect(history.currentState!.hasLater, isFalse);
      await wheel(100);
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, closeTo(0, .01));
      for (var page = 0; page < 12 && !history.currentState!.hasLater; page++) {
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
      }
      expect(history.currentState!.hasLater, isTrue);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      final lowerAnchor = _visibleMessage(tester);
      final lowerTop = tester.getTopLeft(lowerAnchor).dy;
      await wheel(100);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 8));
      expect(tester.getTopLeft(lowerAnchor).dy - lowerTop, closeTo(-100, .01));

      scroll.jumpTo(20);
      final reverseAnchor = _visibleMessage(tester);
      await wheel(-100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final reverseTop = tester.getTopLeft(reverseAnchor).dy;
      await wheel(60);
      await tester.pumpAndSettle(const Duration(milliseconds: 8));
      expect(
        tester.getTopLeft(reverseAnchor).dy - reverseTop,
        closeTo(-60, .01),
      );
    },
  );

  testWidgets('Windows reader moves and then stops a 10000-message chat', (
    tester,
  ) async {
    final scroll = ConversationScrollController();
    final history = GlobalKey<ChatHistoryWindowState>();
    final focus = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        messages: _messages(10000),
        controller: scroll,
        history: history,
        focus: focus,
        viewportHeight: 420,
        scrollbar: true,
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    final bar = tester.widget<ChatHistoryScrollbar>(
      find.byType(ChatHistoryScrollbar),
    );
    bar.seek((4106 - .5) / 10000, true);
    await tester.pumpAndSettle();
    final visible = _visibleMessage(tester);
    final initialTop = tester.getTopLeft(visible).dy;
    final start = tester.getCenter(find.byType(SingleChildScrollView));
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('lilygobox/reader_mode');
    var samples = 0;
    int? session;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start') {
        final args = call.arguments as List<Object?>;
        expect(args[1], false);
        session = args[0] as int;
        return true;
      }
      expect(call.arguments, session);
      return ++samples <= 2 ? -12.0 * tester.view.devicePixelRatio : null;
    });
    final end = start - const Offset(0, 190);
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await mouse.addPointer(location: start);
    await mouse.down(start);
    await tester.pump();
    await mouse.moveTo(end);
    await tester.pump();
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    expect(session, isNotNull);
    expect(samples, 3);
    expect(tester.getTopLeft(visible).dy, closeTo(initialTop + 24, .01));
    await mouse.up();
    await tester.pump();
    await mouse.moveTo(end);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.getTopLeft(visible).dy, closeTo(initialTop + 24, .01));
    expect(scroll.position.isScrollingNotifier.value, isFalse);
    expect(focus.hasFocus, isTrue);
    await mouse.removePointer();
  });

  testWidgets('preloading preserves the remaining cumulative wheel animation', (
    tester,
  ) async {
    final messages = _messages(10000);
    final scroll = ConversationScrollController();
    final focus = FocusNode();
    final history = GlobalKey<ChatHistoryWindowState>();
    addTearDown(scroll.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        messages: messages,
        controller: scroll,
        history: history,
        focus: focus,
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(925);
    await tester.pumpAndSettle();
    final anchor = _visibleMessage(tester);
    final before = tester.getTopLeft(anchor).dy;
    final initialCount = history.currentState!.loadedMessageCount;
    final point = tester.getCenter(find.byType(SingleChildScrollView));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: point,
        scrollDelta: const Offset(0, -300),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: point,
        scrollDelta: const Offset(0, -300),
        kind: PointerDeviceKind.mouse,
      ),
    );
    var previousTop = tester.getTopLeft(anchor).dy;
    var previousCount = initialCount;
    for (var frame = 1; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 8));
      final top = tester.getTopLeft(anchor).dy;
      final count = history.currentState!.loadedMessageCount;
      expect(top, greaterThan(previousTop), reason: 'frame $frame');
      expect(count - previousCount, inInclusiveRange(0, 2));
      previousTop = top;
      previousCount = count;
    }
    expect(previousCount, greaterThan(initialCount));
    await tester.pumpAndSettle();
    expect(
      history.currentState!.loadedMessageCount,
      greaterThan(ChatHistoryWindowState.initialMessages),
    );
    expect(tester.getTopLeft(anchor).dy, closeTo(before + 600, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an isolated wheel notch keeps its frame trajectory without mounting a cold page mid-flight',
    (tester) async {
      final scroll = ConversationScrollController();
      final history = GlobalKey<ChatHistoryWindowState>();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _app(messages: _messages(10000), controller: scroll, history: history),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(
        scroll.position.viewportDimension *
                ChatHistoryWindowState.preloadScreens +
            25,
      );
      await tester.pumpAndSettle();
      final anchor = _visibleMessage(tester);
      final initialTop = tester.getTopLeft(anchor).dy;
      final initialWindow = _mountedMessageIds(tester);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(SingleChildScrollView)),
          scrollDelta: const Offset(0, -100),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      for (var frame = 1; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        final remaining = 1 - frame / 25;
        final expected = 100 * (1 - remaining * remaining * remaining);
        expect(
          tester.getTopLeft(anchor).dy - initialTop,
          closeTo(expected, .01),
          reason: 'frame $frame',
        );
        expect(
          _mountedMessageIds(tester).first,
          initialWindow.first,
          reason: 'the reading buffer still contains more than three screens',
        );
      }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy - initialTop, closeTo(100, .01));
      final restoredWindow = _mountedMessageIds(tester);
      expect(restoredWindow.first, isNot(initialWindow.first));
      expect(
        restoredWindow.length - initialWindow.length,
        inInclusiveRange(1, 4),
      );
    },
  );

  testWidgets(
    'select all and copy include the unmounted first and last messages',
    (tester) async {
      final messages = _messages(1000);
      final scroll = ConversationScrollController();
      final focus = FocusNode();
      final history = GlobalKey<ChatHistoryWindowState>();
      final selection = GlobalKey<ChatHistorySelectionState>();
      addTearDown(scroll.dispose);
      addTearDown(focus.dispose);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': false};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        _app(
          messages: messages,
          controller: scroll,
          history: history,
          focus: focus,
          selection: selection,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(messages.first.content), findsNothing);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, startsWith(messages.first.content));
      expect(copied, endsWith(messages.last.content));
      expect(
        history.currentState!.loadedMessageCount,
        ChatHistoryWindowState.initialMessages,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
