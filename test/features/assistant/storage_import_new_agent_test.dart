import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/core/widgets/settings/select.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/storage_content.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/state/storage_controller.dart';
import 'package:lilygobox/features/settings/presentation/widgets/content_layout.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';
import 'storage_content_test.dart' show tick;

void main() {
  for (final empty in [false, true]) {
    testWidgets(
      'memory destination is independent and can create an agent with empty=$empty',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1000);
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
        late String path;
        await tester.runAsync(() async {
          directory = await Directory.systemTemp.createTemp(
            'storage-import-ui',
          );
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
          await scope.provider.saveService(
            name: 'Local model',
            protocol: AiApiProtocol.openAiChatCompletions,
            baseUrl: 'https://example.test/v1',
            models: ['gpt-6.1-sol'],
            apiKey: 'test-key',
          );
          final source = await workspaces.create(
            title: 'Imported conversation',
            task: 'Keep this conversation',
            kind: AiWorkspaceKind.primary,
            startImmediately: false,
          );
          final controller = AgentStorageController(workspaces)
            ..owner = source.id;
          await storage.putMemory(
            id: 'source-memory',
            owner: source.id,
            content: 'Keep this imported preference',
          );
          path = '${directory.path}/memory.tar.zst';
          await controller.export(path, 'memory');
          if (empty) {
            workspaces.removeMany([source.id]);
            await workspaces.flush();
          }
          controller.dispose();
        });
        const channel = MethodChannel('plugins.flutter.io/file_selector');
        var pickerCalls = 0;
        var cancelled = true;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            expect(call.method, 'openFile');
            pickerCalls++;
            return cancelled ? null : [path];
          },
        );
        addTearDown(() async {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
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
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: workspaces,
            child: MaterialApp(
              locale: const Locale('zh'),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: appLocalizationDelegates,
              home: Scaffold(body: AgentStorageContent(theme: theme.themeData)),
            ),
          ),
        );
        await tick(tester);
        final panel = find.ancestor(
          of: find.text('导入与导出'),
          matching: find.byType(SettingsPanel),
        );
        final manage = find.descendant(of: panel, matching: find.text('管理'));
        await tester.ensureVisible(manage);
        await tester.tap(manage);
        await tick(tester);
        await tester.tap(find.text('导入数据'));
        await tick(tester);
        final action = find.byKey(const ValueKey('storage-transfer-action'));
        final before = workspaces.sessions.length;
        await tester.tap(action);
        await tick(tester);
        expect(pickerCalls, 1);
        expect(workspaces.sessions.length, before);
        expect(tester.widget<AppActionButton>(action).onPressed, isNotNull);
        cancelled = false;
        final destination = find.byKey(
          const ValueKey('storage-memory-import-destination'),
        );
        final target = find.byKey(
          const ValueKey('storage-memory-import-target'),
        );
        Future<void> openDestination() async {
          await tester.tap(action);
          for (var attempt = 0; attempt < 12; attempt++) {
            await tick(tester);
            if (destination.evaluate().isNotEmpty) break;
          }
          expect(destination, findsOneWidget);
        }

        await openDestination();
        expect(
          find.descendant(
            of: destination,
            matching: find.byType(SettingSelect<String>),
          ),
          findsOneWidget,
        );
        expect(workspaces.sessions.length, before);
        await tester.tap(
          find.byKey(const ValueKey('storage-memory-import-target-cancel')),
        );
        await tick(tester);
        expect(destination, findsNothing);
        expect(workspaces.sessions.length, before);

        if (!empty) {
          await openDestination();
          final existingId = workspaces.sessions.single.id;
          expect(
            tester.widget<SettingSelect<String>>(target).value,
            existingId,
          );
          await tester.tap(
            find.byKey(const ValueKey('storage-memory-import-target-confirm')),
          );
          await tick(tester);
          await tester.tap(find.byKey(const ValueKey('memory-review-import')));
          await tick(tester);
          expect(workspaces.sessions.length, before);
          await tester.runAsync(() async {
            expect(await storage.memories(existingId), hasLength(1));
          });
        }

        Future<void> chooseNewTarget() async {
          await openDestination();
          await tester.tap(target);
          await tester.pumpAndSettle();
          await tester.tap(find.text('新建智能体').last);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('storage-memory-import-target-confirm')),
          );
          await tick(tester);
          expect(destination, findsNothing);
          expect(
            find.byKey(const ValueKey('memory-review-list')),
            findsNothing,
          );
        }

        await chooseNewTarget();
        for (var i = 0; i < 12 && workspaces.sessions.length == before; i++) {
          await tick(tester);
        }
        await tick(tester);
        expect(workspaces.sessions.length, before + 1);
        final imported = workspaces.sessions.last;
        expect(imported.kind, AiWorkspaceKind.primary);
        expect(imported.busy, isFalse);
        expect(imported.assistant.messages, isEmpty);
        await tester.runAsync(() async {
          expect(
            (await storage.memories(imported.id)).single['content'],
            'Keep this imported preference',
          );
        });
        expect(
          find.byKey(const ValueKey('storage-transfer-progress-dialog')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
