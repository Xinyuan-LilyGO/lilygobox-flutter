import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_content_window.dart';
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
          height: 200,
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
