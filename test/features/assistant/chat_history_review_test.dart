import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_selection.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_window.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_message_list.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

void main() {
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider splitView;
  late AppNavigationProvider navigation;
  late AssistantTestScope scope;
  late PageStorageBucket bucket;

  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    splitView = SplitViewProvider();
    navigation = AppNavigationProvider();
    bucket = PageStorageBucket();
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: splitView,
    );
  });

  tearDown(() {
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    splitView.dispose();
    navigation.dispose();
  });

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider.value(value: language),
      ChangeNotifierProvider.value(value: scope.provider),
      ChangeNotifierProvider.value(value: navigation),
    ],
    child: MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: PageStorage(
          bucket: bucket,
          child: const AssistantPage(readOnly: true),
        ),
      ),
    ),
  );

  Future<void> restoreMessages(WidgetTester tester, int count) async {
    await tester.runAsync(() => scope.provider.initialized);
    scope.provider.restoreWorkspaceConversation({
      'messages': [
        for (var index = 0; index < count; index++)
          ConversationCodec.message(
            AiMessage(
              id: 'reading-$index',
              role: 'user',
              content: List.generate(
                8,
                (line) => 'Message $index, line $line of the reading fixture.',
              ).join('\n'),
              createdAt: DateTime(2026, 11, 19, 1, 2, 3),
            ),
          ),
      ],
      'history': <Map<String, Object?>>[],
    });
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  Finder scrollFinder() => find.byKey(const ValueKey('ai-message-scroll'));

  ScrollController scrollController(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(scrollFinder()).controller!;

  ChatHistoryWindowState historyState(WidgetTester tester) =>
      tester.state<ChatHistoryWindowState>(find.byType(ChatHistoryWindow));

  List<String> mountedMessageIds(WidgetTester tester) {
    final list = tester.widget<ChatMessageList>(find.byType(ChatMessageList));
    return [
      for (final child in list.children)
        if (child.key case ValueKey<(String, String)>(value: final value)
            when value.$1 == 'chat-content-message')
          value.$2,
    ];
  }

  int unloadedLaterMessages(WidgetTester tester) {
    final lastId = mountedMessageIds(tester).last;
    final messages = scope.provider.messages;
    final lastIndex = messages.indexWhere((message) => message.id == lastId);
    expect(lastIndex, greaterThanOrEqualTo(0));
    return messages.length - lastIndex - 1;
  }

  Future<void> moveToEarlierWindow(WidgetTester tester) async {
    final controller = scrollController(tester);
    const minimumLaterMessages =
        ChatHistoryWindowState.initialMessages +
        ChatHistoryWindowState.batchMessages;
    for (
      var batch = 0;
      batch < ChatHistoryWindowState.maximumMessages &&
          unloadedLaterMessages(tester) < minimumLaterMessages;
      batch++
    ) {
      final firstBefore = mountedMessageIds(tester).first;
      controller.jumpTo(80);
      await tester.pumpAndSettle();
      expect(mountedMessageIds(tester).first, isNot(firstBefore));
    }
    expect(historyState(tester).hasEarlier, isTrue);
    expect(historyState(tester).hasLater, isTrue);
    expect(
      unloadedLaterMessages(tester),
      greaterThanOrEqualTo(minimumLaterMessages),
    );
  }

  Finder lastMountedMessage(WidgetTester tester) =>
      find.byKey(ValueKey(mountedMessageIds(tester).last));

  Finder middleVisibleMessage(WidgetTester tester) {
    final middle = tester.getCenter(scrollFinder()).dy;
    final list = tester.widget<ChatMessageList>(find.byType(ChatMessageList));
    for (final child in list.children) {
      final key = child.key;
      if (key is! ValueKey<(String, String)> ||
          key.value.$1 != 'chat-content-message') {
        continue;
      }
      final id = key.value.$2;
      final finder = find.byKey(ValueKey(id));
      final rect = tester.getRect(finder);
      if (rect.top <= middle && rect.bottom > middle) return finder;
    }
    throw StateError('The viewport has no message at its center');
  }

  testWidgets(
    'releasing a scrollbar at a loaded history boundary retains the reading anchor',
    (tester) async {
      await restoreMessages(tester, 600);
      await moveToEarlierWindow(tester);
      final controller = scrollController(tester);
      final pointer = await tester.startGesture(
        tester.getTopRight(scrollFinder()) + const Offset(-2, 80),
        kind: PointerDeviceKind.mouse,
      );
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final anchor = lastMountedMessage(tester);
      final before = tester.getTopLeft(anchor).dy;
      expect(historyState(tester).hasLater, isTrue);

      await pointer.up();
      await tester.pumpAndSettle();

      expect(historyState(tester).hasLater, isTrue);
      expect(anchor, findsOneWidget);
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
      expect(controller.position.extentAfter, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'restoring the bottom of an earlier window does not follow the global latest message',
    (tester) async {
      await restoreMessages(tester, 600);
      await moveToEarlierWindow(tester);
      final controller = scrollController(tester);
      final pointer = await tester.startGesture(
        tester.getTopRight(scrollFinder()) + const Offset(-2, 80),
        kind: PointerDeviceKind.mouse,
      );
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final anchor = lastMountedMessage(tester);
      final before = tester.getTopLeft(anchor).dy;
      expect(historyState(tester).hasLater, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await pointer.up();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(historyState(tester).hasLater, isTrue);
      expect(anchor, findsOneWidget);
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'clearing a selection trims an oversized middle window without moving the visible message',
    (tester) async {
      await restoreMessages(tester, 600);
      final selection = tester.widget<ChatHistorySelection>(
        find.byType(ChatHistorySelection),
      );
      selection.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final selectionState = tester.state<ChatHistorySelectionState>(
        find.byType(ChatHistorySelection),
      );
      expect(selectionState.hasSelection, isTrue);
      final controller = scrollController(tester);
      const oversizedCount = ChatHistoryWindowState.maximumMessages * 2;
      while (historyState(tester).loadedMessageCount <= oversizedCount) {
        final before = historyState(tester).loadedMessageCount;
        controller.jumpTo(80);
        await tester.pumpAndSettle();
        expect(historyState(tester).loadedMessageCount, greaterThan(before));
      }
      expect(
        historyState(tester).loadedMessageCount,
        greaterThan(oversizedCount),
      );
      expect(selectionState.hasSelection, isTrue);
      controller.jumpTo(controller.position.maxScrollExtent * .5);
      await tester.pumpAndSettle();
      final loaded = historyState(tester).loadedMessageCount;
      final anchor = middleVisibleMessage(tester);
      final before = tester.getTopLeft(anchor).dy;

      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      region.clearSelection();
      region.hideToolbar();
      await tester.pumpAndSettle();

      expect(selectionState.hasSelection, isFalse);
      expect(historyState(tester).loadedMessageCount, lessThan(loaded));
      expect(
        historyState(tester).loadedMessageCount,
        lessThanOrEqualTo(ChatHistoryWindowState.maximumMessages),
      );
      expect(anchor, findsOneWidget);
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'selecting a fully mounted history keeps rendered timestamps in copied text',
    (tester) async {
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
      await restoreMessages(tester, 2);
      expect(historyState(tester).hasEarlier, isFalse);
      expect(historyState(tester).hasLater, isFalse);
      final selection = tester.widget<ChatHistorySelection>(
        find.byType(ChatHistorySelection),
      );
      selection.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(copied, contains('Message 0, line 0'));
      expect(copied, contains('Message 1, line 7'));
      expect(copied, contains('2026.11.19 01:02:03'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
