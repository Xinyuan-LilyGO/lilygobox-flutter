import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/approval_panel.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/code_block.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/command_display.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

void main() {
  for (final locale in ['en', 'zh']) {
    for (final dark in [false, true]) {
      for (final width in [340.0, 800.0]) {
        testWidgets(
          'approval scrollbar reserves its gutter and keeps actions fixed ($locale/$dark/$width)',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(1000, 800);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            final theme = ThemeProvider()
              ..setTheme(dark ? ThemeType.dark : ThemeType.light);
            final focus = FocusNode();
            addTearDown(theme.dispose);
            addTearDown(focus.dispose);
            final decisions = <bool>[];
            final args = <String, Object?>{
              'executable': 'powershell.exe',
              'arguments': [
                '-NoProfile',
                '-Command',
                List.generate(
                  25,
                  (index) =>
                      "Write-Output 'long-command-line-$index ${List.filled(12, 'argument').join('-')}'",
                ).join('\n'),
              ],
              'working_directory': 'C:/firmware/project',
              // 代码块限制内部高度后，外层滚动仍由长操作说明覆盖。
              'reason': List.generate(
                8,
                (index) =>
                    'Inspection step $index: review the target and command before approval.',
              ).join('\n'),
              'permission_category': 'execution',
              'command_safety_approval': true,
              'command_risks': ['opaqueScript'],
            };
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                scrollBehavior: const AppScrollBehavior(),
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                  scrollbarTheme: const ScrollbarThemeData(
                    crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                  ),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(width == 340 ? 1.3 : 1),
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: width,
                      child: AssistantApprovalPanel(
                        request: AiMessage(
                          id: 'long-command',
                          role: 'tool',
                          content: '',
                          toolName: 'run_command',
                          toolArguments: args,
                        ),
                        theme: theme.themeData,
                        inputFocus: focus,
                        onResolve: decisions.add,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final surface = find.byKey(const ValueKey('ai-approval-surface'));
            final scrollbar = find.byKey(
              const ValueKey('ai-approval-scrollbar'),
            );
            final viewport = find.byKey(const ValueKey('ai-approval-scroll'));
            final content = find.byKey(
              const ValueKey('ai-approval-scroll-content'),
            );
            final allow = find.byKey(const ValueKey('ai-approval-allow'));
            final deny = find.byKey(const ValueKey('ai-approval-deny'));
            expect(scrollbar, findsOneWidget);
            // 嵌套代码块有自己的滚动条；外层视口只由一根滚动条装饰。
            expect(
              find.ancestor(of: viewport, matching: find.byType(Scrollbar)),
              findsOneWidget,
            );
            expect(
              ScrollbarTheme.of(tester.element(scrollbar)).crossAxisMargin,
              AppScrollBehavior.scrollbarEdgeInset,
            );
            final surfaceRect = tester.getRect(surface);
            final viewportRect = tester.getRect(viewport);
            final contentRect = tester.getRect(content);
            expect(viewportRect.right, closeTo(surfaceRect.right, .01));
            expect(viewportRect.left, closeTo(surfaceRect.left, .01));
            expect(contentRect.left - viewportRect.left, closeTo(16, .01));
            expect(viewportRect.right - contentRect.right, closeTo(20, .01));
            final fullCommand = find.byKey(
              const ValueKey('ai-approval-full-command'),
            );
            final commandText = tester.widget<Text>(
              find.descendant(
                of: fullCommand,
                matching: find.text(formatAiCommand(args)),
              ),
            );
            expect(commandText.data, formatAiCommand(args));
            expect(
              tester.widget<ChatCodeBlock>(fullCommand).initialSoftWrap,
              isTrue,
            );
            expect(commandText.softWrap, isTrue);
            expect(commandText.maxLines, isNull);
            expect(commandText.overflow, isNot(TextOverflow.ellipsis));
            expect(
              tester.getRect(fullCommand).right,
              lessThanOrEqualTo(contentRect.right),
            );
            final initialAllowRect = tester.getRect(allow);
            final initialDenyRect = tester.getRect(deny);
            expect(
              initialAllowRect.top,
              greaterThanOrEqualTo(viewportRect.bottom),
            );
            expect(allow.hitTestable(), findsOneWidget);
            expect(deny.hitTestable(), findsOneWidget);
            final controller = tester
                .widget<SingleChildScrollView>(viewport)
                .controller!;
            expect(controller.position.maxScrollExtent, greaterThan(100));
            final initialOffset = controller.offset;
            await tester.sendEventToBinding(
              PointerScrollEvent(
                // 左侧留白属于外层视口，避免代码块接管此次滚轮。
                position: Offset(viewportRect.left + 8, viewportRect.center.dy),
                scrollDelta: const Offset(0, 100),
              ),
            );
            expect(controller.offset, initialOffset);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 60));
            expect(controller.offset, greaterThan(initialOffset));
            expect(controller.offset, lessThan(initialOffset + 100));
            await tester.pumpAndSettle();
            expect(controller.offset, closeTo(initialOffset + 100, .01));
            controller.jumpTo(controller.position.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(content).right,
              closeTo(contentRect.right, .01),
            );
            expect(tester.getRect(allow), initialAllowRect);
            expect(tester.getRect(deny), initialDenyRect);
            expect(
              find.textContaining('C:/firmware/project').hitTestable(),
              findsOneWidget,
            );
            await tester.tap(allow);
            await tester.tap(deny);
            expect(decisions, [true, false]);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
