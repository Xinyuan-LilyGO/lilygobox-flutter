import 'dart:async';

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
import 'package:lilygobox/core/widgets/confirmation_dialog.dart';
import 'package:lilygobox/core/widgets/desktop_card_selection.dart';
import 'package:lilygobox/core/widgets/settings/search_field.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/recycle_bin_dialog.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

class _GatedStorage extends AgentStorage {
  _GatedStorage() : super(path: ':memory:');

  Completer<void>? deletion;

  @override
  Future<Object?> request(String operation, [Map<String, Object?> args = const {}]) async {
    if (operation == 'commitRecycle') await deletion?.future;
    return super.request(operation, args);
  }
}

void main() {
  for (final compact in [false, true]) {
    testWidgets(
      compact
          ? 'small recycle dialog supports batch selection at 1.5 text scale'
          : 'many recycled cards scroll without moving search or close',
      (tester) async {
        tester.view.physicalSize = compact
            ? const Size(420, 620)
            : const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final theme = ThemeProvider();
        final language = LanguageProvider();
        final shell = AppShellProvider();
        final split = SplitViewProvider();
        final storage = _GatedStorage();
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
          await scope.provider.saveService(
            name: 'Test service',
            protocol: AiApiProtocol.openAiChatCompletions,
            baseUrl: 'https://example.test/v1',
            models: ['test-model'],
            apiKey: 'test-key',
          );
          workspace = AiWorkspaceProvider(scope.provider);
          await workspace.initialized;
          final ids = <String>[];
          for (var i = 0; i < 12; i++) {
            final agent = await workspace.create(
              title: 'Recycled agent $i',
              task: 'A retained conversation',
              kind: AiWorkspaceKind.primary,
              startImmediately: false,
            );
            ids.add(agent.id);
          }
          workspace.removeMany(ids);
          await workspace.flush();
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(compact ? 1.5 : 1)),
                child: child!,
              ),
              locale: const Locale('en'),
              supportedLocales: const [Locale('en'), Locale('zh')],
              localizationsDelegates: appLocalizationDelegates,
              scrollBehavior: const AppScrollBehavior(),
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
        final list = find.byKey(
          ValueKey(
            compact
                ? 'recycle-agent-compact-scroll'
                : 'recycle-agent-list-scroll',
          ),
        );
        final search = find.byType(SettingSearchField);
        final close = find.text('Close');
        final dialogSurface = find
            .descendant(
              of: find.byType(AppDialog),
              matching: find.byType(Material),
            )
            .first;
        final dialogSize = tester.getSize(dialogSurface);
        final searchRect = tester.getRect(search);
        final closeRect = tester.getRect(close);
        final listSize = tester.getSize(list);
        if (!compact) expect(listSize.height, closeTo(270, .01));
        expect(dialogSize.height, lessThan(compact ? 620 : 800));
        if (!compact) expect(tester.widget<ScrollView>(list).primary, isFalse);
        expect(
          find.descendant(
            of: find.byType(AppDialog),
            matching: find.byType(Scrollbar),
          ),
          findsOneWidget,
        );

        final last = workspace.recycledAgents.last;
        final lastCard = find.byKey(ValueKey('recycle-agent-card-${last.id}'));
        final scrollable = find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first;
        await tester.scrollUntilVisible(lastCard, 220, scrollable: scrollable);
        await tester.pumpAndSettle();
        expect(lastCard.hitTestable(), findsOneWidget);
        expect(tester.getSize(list), listSize);
        expect(tester.getSize(dialogSurface), dialogSize);
        if (!compact) expect(tester.getRect(search), searchRect);
        expect(tester.getRect(close), closeRect);
        expect(tester.takeException(), isNull);
        final ordered = workspace.recycledAgents.toList();
        final bin = tester.element(find.byType(AppDialog));
        final region = tester.widget<DesktopCardSelectionRegion>(
          find.byType(DesktopCardSelectionRegion),
        );
        Future<void> tapCard(int index) async {
          final title = find.text(ordered[index].title);
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(title, 120, scrollable: scrollable);
          await tester.pumpAndSettle();
          await tester.tap(title);
          await tester.pumpAndSettle();
        }

        await tapCard(0);
        expect(
          tester.takeException(),
          isNull,
          reason: 'batch actions fit in a small scaled dialog',
        );
        expect(region.selection.selected, {ordered[0].id});
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        await tester.tap(search);
        await tester.pump();
        expect(region.selection.selected, {
          ordered[0].id,
        }, reason: 'focusing search preserves card selection');
        expect(tester.getSize(dialogSurface).width, dialogSize.width);
        final restoreRect = tester.getRect(
          find.byKey(const ValueKey('recycle-restore-selected')),
        );
        final deleteRect = tester.getRect(
          find.byKey(const ValueKey('recycle-delete-selected')),
        );
        expect(
          restoreRect.center.dy,
          closeTo(tester.getRect(search).center.dy, 1),
        );
        expect(deleteRect.center.dy, closeTo(restoreRect.center.dy, 1));
        expect(restoreRect.left, greaterThan(tester.getRect(search).right));

        final firstCard = find.byKey(
          ValueKey('recycle-agent-card-${ordered[0].id}'),
        );
        BoxBorder? cardBorder() =>
            (tester.widget<AnimatedContainer>(firstCard).decoration
                    as BoxDecoration)
                .border;
        expect(
          cardBorder(),
          Border.all(color: theme.themeData.basePrimary, width: 1),
        );
        await tester.tap(find.text('Recycle bin').first);
        await tester.pumpAndSettle();
        expect(region.selection.selected, isEmpty);
        expect(cardBorder(), Border.all(color: Colors.transparent, width: 1));
        await tester.ensureVisible(firstCard);
        await tester.pumpAndSettle();
        final firstCardRect = tester.getRect(firstCard);
        final listRect = tester.getRect(list);
        expect(firstCardRect.left, closeTo(searchRect.left, .01));
        expect(firstCardRect.right, closeTo(searchRect.right, .01));
        expect(listRect.right - firstCardRect.right, closeTo(24, .01));
        await tester.tap(firstCard, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        expect(region.selection.selected, isEmpty);
        await tester.tap(find.text('Select all'));
        await tester.pumpAndSettle();
        expect(
          region.selection.selected,
          ordered.map((entry) => entry.id).toSet(),
        );
        await tester.tap(firstCard, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Deselect'));
        await tester.pumpAndSettle();
        expect(
          region.selection.selected,
          ordered.skip(1).map((entry) => entry.id).toSet(),
        );
        await tapCard(0);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tapCard(2);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(region.selection.selected, {
          ordered[0].id,
          ordered[1].id,
          ordered[2].id,
        });
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tapCard(1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(region.selection.selected, {ordered[0].id, ordered[2].id});
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();
        final confirmation = find.byKey(
          const ValueKey('confirm-recycle-delete'),
        );
        expect(confirmation, findsOneWidget);
        expect(
          tester.widget<AppActionButton>(confirmation).destructive,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('cancel-recycle-delete')));
        await tester.pumpAndSettle();
        expect(workspace.recycledAgents, hasLength(12));
        expect(region.selection.selected, {ordered[0].id, ordered[2].id});
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(region.selection.selected, isEmpty);

        await tapCard(0);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(region.selection.selected, hasLength(12));
        if (compact) {
          await tester.ensureVisible(search);
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextField), 'Recycled agent');
        await tester.pumpAndSettle();
        expect(region.selection.selected, hasLength(12));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(region.selection.selected, hasLength(12));
        expect(workspace.recycledAgents, hasLength(12));
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(
          region.selection.selected,
          hasLength(12),
          reason: 'clearing search with its button preserves selection',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );

        await tapCard(0);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tapCard(1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(region.selection.selected, {ordered[0].id, ordered[1].id});
        if (compact) {
          await tester.ensureVisible(
            find.byKey(const ValueKey('recycle-restore-selected')),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(const ValueKey('recycle-restore-selected')),
        );
        Future<void> settleRecycleCount(int count) async {
          for (var attempt = 0; attempt < 100; attempt++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
            if (workspace.recycledAgents.length == count &&
                !workspace.recycleBusy) {
              return;
            }
          }
        }

        await settleRecycleCount(10);
        await tester.pumpAndSettle();
        expect(
          workspace.recycleBusy,
          isFalse,
          reason: 'batch restore finished its storage write',
        );
        expect(workspace.recycledAgents, hasLength(10));
        expect(workspace.find(ordered[0].id), isNotNull);
        expect(workspace.find(ordered[1].id), isNotNull);
        expect(tester.element(find.byType(AppDialog)), same(bin));
        expect(region.selection.selected, isEmpty);
        await tapCard(2);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tapCard(3);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        if (compact) {
          await tester.ensureVisible(
            find.byKey(const ValueKey('recycle-delete-selected')),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('recycle-delete-selected')));
        await tester.pumpAndSettle();
        expect(region.selection.selected, {ordered[2].id, ordered[3].id});
        await tester.tap(find.byKey(const ValueKey('confirm-recycle-delete')));
        await settleRecycleCount(8);
        await tester.pumpAndSettle();
        expect(workspace.recycledAgents, hasLength(8));
        expect(
          workspace.recycledAgents.any(
            (entry) => entry.id == ordered[2].id || entry.id == ordered[3].id,
          ),
          isFalse,
        );
        expect(region.selection.selected, isEmpty);
        await tester.ensureVisible(search);
        await tester.enterText(find.byType(TextField), 'No results for this');
        await tester.pumpAndSettle();
        final restoreAll = find.byKey(const ValueKey('recycle-restore-all'));
        final emptyAll = find.byKey(const ValueKey('recycle-empty-all'));
        await tester.ensureVisible(restoreAll);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(restoreAll).right,
          lessThan(tester.getRect(emptyAll).left),
        );
        expect(find.text('Restore all'), findsOneWidget);
        expect(find.text('Empty all'), findsOneWidget);
        await tester.tap(emptyAll);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('confirm-recycle-empty')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('cancel-recycle-empty')));
        await tester.pumpAndSettle();
        expect(workspace.recycledAgents, hasLength(8));
        await tester.ensureVisible(restoreAll);
        await tester.pumpAndSettle();
        await tester.tap(restoreAll);
        await tester.pumpAndSettle();
        expect(
          find.text('Restore all 8 agents in the recycle bin?'),
          findsOneWidget,
        );
        expect(workspace.recycledAgents, hasLength(8));
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('recycle-restore-dialog')),
          findsNothing,
        );
        expect(workspace.recycledAgents, hasLength(8));
        await tester.ensureVisible(restoreAll);
        await tester.pumpAndSettle();
        await tester.tap(restoreAll);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-recycle-restore')));
        await tester.pump();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('recycle-restore-dialog')),
            matching: find.byType(LinearProgressIndicator),
          ),
          findsOneWidget,
        );
        await settleRecycleCount(0);
        await tester.pumpAndSettle();
        expect(workspace.recycledAgents, isEmpty);
        expect(workspace.sessions, hasLength(10));
        expect(tester.element(find.byType(AppDialog)), same(bin));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'No results for this',
        );
        expect(tester.widget<AppActionButton>(restoreAll).onPressed, isNull);
        expect(tester.widget<AppActionButton>(emptyAll).onPressed, isNull);
        expect(tester.takeException(), isNull);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
        workspace.removeMany(workspace.sessions.map((session) => session.id));
        await tester.tap(find.text('Open bin'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(emptyAll);
        await tester.tap(emptyAll);
        await tester.pumpAndSettle();
        storage.deletion = Completer<void>();
        try {
          await tester.tap(find.byKey(const ValueKey('confirm-recycle-empty')));
          await tester.pumpAndSettle();
          for (var attempt = 0; attempt < 50 && !workspace.recycleBusy; attempt++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
            await tester.pump();
          }
          expect(workspace.recycleBusy, isTrue);
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(find.byType(AppDialog), findsNothing);
          expect(workspace.recycledAgents, hasLength(10));
        } finally {
          storage.deletion!.complete();
        }
        await settleRecycleCount(0);
        expect(workspace.recycledAgents, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
