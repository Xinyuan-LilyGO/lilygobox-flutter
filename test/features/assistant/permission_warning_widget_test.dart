import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/confirmation_dialog.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/permissions_button.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'assistant_test_scope.dart';

void main() {
  group('Sensitive permission confirmation', () {
    for (final dark in [false, true]) {
      for (final narrow in [false, true]) {
        testWidgets(
          'confirms enable, cancels safely and resets bypass ($dark/$narrow)',
          (tester) async {
            final captureKey = GlobalKey();
            if (const bool.fromEnvironment('CAPTURE_PERMISSION_WARNINGS')) {
              await (FontLoader('LilygoBoxInter')..addFont(
                    rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf'),
                  ))
                  .load();
              await tester.runAsync(() async {
                final cjkFont = File(
                  '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/msyh.ttc',
                );
                if (Platform.isWindows && await cjkFont.exists()) {
                  await (FontLoader('PermissionCaptureCjk')..addFont(
                        Future.value(
                          ByteData.sublistView(await cjkFont.readAsBytes()),
                        ),
                      ))
                      .load();
                }
              });
              await (FontLoader(
                    'packages/material_symbols_icons/MaterialSymbolsRounded',
                  )..addFont(
                    rootBundle.load(
                      'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
                    ),
                  ))
                  .load();
            }
            Future<void> capture(String name) async {
              if (!const bool.fromEnvironment('CAPTURE_PERMISSION_WARNINGS') ||
                  narrow) {
                return;
              }
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(captureKey),
                );
                final image = await boundary.toImage(pixelRatio: 1.5);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory('tmp').create(recursive: true);
                await File(
                  'tmp/permission-warning-$name-$dark.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }

            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = narrow
                ? const Size(360, 760)
                : const Size(800, 600);
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
            await scope.provider.initialized;
            addTearDown(() {
              scope.dispose();
              theme.dispose();
              language.dispose();
              shell.dispose();
              split.dispose();
            });
            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('zh'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                scrollBehavior: const AppScrollBehavior(),
                theme: ThemeData(
                  colorScheme: theme.themeData.materialColors,
                  fontFamily: 'LilygoBoxInter',
                  fontFamilyFallback: const ['PermissionCaptureCjk'],
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(narrow ? 1.5 : 1)),
                  child: RepaintBoundary(key: captureKey, child: child!),
                ),
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: AssistantPermissionsButton(
                      theme: theme.themeData,
                      assistant: scope.provider,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            Future<void> openCustom() async {
              if (find
                  .byKey(const ValueKey('ai-permissions-panel'))
                  .evaluate()
                  .isEmpty) {
                await tester.tap(
                  find.byKey(const ValueKey('ai-permissions-button')),
                );
                await tester.pumpAndSettle();
              }
              final custom = find.byKey(
                const ValueKey('ai-permission-mode-custom'),
              );
              if (custom.evaluate().isNotEmpty) {
                await tester.tap(custom);
                await tester.pumpAndSettle();
              }
            }

            Future<void> toggle(String key) async {
              await openCustom();
              final control = find.byKey(ValueKey(key));
              await tester.ensureVisible(control);
              await tester.pumpAndSettle();
              await tester.tap(control);
              await tester.pumpAndSettle();
            }

            await tester.tap(
              find.byKey(const ValueKey('ai-permissions-button')),
            );
            await tester.pumpAndSettle();
            final panelRect = tester.getRect(
              find.byKey(const ValueKey('ai-permissions-panel')),
            );
            final firstRect = tester.getRect(
              find.byKey(const ValueKey('ai-permission-mode-request')),
            );
            final lastRect = tester.getRect(
              find.byKey(const ValueKey('ai-permission-mode-custom')),
            );
            expect(firstRect.left - panelRect.left, closeTo(8, .01));
            expect(panelRect.right - lastRect.right, closeTo(8, .01));
            expect(panelRect.bottom - lastRect.bottom, closeTo(8, .01));
            await capture('menu');
            await openCustom();
            expect(
              find.byKey(const ValueKey('ai-permission-command-no-approval')),
              findsNothing,
            );
            await toggle('ai-permission-execution');
            expect(
              find.byKey(const ValueKey('ai-permission-command-no-approval')),
              findsOneWidget,
            );
            expect(
              tester.widget<Text>(find.text('命令免审批')).style?.color,
              theme.themeData.permissionWarningColor,
            );
            final commandTitle = tester.widget<Text>(find.text('允许运行本机命令'));
            expect(commandTitle.style?.fontSize, 13);
            expect(commandTitle.style?.fontWeight, FontWeight.w500);
            for (final description in [
              '运行命令时不再请求批准。',
              '允许访问本地文件，无需逐文件夹授权，仍受系统权限限制。',
            ]) {
              expect(
                tester.widget<Text>(find.text(description)).style?.color,
                theme.themeData.permissionWarningColor,
              );
            }
            for (final commands in [true, false]) {
              final key = commands ? 'command-no-approval' : 'full-files';
              bool enabled() => commands
                  ? scope.provider.permissions.commandNoApproval
                  : scope.provider.permissions.fullFiles;
              await toggle('ai-permission-$key');
              expect(find.byType(Dialog), findsOneWidget);
              final dialog = tester.widget<AppDialog>(find.byType(AppDialog));
              final warning = find.byIcon(Symbols.warning_rounded);
              expect(tester.widget<Icon>(warning).fill, 1);
              expect(
                tester.getRect(warning).right,
                lessThan(tester.getRect(find.text(dialog.title)).left),
              );
              expect(
                tester.getCenter(warning).dy,
                closeTo(tester.getCenter(find.text(dialog.title)).dy, .01),
              );
              await capture(key);
              expect(enabled(), isFalse);
              await tester.tap(find.byKey(ValueKey('cancel-enable-$key')));
              await tester.pumpAndSettle();
              expect(enabled(), isFalse);
              await toggle('ai-permission-$key');
              await tester.tap(find.byKey(ValueKey('confirm-enable-$key')));
              await tester.pumpAndSettle();
              expect(enabled(), isTrue);
              expect(find.byType(Dialog), findsNothing);
            }
            await openCustom();
            expect(
              find.byKey(const ValueKey('ai-permission-files')),
              findsNothing,
            );
            expect(
              tester.widget<Text>(find.text('允许访问所有文件')).style?.color,
              theme.themeData.permissionWarningColor,
            );
            await toggle('ai-permission-full-files');
            expect(scope.provider.permissions.fullFiles, isFalse);
            expect(find.byType(Dialog), findsNothing);
            await toggle('ai-permission-execution');
            expect(scope.provider.permissions.commandNoApproval, isFalse);
            expect(
              find.byKey(const ValueKey('ai-permission-command-no-approval')),
              findsNothing,
            );
            await toggle('ai-permission-execution');
            expect(scope.provider.permissions.commandNoApproval, isFalse);
            await toggle('ai-permission-command-no-approval');
            // 直接关闭提示框同样不能开启权限。
            final dialogContext = tester.element(find.byType(Dialog));
            Navigator.of(dialogContext).pop();
            await tester.pumpAndSettle();
            expect(scope.provider.permissions.commandNoApproval, isFalse);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  });
}
