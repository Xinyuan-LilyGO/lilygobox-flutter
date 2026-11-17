import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/settings/select.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/storage_content.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/settings/presentation/widgets/content_layout.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

Future<void> tick(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final type in ThemeType.values) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('storage memory editor fits ${type.name} at $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(760, 900);
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
        late AiWorkspaceProvider workspaces;
        String? owner;
        await tester.runAsync(() async {
          final font = File('C:/Windows/Fonts/msyh.ttc');
          if (await font.exists()) {
            await (FontLoader('StorageChinese')..addFont(
                  Future.value(ByteData.sublistView(await font.readAsBytes())),
                ))
                .load();
          }
          await (FontLoader(
                'packages/material_symbols_icons/MaterialSymbolsRounded',
              )..addFont(
                rootBundle.load(
                  'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
                ),
              ))
              .load();
          await (FontLoader(
                'packages/material_symbols_icons/MaterialSymbolsOutlined',
              )..addFont(
                rootBundle.load(
                  'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
                ),
              ))
              .load();
          final materialIcons = File(
            'D:/flutter sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          );
          if (await materialIcons.exists()) {
            await (FontLoader('MaterialIcons')..addFont(
                  Future.value(
                    ByteData.sublistView(await materialIcons.readAsBytes()),
                  ),
                ))
                .load();
          }
          if (await font.exists()) {
            await (FontLoader('Ahem')..addFont(
                  Future.value(ByteData.sublistView(await font.readAsBytes())),
                ))
                .load();
            await (FontLoader('Roboto')..addFont(
                  Future.value(ByteData.sublistView(await font.readAsBytes())),
                ))
                .load();
          }
          directory = await Directory.systemTemp.createTemp('storage-ui');
          storage = AgentStorage(path: '${directory.path}/data.sqlite');
          scope = await createAssistantTestScope(
            theme: theme,
            language: language,
            shell: shell,
            splitView: split,
            storage: storage,
          );
          await scope.provider.initialized;
          workspaces = AiWorkspaceProvider(scope.provider);
          await workspaces.initialized;
          {
            await scope.provider.saveService(
              name: 'Local model',
              protocol: AiApiProtocol.openAiChatCompletions,
              baseUrl: 'https://example.test/v1',
              models: ['gpt-6.1-sol'],
              apiKey: 'test-key',
            );
            final agent = await workspaces.create(
              title: 'Example agent',
              task: 'Review local data',
              kind: AiWorkspaceKind.primary,
              startImmediately: false,
            );
            owner = agent.id;
          }
          await storage.putMemory(
            id: 'example',
            owner: owner!,
            content: 'Use filled icons and preserve the complete conversation.',
          );
        });
        final longMemory = List.filled(
          200,
          'Long memory line with complete details.',
        ).join('\n');
        await tester.runAsync(
          () => storage.putMemory(
            id: 'long-example',
            owner: owner!,
            content: longMemory,
          ),
        );
        final palette = MaterialPalette.create(type);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: workspaces,
            child: MaterialApp(
              locale: const Locale('zh'),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: appLocalizationDelegates,
              theme: ThemeData(
                platform: TargetPlatform.windows,
                colorScheme: palette.materialColors,
                fontFamily: 'StorageChinese',
                scrollbarTheme: const ScrollbarThemeData(
                  crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                  mainAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: boundary, child: child!),
              ),
              home: Scaffold(
                backgroundColor: palette.secondary,
                body: AgentStorageContent(theme: palette, owner: owner),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tick(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(SettingSelect<String>), findsNothing);
        // The overview combines chat bodies, attachments and context.
        expect(find.text('聊天记录与上下文'), findsNWidgets(2));
        for (final retired in ['正文与附件', '聊天记录', '上下文缓存', '记忆历史版本']) {
          expect(find.text(retired), findsNothing);
        }
        final cleanupTitle = find.text('清理存储空间');
        final recycleTitle = find.text('回收站').last;
        final backupTitle = find.text('导入与导出');
        expect(cleanupTitle, findsOneWidget);
        expect(find.text('立即清理'), findsOneWidget);
        const cleanupDescription = '立即清理残留文件，释放存储空间。聊天、记忆和回收站内容会保留。';
        final cleanupHint = find.text(cleanupDescription);
        expect(cleanupHint, findsOneWidget);
        Finder panelOf(Finder item) =>
            find.ancestor(of: item, matching: find.byType(SettingsPanel)).first;
        final cleanupPanel = panelOf(cleanupTitle);
        expect(
          tester.element(cleanupPanel),
          same(tester.element(panelOf(recycleTitle))),
        );
        expect(
          tester.element(cleanupPanel),
          isNot(same(tester.element(panelOf(backupTitle)))),
        );
        expect(
          find.descendant(of: cleanupPanel, matching: find.byType(Divider)),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(cleanupTitle).dy,
          lessThan(tester.getTopLeft(recycleTitle).dy),
        );
        expect(
          tester.element(cleanupPanel),
          same(tester.element(find.byType(SettingsPanel).last)),
        );
        final hintWidget = tester.widget<Text>(cleanupHint);
        expect(hintWidget.maxLines, isNull);
        expect(hintWidget.softWrap, isNot(false));
        expect(
          tester.renderObject<RenderParagraph>(cleanupHint).didExceedMaxLines,
          isFalse,
        );
        final panelRect = tester.getRect(cleanupPanel);
        final hintRect = tester.getRect(cleanupHint);
        expect(hintRect.left, greaterThanOrEqualTo(panelRect.left));
        expect(hintRect.right, lessThanOrEqualTo(panelRect.right));
        expect(hintRect.bottom, lessThan(tester.getTopLeft(recycleTitle).dy));
        // The landing view is an overview; detailed controls open on demand.
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('tmp/storage-overview-${type.name}-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        final cleanButton = find.text('立即清理');
        await tester.ensureVisible(cleanButton);
        await tester.tap(cleanButton);
        await tick(tester);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining(
              RegExp(r'^(暂无需要清理的数据。|已清理 \d+ 项残留数据，释放 .+ 空间。|整理完成，释放 .+ 空间。)$'),
            ),
          ),
          findsOneWidget,
        );
        expect(workspaces.find(owner!), isNotNull);
        expect(tester.takeException(), isNull);
        ScaffoldMessenger.of(tester.element(cleanButton)).hideCurrentSnackBar();
        await tick(tester);
        late String recycledId;
        await tester.runAsync(() async {
          final agent = await workspaces.create(
            title: 'Recoverable agent',
            task: 'Retain data',
            kind: AiWorkspaceKind.primary,
            startImmediately: false,
          );
          recycledId = agent.id;
          workspaces.removeMany([agent.id]);
          await workspaces.flush();
        });
        await tick(tester);
        await tester.tap(find.text('管理').last);
        await tick(tester);
        expect(find.text('回收站'), findsWidgets);
        expect(find.textContaining(recycledId), findsOneWidget);
        expect(find.text('还原'), findsOneWidget);
        final recycledCard = tester.widget<AnimatedContainer>(
          find.byKey(ValueKey('recycle-agent-card-$recycledId')),
        );
        expect(
          (recycledCard.decoration as BoxDecoration).color,
          palette.secondary,
        );
        final recycleList = find.byKey(
          const ValueKey('recycle-agent-list-scroll'),
        );
        expect(recycleList, findsOneWidget);
        expect(tester.getSize(recycleList).height, lessThanOrEqualTo(300));
        expect(tester.widget<ListView>(recycleList).primary, isFalse);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('tmp/recycle-bin-${type.name}-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(find.text('还原'));
        await tick(tester);
        expect(workspaces.find(recycledId), isNotNull);
        expect(find.text('回收站为空'), findsOneWidget);
        final emptyRecycleButton = find.byWidgetPredicate(
          (widget) => widget is AppActionButton && widget.label == '清空回收站',
        );
        expect(
          tester.widget<AppActionButton>(emptyRecycleButton).onPressed,
          isNull,
        );
        expect(
          tester.widget<Text>(find.text('清空回收站')).style!.color,
          isNot(palette.materialColors.onError),
        );
        expect(
          tester.getSize(find.byType(ListView).last).width,
          lessThanOrEqualTo(440),
        );
        await tester.tap(find.text('关闭'));
        await tick(tester);
        await tester.runAsync(() async {
          workspaces.removeMany([recycledId]);
          await storage.putMemory(
            id: 'orphan-memory',
            owner: 'orphan-archive-id',
            content: 'Archived memory must not be editable here.',
          );
          await workspaces.flush();
        });
        await tester.tap(find.text('管理').first);
        await tick(tester);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(SettingSelect<String>), findsOneWidget);
        // Dialog controls leave a gutter; only one scrollbar owns this viewport.
        final managerScroll = find.byKey(
          const ValueKey('storage-manager-scroll'),
        );
        final viewport = tester.getRect(managerScroll);
        expect(viewport.width, lessThanOrEqualTo(440));
        final memoryList = find.byKey(
          const ValueKey('storage-memory-list-scroll'),
        );
        expect(memoryList, findsOneWidget);
        expect(tester.getSize(memoryList).height, lessThanOrEqualTo(240));
        expect(tester.widget<ListView>(memoryList).primary, isFalse);

        final editableOwners = tester
            .widget<SettingSelect<String>>(find.byType(SettingSelect<String>))
            .items
            .map((item) => item.value);
        expect(editableOwners, isNot(contains(recycledId)));
        expect(editableOwners, isNot(contains('orphan-archive-id')));
        final ownerField = tester.getRect(find.byType(SettingSelect<String>));
        expect(ownerField.left - viewport.left, closeTo(24, .01));
        expect(viewport.right - ownerField.right, closeTo(24, .01));
        expect(
          find.ancestor(
            of: find.byType(SettingSelect<String>),
            matching: find.byType(Scrollbar),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byType(SettingSelect<String>));
        await tick(tester);
        expect(find.text('共享记忆（所有智能体）'), findsNothing);
        await tester.tap(find.textContaining('Example agent').last);
        await tick(tester);
        if (owner != null) {
          await tester.tap(find.byType(SettingSelect<String>));
          await tick(tester);
          await tester.tap(find.textContaining('Example agent').last);
          await tick(tester);
          expect(find.byType(SettingSelect<int>), findsNothing);
        }
        tester.view.physicalSize = const Size(420, 620);
        await tick(tester);
        final longPreview = find.text(longMemory);
        await tester.ensureVisible(longPreview);
        await tick(tester);
        expect(tester.widget<Text>(longPreview).maxLines, 2);
        await tester.tap(
          find.descendant(
            of: find.ancestor(of: longPreview, matching: find.byType(ListTile)),
            matching: find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '编辑',
            ),
          ),
        );
        await tick(tester);
        expect(find.byType(Dialog), findsNWidgets(2));
        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .controller!
              .text,
          longMemory,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tick(tester);
        expect(find.byType(Dialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(760, 900);
        await tick(tester);
        final searchField = find.byType(TextField).first;
        await tester.ensureVisible(searchField);
        await tester.enterText(searchField, 'zzzxqv987654321');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tick(tester);
        expect(find.text('暂无已保存的记忆。'), findsOneWidget);
        final addMemoryButton = find.byWidgetPredicate(
          (widget) => widget is AppActionButton && widget.label == '添加记忆',
        );
        final searchRect = tester.getRect(searchField);
        final addRect = tester.getRect(addMemoryButton);
        expect(addRect.left, greaterThanOrEqualTo(searchRect.right));
        expect(addRect.center.dy, closeTo(searchRect.center.dy, .01));

        final compactMemorySwitch = find.ancestor(
          of: find.byKey(const ValueKey('storage-use-memory-switch')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SizedBox && widget.width == 44 && widget.height == 28,
          ),
        );
        expect(compactMemorySwitch, findsOneWidget);
        await tester.ensureVisible(compactMemorySwitch);
        await tick(tester);
        final switchRect = tester.getRect(compactMemorySwitch);
        final switchTitleRect = tester.getRect(find.text('自动使用长期记忆'));
        expect(switchRect.size, const Size(44, 28));
        expect(switchRect.left, greaterThan(switchTitleRect.right));
        expect(switchRect.center.dy, closeTo(switchTitleRect.center.dy, .01));
        final automaticMemory = find.byKey(
          const ValueKey('storage-auto-memory-switch'),
        );
        expect(tester.widget<Switch>(automaticMemory).value, isTrue);
        await tester.ensureVisible(automaticMemory);
        await tester.tap(automaticMemory);
        await tick(tester);
        expect(workspaces.find(owner!)!.assistant.autoSaveMemory, isFalse);
        expect(
          workspaces
              .find(owner!)!
              .assistant
              .snapshotWorkspaceConversation()['autoSaveMemory'],
          isFalse,
        );
        final useMemory = find.byKey(
          const ValueKey('storage-use-memory-switch'),
        );
        await tester.ensureVisible(useMemory);
        await tester.tap(useMemory);
        await tick(tester);
        expect(tester.widget<Switch>(automaticMemory).onChanged, isNull);
        await tester.tap(useMemory);
        await tick(tester);
        expect(tester.widget<Switch>(automaticMemory).onChanged, isNotNull);

        await tester.ensureVisible(searchField);
        await tester.enterText(searchField, '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tick(tester);
        final memory = find.text(
          'Use filled icons and preserve the complete conversation.',
        );
        await tester.ensureVisible(memory);
        await tick(tester);
        {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('tmp/storage-${type.name}-$scale.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(
          find.descendant(
            of: find.ancestor(of: memory, matching: find.byType(ListTile)),
            matching: find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '编辑',
            ),
          ),
        );
        await tick(tester);
        expect(find.byType(Dialog), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byType(TextField).last,
          'Updated durable preference.',
        );
        await tester.tap(find.text('保存'));
        await tick(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tick(tester);
        expect(find.text('Updated durable preference.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('关闭'));
        await tick(tester);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(SettingSelect<String>), findsNothing);
        expect(find.text('Updated durable preference.'), findsNothing);
        await tester.tap(find.text('管理').at(1));
        await tick(tester);
        expect(find.text('当前上下文'), findsOneWidget);
        final compactButton = find.text('立即压缩');
        await tester.ensureVisible(compactButton);
        await tester.tap(compactButton);
        await tick(tester);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining(
              RegExp(r'^(当前聊天记录较少，暂无需要压缩的上下文。|请先配置可用的模型服务后再压缩。)$'),
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        ScaffoldMessenger.of(tester.element(compactButton))
            .hideCurrentSnackBar();
        await tick(tester);
        expect(find.byType(SettingSelect<int>), findsNothing);
        final contextBudget = find.descendant(
          of: find.byKey(const ValueKey('storage-context-budget')),
          matching: find.byType(TextField),
        );
        expect(contextBudget, findsOneWidget);
        await tester.ensureVisible(contextBudget);
        await tester.enterText(contextBudget, '45000');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tick(tester);
        expect(workspaces.find(owner!)!.assistant.contextBudgetTokens, 45000);
        expect(find.text('请输入大于 0 的整数。'), findsNothing);
        expect(tester.takeException(), isNull);
        final contextPercent = find.descendant(
          of: find.byKey(const ValueKey('storage-context-percent')),
          matching: find.byType(TextField),
        );
        expect(contextPercent, findsOneWidget);
        expect(tester.widget<TextField>(contextPercent).controller!.text, '90');
        await tester.ensureVisible(contextPercent);
        await tester.enterText(contextPercent, '75');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tick(tester);
        expect(workspaces.find(owner!)!.assistant.contextCompactionPercent, 75);
        expect(
          workspaces.find(owner!)!.assistant.contextCompactionThresholdTokens,
          33750,
        );
        for (final invalidPercent in ['101', '0']) {
          await tester.enterText(contextPercent, invalidPercent);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tick(tester);
          expect(find.text('百分比请输入 1–100 的整数。'), findsOneWidget);
          expect(
            workspaces.find(owner!)!.assistant.contextCompactionPercent,
            75,
          );
          expect(
            workspaces.find(owner!)!.assistant.contextCompactionThresholdTokens,
            33750,
          );
        }
        await tester.enterText(contextPercent, '99');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tick(tester);
        expect(workspaces.find(owner!)!.assistant.contextCompactionPercent, 99);
        expect(find.text('百分比请输入 1–100 的整数。'), findsNothing);
        expect(
          find.text('百分比过高可能没有足够余量处理新消息、工具和回复；不建议等到窗口填满才压缩。'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('tmp/storage-context-${type.name}-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.enterText(contextBudget, '0');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tick(tester);
        expect(find.text('请输入大于 0 的整数。'), findsOneWidget);
        expect(workspaces.find(owner!)!.assistant.contextBudgetTokens, 45000);
        expect(tester.takeException(), isNull);
        // Leaving the field saves a valid custom value without pressing Enter.
        await tester.enterText(contextBudget, '45001');
        FocusManager.instance.primaryFocus?.unfocus();
        await tick(tester);
        expect(workspaces.find(owner!)!.assistant.contextBudgetTokens, 45001);
        expect(find.text('请输入大于 0 的整数。'), findsNothing);
        await tester.tap(find.text('关闭'));
        await tick(tester);
        expect(find.byType(Dialog), findsNothing);
        await tester.tap(find.text('管理').at(2));
        await tick(tester);
        expect(find.byType(Dialog), findsOneWidget);
        final targetPicker = find.byKey(
          const ValueKey('storage-export-target'),
        );
        expect(
          find.byKey(const ValueKey('storage-package-type')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('storage-owner-select')),
          findsNothing,
        );
        expect(
          tester
              .widget<SettingSelect<String>>(targetPicker)
              .items
              .map((item) => item.value),
          ['agent', 'workflow'],
        );
        expect(
          tester.widget<SettingSelect<String>>(targetPicker).value,
          'workflow',
        );
        await tester.tap(targetPicker);
        await tick(tester);
        expect(find.text('请选择导出对象'), findsNothing);
        await tester.tap(find.text('智能体工作流').last);
        await tick(tester);
        expect(
          find.byKey(const ValueKey('storage-package-type')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('storage-owner-select')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('storage-include-archived')),
          findsNothing,
        );
        await tester.tap(targetPicker);
        await tick(tester);
        await tester.tap(find.text('智能体').last);
        await tick(tester);
        final packagePicker = find.byKey(
          const ValueKey('storage-package-type'),
        );
        final packageSelect = tester.widget<SettingSelect<String>>(
          packagePicker,
        );
        expect(packageSelect.items.map((item) => item.value), [
          'agent',
          'chat',
          'memory',
        ]);
        expect(
          find.byKey(const ValueKey('storage-owner-select')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('storage-include-archived')),
          findsNothing,
        );
        final includeChildren = find.byKey(
          const ValueKey('storage-include-children'),
        );
        final ownerPicker = find.byKey(const ValueKey('storage-owner-select'));
        Future<void> chooseOwner(String title) async {
          await tester.ensureVisible(ownerPicker);
          await tester.tap(ownerPicker);
          await tick(tester);
          await tester.tap(find.textContaining(' · $title').last);
          await tick(tester);
        }

        Future<void> choosePackage(String label) async {
          await tester.ensureVisible(packagePicker);
          await tester.tap(packagePicker);
          await tick(tester);
          await tester.tap(find.text(label).last);
          await tick(tester);
        }

        Finder includeCheckbox() => find.descendant(
          of: includeChildren,
          matching: find.byType(Checkbox),
        );
        await chooseOwner('Example agent');
        expect(includeChildren, findsNothing);
        late String leafId;
        late String recycledChildId;
        await tester.runAsync(() async {
          await workspaces.create(
            title: 'Active export child',
            task: 'Retain branch data',
            parentId: owner!,
            startImmediately: false,
          );
          final leaf = await workspaces.create(
            title: 'Leaf export agent',
            task: 'Export only this agent',
            kind: AiWorkspaceKind.primary,
            startImmediately: false,
          );
          leafId = leaf.id;
          final recycledChild = await workspaces.create(
            title: 'Recycled export child',
            task: 'Exclude recycled descendants',
            parentId: leafId,
            startImmediately: false,
          );
          recycledChildId = recycledChild.id;
          workspaces.removeMany([recycledChildId]);
          await workspaces.flush();
        });
        await tick(tester);
        expect(includeChildren, findsOneWidget);
        expect(tester.widget<Checkbox>(includeCheckbox()).value, isFalse);
        await tester.ensureVisible(includeCheckbox());
        await tester.tap(includeCheckbox());
        await tick(tester);
        expect(tester.widget<Checkbox>(includeCheckbox()).value, isTrue);
        await chooseOwner('Leaf export agent');
        expect(workspaces.find(recycledChildId), isNull);
        expect(workspaces.childrenOf(leafId), isEmpty);
        expect(includeChildren, findsNothing);
        await chooseOwner('Example agent');
        expect(includeChildren, findsOneWidget);
        expect(tester.widget<Checkbox>(includeCheckbox()).value, isFalse);
        await tester.ensureVisible(includeCheckbox());
        await tester.tap(includeCheckbox());
        await tick(tester);
        expect(tester.widget<Checkbox>(includeCheckbox()).value, isTrue);
        await choosePackage('聊天记录与上下文包');
        expect(includeChildren, findsNothing);
        await choosePackage('完整数据包');
        expect(includeChildren, findsOneWidget);
        expect(tester.widget<Checkbox>(includeCheckbox()).value, isFalse);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('tmp/storage-transfer-${type.name}-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(packagePicker);
        await tick(tester);
        for (final label in ['长期记忆包', '聊天记录与上下文包', '完整数据包']) {
          expect(find.text(label), findsWidgets);
        }
        await tester.tap(find.text('聊天记录与上下文包').last);
        await tick(tester);
        final ownerSelect = tester.widget<SettingSelect<String>>(
          find.byKey(const ValueKey('storage-owner-select')),
        );
        expect(
          ownerSelect.items.any((item) => item.value == 'global'),
          isFalse,
        );
        const selectorChannel = MethodChannel(
          'plugins.flutter.io/file_selector',
        );
        final openResult = Completer<Object?>();
        final saveResult = Completer<Object?>();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          selectorChannel,
          (call) => switch (call.method) {
            'openFile' => openResult.future,
            'getSavePath' => saveResult.future,
            _ => throw UnsupportedError(call.method),
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            selectorChannel,
            null,
          ),
        );
        final transferAction = find.byKey(
          const ValueKey('storage-transfer-action'),
        );
        void expectPickerPreservesButtons() {
          expect(
            tester.widget<AppActionButton>(transferAction).onPressed,
            isNotNull,
          );
          for (final label in ['导入数据', '导出数据']) {
            final tab = find
                .byWidgetPredicate(
                  (widget) =>
                      widget is AppActionButton && widget.label == label,
                )
                .first;
            expect(tester.widget<AppActionButton>(tab).onPressed, isNotNull);
          }
          expect(
            find.byKey(const ValueKey('storage-transfer-progress-dialog')),
            findsNothing,
          );
        }

        await tester.tap(transferAction);
        await tick(tester);
        expectPickerPreservesButtons();
        saveResult.complete(null);
        await tick(tester);
        await tester.tap(find.text('导入数据'));
        await tick(tester);
        expect(packagePicker, findsNothing);
        expect(find.text('导入数据包'), findsNothing);
        expect(find.text('导入数据'), findsOneWidget);
        expect(find.byType(SettingSelect<String>), findsNothing);
        expect(
          find.byKey(const ValueKey('storage-import-target')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('storage-owner-select')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('storage-import-file')), findsNothing);
        expect(find.text('选择数据包'), findsWidgets);
        await tester.tap(transferAction);
        await tick(tester);
        expectPickerPreservesButtons();
        expect(
          tester
              .widget<AppActionButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is AppActionButton && widget.label == '导入数据',
                ),
              )
              .primary,
          isTrue,
        );
        openResult.complete(null);
        await tick(tester);

        expect(tester.takeException(), isNull);
        await tester.tap(find.text('关闭'));
        await tick(tester);
        expect(find.byType(Dialog), findsNothing);
        await tester.runAsync(() async {
          workspaces.removeMany(
            workspaces.sessions.map((agent) => agent.id).toList(),
          );
          await workspaces.flush();
        });
        await tick(tester);
        await tester.tap(find.text('管理').first);
        await tick(tester);
        final addMemory = find.byWidgetPredicate(
          (widget) => widget is AppActionButton && widget.label == '添加记忆',
        );
        expect(tester.widget<AppActionButton>(addMemory).onPressed, isNull);
        expect(
          tester
              .widget<SettingSelect<String>>(find.byType(SettingSelect<String>))
              .items
              .map((item) => item.value),
          [''],
        );
        final emptyManager = tester.getSize(
          find.byKey(const ValueKey('storage-manager-scroll')),
        );
        expect(emptyManager.width, lessThanOrEqualTo(440));
        expect(emptyManager.height, lessThan(400));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('关闭'));
        await tick(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await workspaces.flush();
          workspaces.dispose();
          scope.dispose();
          await storage.close();
          await directory.delete(recursive: true);
        });
        theme.dispose();
        language.dispose();
        shell.dispose();
        split.dispose();
      });
    }
  }
}
