import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/desktop_card_selection.dart';
import 'package:lilygobox/core/widgets/settings/search_field.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/recycle_bin_dialog.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/storage_content.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

class _ObservedRecycledAgent extends AiRecycledAgent {
  _ObservedRecycledAgent({required super.record, required super.deletedAt});

  int recordReads = 0;

  @override
  Map<String, dynamic> get record {
    recordReads++;
    return super.record;
  }
}

void main() {
  Set<String> trackBuiltCards() {
    final builtIds = <String>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget case DesktopCardSelectionMenu(:final id)) {
        builtIds.add(id);
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    return builtIds;
  }

  Future<void> checkJumps(
    WidgetTester tester,
    ScrollPosition position,
    Set<String> builtIds,
  ) async {
    for (final fraction in [.02, .8047, 1.0, 0.0]) {
      builtIds.clear();
      final elapsed = Stopwatch()..start();
      position.jumpTo(position.maxScrollExtent * fraction);
      await tester.pumpAndSettle();
      expect(
        builtIds.length,
        lessThan(30),
        reason: 'Jump to $fraction took ${elapsed.elapsedMilliseconds} ms',
      );
    }
  }

  Future<void> dragScrollbar(
    WidgetTester tester,
    Finder list,
    ScrollPosition position,
    Set<String> builtIds,
  ) async {
    await tester.ensureVisible(list);
    final region = tester.widget<DesktopCardSelectionRegion>(
      find.byType(DesktopCardSelectionRegion),
    );
    region.selection.selectAll(region.ids.take(2));
    region.onChanged();
    await tester.pumpAndSettle();
    final selected = region.selection.selected.toSet();
    expect(selected, hasLength(2));
    position.jumpTo(1);
    await tester.pump();
    position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 32));
    final rect = tester.getRect(list);
    final thumb = Offset(rect.right - 9, rect.top + 18);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(thumb);
    await tester.pumpAndSettle();
    builtIds.clear();
    await mouse.down(thumb);
    expect(region.selection.selected, selected);
    await mouse.moveBy(Offset(0, rect.height * .7));
    await tester.pump();
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(position.maxScrollExtent * .5));
    expect(region.selection.selected, selected);
    expect(builtIds.length, lessThan(30));
  }

  test(
    'recycle metadata does not decode or expose the conversation snapshot',
    () {
      final entry = _ObservedRecycledAgent(
        record: {
          'id': '1000-0',
          'title': 'Retained agent',
          'task': 'Retained task',
          'conversation': {
            'messages': List.filled(100, 'Long response ' * 100),
          },
        },
        deletedAt: DateTime.now(),
      );
      for (var access = 0; access < 1000; access++) {
        expect(entry.id, '1000-0');
        expect(entry.title, 'Retained agent');
        expect(entry.task, 'Retained task');
      }
      expect(entry.recordReads, 0);
      final decoded = entry.record;
      decoded['title'] = 'Changed outside';
      (decoded['conversation'] as Map)['messages'] = [];
      expect(entry.title, 'Retained agent');
      expect((entry.record['conversation'] as Map)['messages'], hasLength(100));
    },
  );

  testWidgets('10000 paged memories build only nearby cards during long jumps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final split = SplitViewProvider();
    final storage = AgentStorage(path: ':memory:');
    late AssistantTestScope scope;
    late AiWorkspaceProvider workspace;
    late String owner;
    await tester.runAsync(() async {
      scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        storage: storage,
      );
      workspace = AiWorkspaceProvider(scope.provider);
      await workspace.initialized;
      await scope.provider.saveService(
        name: 'Local model',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['gpt-6.1-sol'],
        apiKey: 'test-key',
      );
      owner = (await workspace.create(
        title: 'Memory owner',
        task: 'Retain memories',
        kind: AiWorkspaceKind.primary,
        startImmediately: false,
      )).id;
      await storage.commitImport(workspace.exportData(), [
        for (var index = 0; index < 10000; index++)
          {
            'id': 'memory-$index',
            'owner': owner,
            'content':
                'Memory $index: ${index.isEven ? 'Retained details ' * 8 : 'Short'}',
          },
      ]);
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        await workspace.flush();
        workspace.dispose();
        scope.dispose();
        await storage.close();
      });
      theme.dispose();
      language.dispose();
      shell.dispose();
      split.dispose();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: workspace,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          scrollBehavior: const AppScrollBehavior(),
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: appLocalizationDelegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showAgentStorage(context, theme.themeData, owner),
                child: const Text('Open memories'),
              ),
            ),
          ),
        ),
      ),
    );
    final builtIds = trackBuiltCards();
    await tester.tap(find.text('Open memories'));
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final cards = find.byWidgetPredicate(
      (widget) =>
          widget is ListTile &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'storage-memory-card-',
          ),
    );
    expect(cards.evaluate().length, inInclusiveRange(2, 20));
    expect(
      tester
          .widget<DesktopCardSelectionRegion>(
            find.byType(DesktopCardSelectionRegion),
          )
          .ids,
      hasLength(50),
    );
    final before = {
      for (final element in cards.evaluate())
        element.widget.key: element.widget,
    };
    final target = cards.hitTestable().first;
    final targetKey = tester.widget(target).key;
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.byKey(targetKey!)).selected, isTrue);
    expect(
      cards.evaluate().where(
        (element) =>
            element.widget.key != targetKey &&
            identical(before[element.widget.key], element.widget),
      ),
      isNotEmpty,
    );
    final list = find.byKey(const ValueKey('storage-memory-list-scroll'));
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    final more = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == 'Load more',
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    for (var attempt = 0; attempt < 4 && more.evaluate().isEmpty; attempt++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    expect(more.hitTestable(), findsOneWidget);
    final loadMore = tester
        .widget<AppActionButton>(
          find.widgetWithText(AppActionButton, 'Load more'),
        )
        .onPressed!;
    await tester.tap(more);
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(cards.evaluate().length, lessThan(20));
    expect(
      tester
          .widget<DesktopCardSelectionRegion>(
            find.byType(DesktopCardSelectionRegion),
          )
          .ids,
      hasLength(100),
    );
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await checkJumps(tester, position, builtIds);
    final region = find.byType(DesktopCardSelectionRegion);
    for (var loaded = 150; loaded <= 10000; loaded += 50) {
      loadMore();
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        if (tester.widget<DesktopCardSelectionRegion>(region).ids.length ==
            loaded) {
          break;
        }
      }
      expect(
        tester.widget<DesktopCardSelectionRegion>(region).ids,
        hasLength(loaded),
      );
    }
    await checkJumps(tester, position, builtIds);
    await dragScrollbar(tester, list, position, builtIds);
    final ids = tester.widget<DesktopCardSelectionRegion>(region).ids;
    expect(ids.toSet(), hasLength(10000));
    final last = find.byKey(ValueKey('storage-memory-card-${ids.last}'));
    for (var attempt = 0; attempt < 4; attempt++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      if (last.evaluate().isNotEmpty) {
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
      }
      if (last.hitTestable().evaluate().isNotEmpty) break;
    }
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final count in [100, 500, 10000]) {
    for (final compact in [false, true]) {
      testWidgets(
        'recycle $count long conversations compact=$compact stay lazy',
        (tester) async {
          tester.view.physicalSize = compact
              ? const Size(420, 620)
              : const Size(2543, 1376);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final theme = ThemeProvider();
          final language = LanguageProvider();
          final shell = AppShellProvider();
          final split = SplitViewProvider();
          final storage = AgentStorage(path: ':memory:');
          late AssistantTestScope scope;
          late AiWorkspaceProvider workspace;
          await tester.runAsync(() async {
            scope = await createAssistantTestScope(
              theme: theme,
              language: language,
              shell: shell,
              splitView: split,
              storage: storage,
            );
            await scope.provider.initialized;
            final conversation = {
              ...scope.provider.snapshotWorkspaceConversation(),
              'messages': [
                for (
                  var messageIndex = 0;
                  messageIndex < (count == 10000 ? 1 : 20);
                  messageIndex++
                )
                  {
                    'id': 'message-$messageIndex',
                    'role': 'assistant',
                    'content': 'Long conversation response ' * 80,
                  },
              ],
            };
            await storage.saveWorkflow({
              'version': 1,
              'sessions': <Object?>[],
              'connections': <Object?>[],
              'recycleRetentionDays': 0,
              'recycleBin': [
                for (var entryIndex = 0; entryIndex < count; entryIndex++)
                  {
                    'record': {
                      'id': '1000-$entryIndex',
                      'title': 'Recycled agent $entryIndex',
                      'task': 'Retained task',
                      'kind': 'primary',
                      'createdAt': DateTime.now().toIso8601String(),
                      'conversation': conversation,
                    },
                    'deletedAt': DateTime.now().toIso8601String(),
                  },
              ],
            });
            workspace = AiWorkspaceProvider(scope.provider);
            await workspace.initialized;
          });
          addTearDown(() async {
            await tester.runAsync(() async {
              await workspace.flush();
              workspace.dispose();
              scope.dispose();
              await storage.close();
            });
            theme.dispose();
            language.dispose();
            shell.dispose();
            split.dispose();
          });
          final snapshot = workspace.recycledAgents;
          expect(snapshot, hasLength(count));
          expect(identical(snapshot, workspace.recycledAgents), isTrue);
          final builtIds = trackBuiltCards();
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: workspace,
              child: MaterialApp(
                theme: ThemeData(platform: TargetPlatform.windows),
                scrollBehavior: const AppScrollBehavior(),
                locale: const Locale('en'),
                supportedLocales: const [Locale('en'), Locale('zh')],
                localizationsDelegates: appLocalizationDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(compact ? 1.5 : 1)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () =>
                          showAgentRecycleBin(context, theme.themeData),
                      child: const Text('Open bin'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open bin'));
          await tester.pumpAndSettle();
          final cards = find.byWidgetPredicate(
            (widget) =>
                widget is AnimatedContainer &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'recycle-agent-card-',
                ),
          );
          expect(cards.evaluate().length, lessThan(30));
          expect(builtIds.length, lessThan(30));
          final list = find.byKey(
            ValueKey(
              compact
                  ? 'recycle-agent-compact-scroll'
                  : 'recycle-agent-list-scroll',
            ),
          );
          final scrollable = find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          if (count == 10000) {
            await checkJumps(tester, position, builtIds);
            await dragScrollbar(tester, list, position, builtIds);
          }
          final last = find.byKey(
            ValueKey('recycle-agent-card-${snapshot.last.id}'),
          );
          for (var attempt = 0; attempt < 4; attempt++) {
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
            if (last.hitTestable().evaluate().isNotEmpty) break;
          }
          expect(last.hitTestable(), findsOneWidget);
          final previous = {
            for (final element in cards.evaluate())
              element.widget.key!: element.widget,
          };
          await tester.tap(last);
          await tester.pumpAndSettle();
          final region = tester.widget<DesktopCardSelectionRegion>(
            find.byType(DesktopCardSelectionRegion),
          );
          expect(region.selection.selected, {snapshot.last.id});
          final unchanged = cards.evaluate().where(
            (element) =>
                element.widget.key != tester.widget(last).key &&
                identical(previous[element.widget.key], element.widget),
          );
          expect(unchanged, isNotEmpty);
          expect(identical(snapshot, workspace.recycledAgents), isTrue);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
          expect(region.selection.selected, hasLength(count));
          final search = find.byType(SettingSearchField);
          await tester.ensureVisible(search);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField),
            'Recycled agent ${count - 1}',
          );
          await tester.pumpAndSettle();
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.data == 'Recycled agent ${count - 1}',
            ),
            findsOneWidget,
          );
          expect(cards.evaluate(), hasLength(1));
          expect(workspace.recycledAgents, hasLength(count));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
