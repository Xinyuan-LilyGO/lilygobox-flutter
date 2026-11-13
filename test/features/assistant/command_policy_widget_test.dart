import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/dialog_style.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/approval_panel.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/command_display.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/command_policy_text.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

void main() {
  for (final locale in ['en', 'zh']) {
    for (final dark in [false, true]) {
      testWidgets(
        'command safety confirmation uses existing panel ($locale/$dark)',
        (tester) async {
          final theme = ThemeProvider()
            ..setTheme(dark ? ThemeType.dark : ThemeType.light);
          final focus = FocusNode();
          addTearDown(theme.dispose);
          addTearDown(focus.dispose);
          bool? approved;
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: 450,
                    child: AssistantApprovalPanel(
                      request: AiMessage(
                        id: 'safety',
                        role: 'tool',
                        content: '',
                        createdAt: DateTime(2026),
                        toolName: 'run_command',
                        toolArguments: const {
                          'executable': 'powershell.exe',
                          'arguments': [
                            '-Command',
                            'Remove-Item -Force target',
                          ],
                          'working_directory': 'C:/work',
                          'reason': 'test',
                          'permission_category': 'execution',
                          'command_safety_approval': true,
                          'command_risks': ['forceDelete'],
                          'command_rules': ['["powershell"]'],
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
          expect(find.text(l10n.aiCommandSafetyTitle), findsOneWidget);
          final command = formatAiCommand({
            'executable': 'powershell.exe',
            'arguments': ['-Command', 'Remove-Item -Force target'],
          });
          expect(find.text(command), findsOneWidget);
          expect(find.text(l10n.aiCommandFull), findsOneWidget);
          expect(find.text('powershell.exe'), findsNothing);
          expect(find.textContaining(l10n.aiCommandArguments), findsNothing);
          expect(find.textContaining('C:/work'), findsOneWidget);
          expect(
            find.textContaining(l10n.aiCommandRiskForceDelete),
            findsOneWidget,
          );
          expect(find.text(l10n.aiPermissionExecutionHelp), findsNothing);
          expect(
            find.textContaining(l10n.aiCommandApprovalNotice),
            findsOneWidget,
          );
          final commandTop = tester
              .getTopLeft(find.text(l10n.aiCommandFull))
              .dy;
          expect(
            tester
                .getBottomLeft(
                  find.textContaining(l10n.aiCommandRiskForceDelete),
                )
                .dy,
            lessThan(commandTop),
          );
          expect(
            tester
                .getBottomLeft(
                  find.textContaining(l10n.aiCommandApprovalNotice),
                )
                .dy,
            lessThan(commandTop),
          );
          expect(
            tester.getTopLeft(find.text(l10n.aiCommandReason)).dy,
            greaterThan(commandTop),
          );
          expect(find.text(l10n.aiCommandReason), findsOneWidget);
          expect(find.text('test'), findsOneWidget);
          expect(
            tester.widget<Text>(find.text('test')).style,
            AppDialogStyle.descriptionStyle(theme.themeData),
          );
          expect(
            tester.widget<Text>(find.text('C:/work')).style,
            AppDialogStyle.descriptionStyle(theme.themeData),
          );
          expect(find.text(l10n.aiCommandDirectory), findsOneWidget);
          expect(find.textContaining(l10n.aiCommandRulePrompt), findsOneWidget);
          final description = tester.widget<Text>(
            find.byKey(const ValueKey('ai-approval-description')),
          );
          expect(
            description.style,
            AppDialogStyle.descriptionStyle(theme.themeData),
          );
          final noticeTitle = tester.widget<Text>(
            find.text(l10n.aiCommandNoticeTitle),
          );
          expect(
            noticeTitle.style,
            AppDialogStyle.fieldTitleStyle(theme.themeData),
          );
          expect(find.text(l10n.aiToolCommand), findsNothing);
          expect(
            description.data,
            [
              l10n.aiCommandRiskForceDelete,
              l10n.aiCommandRulePrompt,
              '${l10n.aiCommandMatchedRules}: ["powershell"]',
              l10n.aiCommandApprovalNotice,
            ].join(' '),
          );
          expect(find.byType(Dialog), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.byKey(const ValueKey('ai-approval-allow')),
          );
          await tester.tap(find.byKey(const ValueKey('ai-approval-allow')));
          expect(approved, isTrue);
          await tester.tap(find.byKey(const ValueKey('ai-approval-deny')));
          expect(approved, isFalse);
          expect(
            aiCommandPolicyOutputText(
              l10n,
              '{"ok":false,"error_code":"command_forbidden"}',
            ),
            l10n.aiCommandPolicyForbidden,
          );
          expect(
            aiCommandPolicyOutputText(
              l10n,
              '{"ok":false,"error_code":"command_invalidRules"}',
            ),
            l10n.aiCommandPolicyInvalidRules,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
