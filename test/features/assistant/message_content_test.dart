/*
 * @Description: 验证聊天 Markdown、跨段落选择、原文复制及消息时间布局。
 * @Author: LILYGO_L
 * @Date: 2026-11-09 15:27:53
 * @LastEditTime: 2026-11-09 16:19:35
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

void main() {
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
