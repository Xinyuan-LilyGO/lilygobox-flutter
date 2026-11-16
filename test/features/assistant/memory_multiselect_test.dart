import 'dart:io';

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
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/storage_content.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

Future<void> settleStorage(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('memory cards select ranges and confirm one bulk deletion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final split = SplitViewProvider();
    late Directory directory;
    late AgentStorage storage;
    late AssistantTestScope scope;
    late AiWorkspaceProvider workspace;
    late String owner;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('memory-multiselect-');
      storage = AgentStorage(path: '${directory.path}/data.sqlite');
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
      final agent = await workspace.create(
        title: 'Memories',
        task: 'Remember facts',
        kind: AiWorkspaceKind.primary,
        startImmediately: false,
      );
      owner = agent.id;
      for (var i = 0; i < 3; i++) {
        await workspace.main.storage!.putMemory(
          id: 'memory-$i',
          owner: owner,
          content: 'Fact $i',
        );
      }
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        await workspace.flush();
        workspace.dispose();
        scope.dispose();
        await storage.close();
        await directory.delete(recursive: true);
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
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: appLocalizationDelegates,
          scrollBehavior: const AppScrollBehavior(),
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
    await tester.tap(find.text('Open memories'));
    await settleStorage(tester);
    final ownerSelect = find.byKey(const ValueKey('storage-owner-select'));
    final useMemory = find.byKey(const ValueKey('storage-use-memory-switch'));
    final automaticMemory = find.byKey(
      const ValueKey('storage-auto-memory-switch'),
    );
    final search = find.byKey(const ValueKey('storage-memory-search'));
    expect(
      tester.getTopLeft(useMemory).dy,
      greaterThan(tester.getBottomLeft(ownerSelect).dy),
    );
    expect(
      tester.getTopLeft(automaticMemory).dy,
      greaterThan(tester.getBottomLeft(useMemory).dy),
    );
    expect(
      tester.getTopLeft(search).dy,
      greaterThan(tester.getBottomLeft(automaticMemory).dy),
    );
    expect(find.textContaining('apply only to that agent.'), findsOneWidget);
    final list = find.byKey(const ValueKey('storage-memory-list-scroll'));
    final cards = find.descendant(of: list, matching: find.byType(ListTile));
    expect(cards, findsNWidgets(3));
    Future<void> tapCard(int index) async {
      await tester.ensureVisible(cards.at(index));
      await tester.tap(cards.at(index));
      await tester.pump();
    }

    int selectedCount() => tester
        .widgetList<ListTile>(cards)
        .where((card) => card.selected)
        .length;
    await tapCard(0);
    expect(selectedCount(), 1);
    await tester.tap(find.byKey(const ValueKey('storage-memory-search')));
    await tester.pump();
    expect(
      selectedCount(),
      1,
      reason: 'focusing search preserves card selection',
    );
    Material cardSurface(int index) => tester.widget<Material>(
      find.ancestor(of: cards.at(index), matching: find.byType(Material)).first,
    );
    final firstSize = tester.getSize(cards.at(0));
    final selectedShape = cardSurface(0).shape! as RoundedRectangleBorder;
    expect(selectedShape.side.color, theme.themeData.basePrimary);
    expect(selectedShape.side.width, 1);
    expect(
      (cardSurface(1).shape! as RoundedRectangleBorder).side.color,
      Colors.transparent,
    );
    // The gap above the list is outside selectable cards and actions.
    await tester.tapAt(tester.getTopLeft(list) + const Offset(3, -4));
    await tester.pump();
    expect(selectedCount(), 0);
    expect(tester.getSize(cards.at(0)), firstSize);
    await tapCard(0);
    expect(find.byType(AppDialog), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tapCard(1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(selectedCount(), 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tapCard(2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(selectedCount(), 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(selectedCount(), 3);
    final searchInput = find.descendant(
      of: find.byKey(const ValueKey('storage-memory-search')),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchInput, '0');
    await tester.pump();
    expect(selectedCount(), 3);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settleStorage(tester);
    expect(cards, findsOneWidget);
    expect(find.text('Delete selected (3)'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await settleStorage(tester);
    expect(selectedCount(), 3);
    await tester.tap(cards.first);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    final confirmation = find.byKey(
      const ValueKey('confirm-delete-selected-memory'),
    );
    expect(tester.widget<AppActionButton>(confirmation).destructive, isTrue);
    await tester.tap(
      find.byKey(const ValueKey('cancel-delete-selected-memory')),
    );
    await tester.pumpAndSettle();
    expect(cards, findsNWidgets(3));
    await tester.tap(
      find.byKey(const ValueKey('storage-memory-delete-selected')),
    );
    await tester.pumpAndSettle();
    await tester.tap(confirmation);
    await settleStorage(tester);
    expect(find.byType(ListTile), findsNothing);
    final remaining = await tester.runAsync(
      () => workspace.main.storage!.memories(owner),
    );
    expect(remaining, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

