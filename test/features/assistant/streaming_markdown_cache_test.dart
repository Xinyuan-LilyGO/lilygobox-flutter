import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/message_content.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('long Markdown parses once across theme and scale changes', (
    tester,
  ) async {
    final syntax = _CountingBlockSyntax();
    final replacement = _CountingBlockSyntax();
    Future<void> pump({
      String tail = '',
      bool dark = false,
      double scale = 1,
      _CountingBlockSyntax? blockSyntax,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SelectionArea(
              child: SingleChildScrollView(
                child: ChatMarkdownBody(
                  MarkdownBody(
                    data: 'COUNTED\n\n${_longPrefix()}$tail',
                    blockSyntaxes: [blockSyntax ?? syntax],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await pump();
    expect(syntax.parses, 1);
    final initialHeight = tester.getSize(find.byType(ChatMarkdownBody)).height;
    for (var index = 0; index < 8; index++) {
      await pump(dark: index.isEven, scale: 1 + index / 10);
      expect(syntax.parses, 1);
    }
    expect(
      tester.getSize(find.byType(ChatMarkdownBody)).height,
      greaterThan(initialHeight),
    );
    await pump(tail: '\n\nNew paragraph');
    expect(syntax.parses, 2);
    await pump(tail: '\n\nNew paragraph', blockSyntax: replacement);
    expect(replacement.parses, 1);
    expect(find.text('New paragraph', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final parentSelection in [false, true]) {
    testWidgets(
      'unchanged Markdown widget survives status updates: parent=$parentSelection',
      (tester) async {
        final theme = ThemeProvider();
        addTearDown(theme.dispose);
        final message = AiMessage(
          id: 'stable',
          role: 'assistant',
          content: _longPrefix(),
        );
        Future<void> pump(AiResponseStatus status) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SelectionArea(
                child: SingleChildScrollView(
                  child: ChatMessageBody(
                    message: message.copyWith(status: status),
                    theme: theme.themeData,
                    useParentSelectionArea: parentSelection,
                  ),
                ),
              ),
            ),
          ),
        );
        final markdown = find.byWidgetPredicate(
          (widget) => widget is MarkdownBody,
        );
        await pump(AiResponseStatus.streaming);
        final original = tester.widget(markdown);
        await pump(AiResponseStatus.completed);
        expect(identical(tester.widget(markdown), original), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('cached Markdown links use the current handler', (tester) async {
    final syntax = _CountingBlockSyntax();
    final links = <String>[];
    Future<void> pump(String label) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMarkdownBody(
            MarkdownBody(
              data: 'COUNTED\n\n[Open](https://example.test)',
              blockSyntaxes: [syntax],
              onTapLink: (_, href, _) => links.add('$label:$href'),
            ),
          ),
        ),
      ),
    );
    await pump('before');
    await tester.tap(find.text('Open', findRichText: true));
    await pump('after');
    await tester.tap(find.text('Open', findRichText: true));
    expect(links, [
      'before:https://example.test',
      'after:https://example.test',
    ]);
    expect(syntax.parses, 1);
    expect(tester.takeException(), isNull);
  });

  for (final html in ['<!-- ignored -->', '<div>ignored</div>']) {
    for (final position in ['head', 'middle', 'tail']) {
      testWidgets('ignored HTML $html at $position adds no spacing', (
        tester,
      ) async {
        final theme = ThemeProvider();
        addTearDown(theme.dispose);
        final parts = ['First paragraph', 'Second paragraph'];
        parts.insert(
          position == 'head'
              ? 0
              : position == 'middle'
              ? 1
              : 2,
          html,
        );
        final content = parts.join('\n\n');
        Future<void> pump(Widget child) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: const ValueKey('markdown-size'),
                  width: 400,
                  child: child,
                ),
              ),
            ),
          ),
        );
        final body = ChatMessageBody(
          message: AiMessage(id: 'html', role: 'assistant', content: content),
          theme: theme.themeData,
        );
        await pump(body);
        final cachedMarkdown = tester.widget<MarkdownBody>(
          find.byWidgetPredicate((widget) => widget is MarkdownBody),
        );
        final cachedSize = tester.getSize(
          find.byKey(const ValueKey('markdown-size')),
        );
        final cachedSecondTop = tester
            .getTopLeft(find.text('Second paragraph', findRichText: true))
            .dy;
        await pump(
          MarkdownBody(data: content, styleSheet: cachedMarkdown.styleSheet),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('markdown-size'))),
          cachedSize,
        );
        expect(
          tester
              .getTopLeft(find.text('Second paragraph', findRichText: true))
              .dy,
          cachedSecondTop,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  final cases = <String, List<String>>{
    'empty table cells': [
      '| Name | Value |\n| --- | --- |\n| First | |',
      '| Name | Value |\n| --- | --- |\n| First | |\n\nTail',
    ],
    'empty list items': ['- ', '- \n\nTail'],
    'late reference definitions': [
      '[Read documentation][doc]\n\nTail',
      '[Read documentation][doc]\n\nTail\n\n[doc]: https://example.test/docs',
    ],
    'open fenced code': [
      'Prefix\n\n```dart\nfinal first = 1;',
      'Prefix\n\n```dart\nfinal first = 1;\nfinal second = 2;\n```\n\nTail',
    ],
    'growing table': [
      '| Name | Value |\n| --- | --- |\n| First | One |',
      '| Name | Value |\n| --- | --- |\n| First | One |\n| Second | Two |\n\nTail',
    ],
    'nested list continuation': [
      '- First\n  - Nested',
      '- First\n  - Nested\n  - Another\n- Second\n\nTail',
    ],
    'footnote reference counts': [
      'First[^note]\n\n[^note]: Footnote text',
      'First[^note] and again[^note]\n\n[^note]: Footnote text\n\nTail',
    ],
  };
  for (final entry in cases.entries) {
    testWidgets('streamed ${entry.key} matches a fresh render', (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      Future<void> pump(String id, String content) => tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SelectionArea(
              child: SingleChildScrollView(
                child: ChatMessageBody(
                  key: ValueKey(id),
                  message: AiMessage(
                    id: id,
                    role: 'assistant',
                    content: '${_longPrefix()}\n\n$content',
                  ),
                  theme: theme.themeData,
                  useParentSelectionArea: true,
                ),
              ),
            ),
          ),
        ),
      );
      List<String> text() => tester
          .widgetList<RichText>(
            find.descendant(
              of: find.byWidgetPredicate((widget) => widget is MarkdownBody),
              matching: find.byType(RichText),
            ),
          )
          .map((widget) => widget.text.toPlainText())
          .toList();
      for (final content in entry.value) {
        await pump('streaming', content);
      }
      final streamedText = text();
      final streamedTables = find.byType(Table).evaluate().length;
      await pump('fresh', entry.value.last);
      expect(text(), streamedText);
      expect(find.byType(Table).evaluate().length, streamedTables);
      if (entry.key == 'late reference definitions') {
        expect(
          find.text('Read documentation', findRichText: true),
          findsOneWidget,
        );
        expect(find.textContaining('[doc]', findRichText: true), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

String _longPrefix() => List.generate(
  12,
  (index) => 'Paragraph $index: ${'Text with **formatting**. ' * 10}',
).join('\n\n');

class _CountingBlockSyntax extends md.BlockSyntax {
  int parses = 0;

  @override
  RegExp get pattern => RegExp(r'^COUNTED$');

  @override
  md.Node parse(md.BlockParser parser) {
    parses++;
    parser.advance();
    return md.Element.text('p', 'Parsed marker');
  }
}
