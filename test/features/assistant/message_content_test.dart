/*
 * @Description: 验证聊天 Markdown、跨段落选择、原文复制及消息时间布局。
 * @Author: LILYGO_L
 * @Date: 2026-11-09 15:27:53
 * @LastEditTime: 2026-11-12 01:36:38
 */

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/context_menu/text_selection_menu.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/features/assistant/data/message_link_opener.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/message_content.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  for (final opens in [true, false]) {
    testWidgets('link tap opens externally or shows failure: $opens', (
      tester,
    ) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      final launched = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatMessageBody(
              message: const AiMessage(
                id: 'link',
                role: 'assistant',
                content: '[打开链接](https://example.test/preview)',
              ),
              theme: theme.themeData,
              linkOpener: MessageLinkOpener(
                launch: (uri) async {
                  launched.add(uri);
                  return opens;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开链接', findRichText: true));
      await tester.pumpAndSettle();
      expect(launched, [Uri.parse('https://example.test/preview')]);
      expect(find.byType(SnackBar), opens ? findsNothing : findsOneWidget);
      if (!opens) expect(find.text('无法打开此链接。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final wide in [false, true]) {
    testWidgets(
      'chat code selection stays tight and copies whitespace: wide=$wide',
      (tester) async {
        final theme = ThemeProvider();
        addTearDown(theme.dispose);
        final code =
            '  short  \n\n${wide ? 'long content ' * 80 : 'longer content'}\n';
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData')
              copied = (call.arguments as Map)['text'] as String;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: SelectionArea(
                  child: ChatMessageBody(
                    message: AiMessage(
                      id: 'code',
                      role: 'assistant',
                      content: '```text\n$code```',
                    ),
                    theme: theme.themeData,
                    useParentSelectionArea: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final region = tester.state<SelectableRegionState>(
          find.byType(SelectableRegion),
        );
        region.selectAll(SelectionChangedCause.toolbar);
        await tester.pump();
        region.copySelection(SelectionChangedCause.toolbar);
        await tester.pump();
        expect(copied, code);
        final render = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text(code), matching: find.byType(RichText)),
        );
        final boxes = render.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: code.length),
        );
        expect(boxes.first.right, lessThan(200));
        expect(
          boxes.first.right,
          lessThan(
            boxes.map((box) => box.right).reduce((a, b) => a > b ? a : b),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'region select all includes user, Markdown and both code widths',
    (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      final wideCode = 'wide token ' * 80;
      final messages = [
        AiMessage(id: 'user', role: 'user', content: 'USER_MESSAGE'),
        AiMessage(
          id: 'assistant',
          role: 'assistant',
          content:
              'BODY_BEFORE\n\n```text\nSHORT_CODE\n```\n\n'
              'BODY_BETWEEN\n\n```text\n$wideCode\n```\n\nBODY_AFTER',
        ),
      ];
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SelectionArea(
              child: SizedBox(
                width: 400,
                child: Column(
                  children: [
                    for (final message in messages)
                      ChatMessageBody(
                        message: message,
                        theme: theme.themeData,
                        useParentSelectionArea: true,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      region.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      for (final text in ['USER_MESSAGE', 'SHORT_CODE\n', '$wideCode\n']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text(text), matching: find.byType(RichText)),
        );
        expect(paragraph.selections, isNotEmpty, reason: text);
        expect(paragraph.selections.single.baseOffset, 0);
        expect(paragraph.selections.single.extentOffset, text.length);
      }
      region.copySelection(SelectionChangedCause.toolbar);
      await tester.pump();
      for (final text in [
        'USER_MESSAGE',
        'BODY_BEFORE',
        'SHORT_CODE',
        'BODY_BETWEEN',
        wideCode,
        'BODY_AFTER',
      ]) {
        expect(copied, contains(text));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multiple and repeated inline code survives streaming and selection',
    (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      Future<void> render(String content) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SelectionArea(
                child: ChatMessageBody(
                  message: AiMessage(
                    id: 'inline',
                    role: 'assistant',
                    content: content,
                  ),
                  theme: theme.themeData,
                  useParentSelectionArea: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await render('Files: `alpha`');
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      region.selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      await render('Files: `alpha`, `beta`, and `alpha`.');
      expect(find.text('alpha'), findsNWidgets(2));
      expect(find.text('beta'), findsOneWidget);
      region.selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await render('Files: `alpha`, `beta`, and `alpha`. More: `gamma`.');
      expect(find.text('gamma'), findsOneWidget);
    },
  );

  for (final kind in ['user', 'markdown', 'wide-code']) {
    testWidgets(
      'clicking outside clears $kind selection and keeps menu copying',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final theme = ThemeProvider();
        addTearDown(theme.dispose);
        final selectedText = kind == 'wide-code'
            ? '${List.filled(30, 'alpha beta ').join()}\n'
            : 'Alpha beta gamma';
        final message = AiMessage(
          id: 'selected',
          role: kind == 'user' ? 'user' : 'assistant',
          content: kind == 'wide-code'
              ? '```text\n$selectedText```'
              : selectedText,
        );
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData')
              copied = (call.arguments as Map)['text'] as String;
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            return null;
          },
        );
        addTearDown(() {
          ContextMenuController.removeAny();
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: theme,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      width: 80,
                      child: ColoredBox(color: Colors.transparent),
                    ),
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          width: 300,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ChatMessageBody(
                                message: message,
                                theme: theme.themeData,
                              ),
                              const SizedBox(height: 30),
                              const TextField(key: ValueKey('draft')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final body = find.byType(ChatMessageBody);
        if (kind == 'wide-code') {
          final codeScrollbars = find.descendant(
            of: find.byKey(const ValueKey('ai-code-block')),
            matching: find.byKey(
              const ValueKey('ai-code-horizontal-scrollbar'),
            ),
          );
          expect(codeScrollbars, findsOneWidget);
          expect(tester.widget<Scrollbar>(codeScrollbars).interactive, isTrue);
        }
        bool hasSelection() {
          final paragraphs = find.descendant(
            of: body,
            matching: find.byType(RichText),
          );
          for (final element in paragraphs.evaluate()) {
            if ((element.renderObject! as RenderParagraph).selections.any(
              (selection) => !selection.isCollapsed,
            ))
              return true;
          }
          final editors = find.descendant(
            of: body,
            matching: find.byType(EditableText),
          );
          return editors.evaluate().any(
            (element) => !(element.widget as EditableText)
                .controller
                .selection
                .isCollapsed,
          );
        }

        final text = find.text(selectedText).first;
        Future<void> select() async {
          final rect = tester.getRect(text);
          final start = rect.topLeft + const Offset(2, 8);
          await tester.dragFrom(
            start,
            const Offset(80, 0),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          expect(hasSelection(), isTrue);
        }

        await select();
        await tester.tapAt(
          tester.getTopLeft(text) + const Offset(30, 8),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(hasSelection(), isTrue);
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();
        expect(copied, isNotEmpty);
        await select();
        await tester.tapAt(
          const Offset(20, 300),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(hasSelection(), isFalse);
        await select();
        await tester.tap(find.byKey(const ValueKey('draft')));
        await tester.pumpAndSettle();
        expect(hasSelection(), isFalse);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const ValueKey('draft')),
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  const markdown =
      '## Heading\n\n**Bold** and `inline` and [link](https://example.com)\n\n- First\n- Second\n\n'
      '> Quote\n\n```dart\nprint("hello");\n```\n\n```text\n  Keep indentation  \nNext line\n```\n\n'
      '| Key | Value |\n| --- | --- |\n| Theme | Light |';

  for (final type in ThemeType.values) {
    testWidgets(
      'renders Markdown and copies the original text in $type',
      (tester) async {
        final theme = ThemeProvider();
        addTearDown(theme.dispose);
        theme.setTheme(type);
        final longMarkdown =
            '${List.generate(30, (i) => 'Paragraph $i before the code blocks.').join('\n\n')}\n\n$markdown';
        final message = AiMessage(
          id: 'reply',
          role: 'assistant',
          content: longMarkdown,
          createdAt: DateTime(2026, 11, 9, 15, 22, 32),
        );
        final boundary = GlobalKey();
        if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
          final font = FontLoader('LilygoBoxInter')
            ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf'));
          final symbols =
              FontLoader(
                'packages/material_symbols_icons/MaterialSymbolsRounded',
              )..addFont(
                rootBundle.load(
                  'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
                ),
              );
          final mono = FontLoader('monospace')
            ..addFont(
              rootBundle.load('assets/fonts/Roboto/Roboto-Variable.ttf'),
            );
          await Future.wait([font.load(), symbols.load(), mono.load()]);
        }
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            theme: ThemeData(
              colorScheme: theme.themeData.materialColors,
              fontFamily: 'LilygoBoxInter',
            ),
            builder: (context, child) =>
                RepaintBoundary(key: boundary, child: child!),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              backgroundColor: theme.themeData.secondary,
              body: ListView(
                children: [
                  SizedBox(
                    width: 300,
                    child: Column(
                      children: [
                        ChatMessageBody(
                          message: message,
                          theme: theme.themeData,
                        ),
                        ChatMessageActions(
                          message: message,
                          theme: theme.themeData,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(find.byType(Table), findsOneWidget);
        expect(find.text('Heading'), findsOneWidget);
        expect(find.text('2026.11.09 15:22:32'), findsOneWidget);
        expect(
          tester
              .widget<SelectionArea>(find.byType(SelectionArea))
              .contextMenuBuilder,
          AppTextSelectionMenu.buildRegion,
        );
        expect(find.byKey(const ValueKey('ai-code-block')), findsNWidgets(2));
        final inline = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.text('inline'),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(
          (inline.decoration as BoxDecoration).borderRadius,
          BorderRadius.circular(4),
        );
        final linkStyle = tester
            .widget<MarkdownBody>(find.byType(MarkdownBody))
            .styleSheet!
            .a!;
        expect(linkStyle.decorationColor, linkStyle.color);
        Future<void> selectText(String value) async {
          final target = find.text(value);
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          final rect = tester.getRect(target);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: rect.topLeft + const Offset(1, 8));
          await mouse.down(rect.topLeft + const Offset(1, 8));
          await mouse.moveTo(
            rect.topLeft + Offset(rect.width.clamp(20, 90), 8),
          );
          await mouse.up();
          await tester.pump();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          expect(copied, isNotNull);
          expect(value, contains(copied!));
          expect(copied, isNotEmpty);
          await mouse.removePointer();
          copied = null;
        }

        await selectText('print("hello");\n');
        await selectText('  Keep indentation  \nNext line\n');
        await selectText('Light');
        final firstCode = find.text('print("hello");\n');
        await tester.ensureVisible(firstCode);
        await tester.pumpAndSettle();
        final start = tester.getTopLeft(firstCode) + const Offset(1, 8);
        final end =
            tester.getBottomRight(
              find.text('  Keep indentation  \nNext line\n'),
            ) -
            const Offset(1, 8);
        final drag = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await drag.addPointer(location: start);
        await drag.down(start);
        await drag.moveTo(end);
        await drag.up();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(copied, contains('Next line'));
        await drag.removePointer();

        final codeCopies = find.byKey(const ValueKey('ai-copy-code'));
        await tester.ensureVisible(codeCopies.first);
        await tester.tap(codeCopies.first);
        await tester.pump();
        expect(copied, 'print("hello");\n');
        await tester.pump(const Duration(seconds: 3));
        await tester.ensureVisible(codeCopies.last);
        await tester.tap(codeCopies.last);
        await tester.pump();
        expect(copied, '  Keep indentation  \nNext line\n');
        await tester.pump(const Duration(seconds: 3));
        final copy = find.byKey(const ValueKey('ai-copy-message-reply'));
        await tester.ensureVisible(copy);
        if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
          await tester.runAsync(() async {
            final render = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(boundary),
            );
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('tmp/assistant-ui/markdown-${type.name}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(copy);
        await tester.pump();
        expect(copied, longMarkdown);
        expect(find.byTooltip('Copied'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'keeps user text literal and fits timestamps at large text sizes',
    (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      final message = AiMessage(
        id: 'user',
        role: 'user',
        content: '**literal**',
        createdAt: DateTime(2026, 11, 9, 15, 22, 32),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SizedBox(
                width: 260,
                child: Column(
                  children: [
                    ChatMessageBody(message: message, theme: theme.themeData),
                    ChatMessageActions(
                      message: message,
                      theme: theme.themeData,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('**literal**'), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
