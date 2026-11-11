import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/core/widgets/settings/select.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_composer.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/permissions_button.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'assistant_test_scope.dart';

void main() {
  for (final dark in [false, true]) {
    for (final locale in ['en', 'zh']) {
      for (final narrow in [false, true]) {
        testWidgets(
          'permission menu applies changes through real clicks ($dark/$locale/narrow:$narrow)',
          (tester) async {
            if (narrow) {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = const Size(360, 760);
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
            }
            final boundaryKey = GlobalKey();
            Future<void> capture(String name) async {
              if (!const bool.fromEnvironment('CAPTURE_PERMISSION_UI') ||
                  narrow) {
                return;
              }
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(boundaryKey),
                );
                final image = await boundary.toImage(pixelRatio: 1.5);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File('tmp/permission-$name-$dark-$locale.png');
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }

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
            final input = TextEditingController();
            final focus = FocusNode();
            final scroll = ScrollController();
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                scrollBehavior: const AppScrollBehavior(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(narrow ? 1.5 : 1)),
                  child: RepaintBoundary(key: boundaryKey, child: child!),
                ),
                theme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.purple,
                    brightness: dark ? Brightness.dark : Brightness.light,
                  ),
                ),
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: 450,
                      child: ListenableBuilder(
                        listenable: scope.provider,
                        builder: (context, _) => ChatComposer(
                          input: input,
                          focusNode: focus,
                          scrollController: scroll,
                          theme: theme.themeData,
                          assistant: scope.provider,
                          ready: false,
                          onSend: (_) {},
                          attachments: const [],
                          onAttachmentsChanged: (_) {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.byType(AssistantPermissionsButton));
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsNothing);
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('ai-permissions-panel')))
                  .bottom,
              lessThan(
                tester
                    .getRect(
                      find.byKey(const ValueKey('ai-permissions-button')),
                    )
                    .top,
              ),
            );
            expect(
              find.byKey(const ValueKey('ai-permissions-panel')),
              findsOneWidget,
            );
            final requestOption = tester.widget<MenuItemSurface>(
              find.byKey(const ValueKey('ai-permission-mode-request')),
            );
            expect(
              requestOption.selectedColor,
              theme.themeData.primaryTextHoverColor,
            );
            expect(requestOption.hoverColor, theme.themeData.basePrimary);
            final heading = tester.widget<Text>(
              find.byKey(const ValueKey('ai-permissions-heading')),
            );
            expect(heading.style?.fontSize, 13);
            expect(heading.style?.fontWeight, FontWeight.w600);
            await capture('modes');
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('ai-permissions-button')),
                matching: find.byIcon(Symbols.front_hand_rounded),
              ),
              findsOneWidget,
            );
            expect(find.byIcon(Symbols.check_rounded), findsOneWidget);
            final custom = find.byKey(
              const ValueKey('ai-permission-mode-custom'),
            );
            await tester.tap(custom);
            await tester.pumpAndSettle();
            await capture('custom');
            expect(scope.provider.permissions.mode, AiApprovalMode.custom);
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('ai-permissions-button')),
                matching: find.byIcon(Symbols.tune_rounded),
              ),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('ai-permissions-panel')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('ai-permissions-back')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('ai-permissions-save')),
              findsNothing,
            );
            final access = find.byKey(const ValueKey('ai-permission-files'));
            await tester.ensureVisible(access);
            await tester.tap(access);
            await tester.pumpAndSettle();
            expect(find.byType(SettingSelect<AiFileAccess>), findsOneWidget);
            await tester.tap(
              find.text(locale == 'zh' ? '读取与修改' : 'Read and modify').last,
            );
            await tester.pumpAndSettle();
            expect(scope.provider.permissions.files, AiFileAccess.readWrite);
            expect(
              find.byKey(const ValueKey('ai-permissions-panel')),
              findsOneWidget,
            );
            final network = find.byKey(const ValueKey('ai-permission-network'));
            expect(
              tester.widget<Switch>(network).activeTrackColor,
              theme.themeData.basePrimary,
            );
            await tester.ensureVisible(network);
            await tester.tap(network);
            await tester.pumpAndSettle();
            expect(scope.provider.permissions.network, isFalse);
            final foldersLabel = find.byKey(
              const ValueKey('ai-permission-folders-label'),
            );
            final addFolder = find.byKey(
              const ValueKey('ai-permission-add-folder'),
            );
            expect(
              tester.getRect(addFolder).top,
              greaterThan(tester.getRect(foldersLabel).bottom),
            );
            final foldersHelp = find.byKey(
              const ValueKey('ai-permission-folders-help'),
            );
            expect(
              tester.getRect(addFolder).left,
              greaterThan(tester.getRect(foldersHelp).right),
            );
            expect(
              tester.getRect(addFolder).center.dy,
              closeTo(tester.getRect(foldersHelp).center.dy, .01),
            );
            expect(
              find.descendant(
                of: addFolder,
                matching: find.byIcon(Symbols.add_rounded),
              ),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('ai-permissions-panel')),
              findsOneWidget,
            );
            await tester.tap(
              find.byKey(const ValueKey('ai-permissions-heading')),
            );
            await tester.pumpAndSettle();
            expect(find.byType(SettingSelect<AiFileAccess>), findsOneWidget);
            expect(
              find.byKey(const ValueKey('ai-permission-ask-outside')),
              findsNothing,
            );
            await tester.tap(find.byKey(const ValueKey('ai-permissions-back')));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('ai-permission-mode-custom')),
              findsOneWidget,
            );
            expect(find.byIcon(Symbols.check_rounded), findsOneWidget);
            await tester.tapAt(Offset(narrow ? 350 : 790, 10));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('ai-permissions-panel')),
              findsNothing,
            );
            expect(scope.provider.permissions.mode, AiApprovalMode.custom);
            expect(scope.provider.permissions.files, AiFileAccess.readWrite);
            expect(scope.provider.permissions.network, isFalse);
            await tester.tap(
              find.byKey(const ValueKey('ai-permissions-button')),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('ai-permission-mode-custom')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('ai-permissions-back')),
              findsOneWidget,
            );
            expect(scope.provider.permissions.files, AiFileAccess.readWrite);
            await tester.tap(find.byKey(const ValueKey('ai-permissions-back')));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('ai-permission-mode-request')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('ai-permissions-panel')),
              findsNothing,
            );
            expect(scope.provider.permissions.mode, AiApprovalMode.onRequest);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            scope.dispose();
            theme.dispose();
            language.dispose();
            shell.dispose();
            split.dispose();
            input.dispose();
            focus.dispose();
            scroll.dispose();
          },
        );
      }
    }
  }
}
