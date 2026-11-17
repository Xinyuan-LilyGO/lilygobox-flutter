import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/message_content.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final entry in {
    'empty table cell': '| Name | Value |\n| --- | --- |\n| First | |',
    'empty list item': '- ',
  }.entries) {
    testWidgets('streaming retains ${entry.key} block widgets', (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      Future<void> pump(String tail) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageBody(
              message: AiMessage(
                id: 'empty-block',
                role: 'assistant',
                content: '${entry.value}\n\nTail $tail',
              ),
              theme: theme.themeData,
            ),
          ),
        ),
      );
      final first = find.byKey(
        const ValueKey('ai-markdown-block-empty-block-0'),
      );
      await pump('initial');
      final original = tester.widget<RepaintBoundary>(first).child;
      expect(original, isNotNull);
      if (entry.key == 'empty table cell') {
        expect(find.byType(Table), findsOneWidget);
      }
      for (var i = 0; i < 5; i++) {
        await pump('updated $i');
        expect(
          identical(tester.widget<RepaintBoundary>(first).child, original),
          isTrue,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

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

  testWidgets('streaming retains unchanged Markdown widgets', (tester) async {
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    Future<void> pump(String content) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatMessageBody(
            message: AiMessage(
              id: 'cache',
              role: 'assistant',
              content: content,
            ),
            theme: theme.themeData,
          ),
        ),
      ),
    );
    await pump('Stable **paragraph**.\n\nGrowing tail');
    final first = find.descendant(
      of: find.byKey(const ValueKey('ai-markdown-block-cache-0')),
      matching: find.byType(RichText),
    );
    final original = tester.widgetList<RichText>(first).toList();
    expect(original, isNotEmpty);
    for (var i = 0; i < 10; i++) {
      await pump('Stable **paragraph**.\n\nGrowing tail ${'word ' * i}');
      final current = tester.widgetList<RichText>(first).toList();
      expect(current.length, original.length);
      for (var j = 0; j < original.length; j++) {
        expect(identical(current[j], original[j]), isTrue);
      }
    }
    expect(tester.takeException(), isNull);
  });

  final cases = <String, List<String>>{
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
            body: SingleChildScrollView(
              child: ChatMessageBody(
                key: ValueKey(id),
                message: AiMessage(id: id, role: 'assistant', content: content),
                theme: theme.themeData,
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
