/*
 * @Description: 验证聊天 Markdown、跨段落选择、原文复制及消息时间布局。
 * @Author: LILYGO_L
 * @Date: 2026-11-09 15:27:53
 * @LastEditTime: 2026-11-11 14:58:26
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
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/message_content.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
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
        final selectable = tester.widget<SelectableText>(
          find.byType(SelectableText),
        );
        expect(selectable.selectionWidthStyle, ui.BoxWidthStyle.tight);
        expect(selectable.data, code);
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        editable.userUpdateTextEditingValue(
          editable.textEditingValue.copyWith(
            selection: TextSelection(baseOffset: 0, extentOffset: code.length),
          ),
          SelectionChangedCause.keyboard,
        );
        await tester.pump();
        editable.copySelection(SelectionChangedCause.keyboard);
        await tester.pump();
        expect(copied, code);
        final render = editable.renderEditable;
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
          find.byKey(const ValueKey('ai-inline-code')),
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
