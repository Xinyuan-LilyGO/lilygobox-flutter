import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/approval_panel.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/permission_labels.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/permissions_button.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

import 'assistant_test_scope.dart';

void main() {
  for (final dark in [false, true]) {
    for (final locale in ['en', 'zh']) {
      testWidgets(
        'capability switches preserve folder grants ($dark/$locale)',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(480, 760);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final theme = ThemeProvider()
            ..setTheme(dark ? ThemeType.dark : ThemeType.light);
          final language = LanguageProvider();
          final shell = AppShellProvider();
          final split = SplitViewProvider();
          final scope = await createAssistantTestScope(
            theme: theme,
            language: language,
            shell: shell,
            splitView: split,
          );
          addTearDown(() {
            scope.dispose();
            theme.dispose();
            language.dispose();
            shell.dispose();
            split.dispose();
          });
          scope.provider.setPermissions(
            AiPermissions(
              mode: AiApprovalMode.custom,
              network: false,
              folders: ['C:/projects/board'],
              files: AiFileAccess.readOnly,
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomLeft,
                  child: AssistantPermissionsButton(
                    theme: theme.themeData,
                    assistant: scope.provider,
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const ValueKey('ai-permissions-button')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('ai-permission-mode-custom')),
          );
          await tester.pumpAndSettle();
          for (final name in ['execution', 'network']) {
            final toggle = find.byKey(ValueKey('ai-permission-$name'));
            await tester.ensureVisible(toggle);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(tester.widget<Switch>(toggle).value, isTrue);
          }
          expect(find.byType(Switch), findsNWidgets(3));
          for (final removed in ['devices', 'firmware', 'installation']) {
            expect(
              find.byKey(ValueKey('ai-permission-$removed')),
              findsNothing,
            );
          }
          final full = find.byKey(const ValueKey('ai-permission-full-files'));
          await tester.ensureVisible(full);
          await tester.tap(full);
          await tester.pumpAndSettle();
          expect(scope.provider.permissions.fullFiles, isTrue);
          expect(
            find.byKey(const ValueKey('ai-permission-files')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('ai-permission-folders-label')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('ai-permission-add-folder')),
            findsNothing,
          );
          expect(scope.provider.permissions.folders, ['C:/projects/board']);
          await tester.tap(full);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('ai-permission-files')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('ai-permission-add-folder')),
            findsOneWidget,
          );
          expect(
            scope.provider.permissions.accessForFolder('C:/projects/board'),
            AiFileAccess.readOnly,
          );
          expect(scope.provider.permissions.execution, isTrue);
          expect(scope.provider.permissions.network, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          scope.provider.clearConversation();
          expect(scope.provider.permissions.execution, isFalse);
          expect(scope.provider.permissions.fullFiles, isFalse);
        },
      );
    }
  }

  for (final category in AiPermissionCategory.values) {
    testWidgets(
      'command approval identifies ${category.name} and keeps actions visible',
      (tester) async {
        final theme = ThemeProvider();
        final focus = FocusNode();
        addTearDown(theme.dispose);
        addTearDown(focus.dispose);
        bool? approved;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 340,
                  child: AssistantApprovalPanel(
                    request: AiMessage(
                      id: 'approval',
                      role: 'tool',
                      content: '',
                      toolName: 'run_command',
                      toolArguments: {
                        'permission_category': category.name,
                        'executable': 'powershell.exe',
                        'arguments': [
                          '-Command',
                          List.filled(100, 'command-argument').join(' '),
                        ],
                        'reason': 'Inspect and build the selected project',
                        'working_directory': 'D:/projects/board',
                        'resolved_path': 'D:/projects/board',
                      },
                    ),
                    theme: theme.themeData,
                    inputFocus: focus,
                    onResolve: (value) => approved = value,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AssistantApprovalPanel)),
        );
        expect(
          find.text(aiPermissionCategoryLabel(l10n, category)),
          findsOneWidget,
        );
        expect(find.text(l10n.aiCommandApprovalNotice), findsOneWidget);
        expect(find.textContaining('powershell.exe'), findsOneWidget);
        expect(find.textContaining('D:/projects/board'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ai-approval-allow')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('ai-approval-deny')));
        expect(approved, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
