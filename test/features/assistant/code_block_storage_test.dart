import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/theme/definition.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/code_block.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/message_content.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('code axes restore independently after history unmounts', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    final code = List.generate(
      40,
      (index) => 'line $index: ${'wide argument ' * 50}',
    ).join('\n');
    Future<void> pump(bool visible) => tester.pumpWidget(
      _host(
        bucket,
        visible
            ? Column(
                children: [
                  for (var index = 0; index < 2; index++)
                    ChatCodeBlock(
                      key: PageStorageKey('block-$index'),
                      text: code,
                      language: 'text',
                      theme: MaterialPalette.create(ThemeType.light),
                      maxBodyHeight: 160,
                    ),
                ],
              )
            : const SizedBox(),
      ),
    );
    ScrollController scroll(int block, String axis) => tester
        .widget<SingleChildScrollView>(
          find.descendant(
            of: find.byKey(PageStorageKey('block-$block')),
            matching: find.byKey(ValueKey('ai-code-$axis-scroll')),
          ),
        )
        .controller!;

    await pump(true);
    for (var block = 0; block < 2; block++) {
      scroll(block, 'horizontal').jumpTo(120.0 + block * 50);
      scroll(block, 'vertical').jumpTo(80.0 + block * 30);
    }
    await tester.pump();
    await pump(false);
    expect(find.byType(ChatCodeBlock), findsNothing);
    await pump(true);
    for (var block = 0; block < 2; block++) {
      expect(scroll(block, 'horizontal').offset, 120.0 + block * 50);
      expect(scroll(block, 'vertical').offset, 80.0 + block * 30);
    }
    expect(tester.takeException(), isNull);
  });

  for (final long in [false, true]) {
    testWidgets('Markdown block wrap survives unmount and theme: long=$long', (
      tester,
    ) async {
      final bucket = PageStorageBucket();
      final code = 'unwrapped ${'argument ' * 30}';
      final prefix = long ? '${'A paragraph of text. ' * 120}\n\n' : '';
      final content = '$prefix```text\n$code\n```\n\n```text\n$code\n```';
      Future<void> pump(bool visible, {bool dark = false}) => tester.pumpWidget(
        _host(
          bucket,
          visible
              ? SelectionArea(
                  child: SingleChildScrollView(
                    child: ChatMessageBody(
                      message: AiMessage(
                        id: 'wrap-message',
                        role: 'assistant',
                        content: content,
                      ),
                      theme: MaterialPalette.create(
                        dark ? ThemeType.dark : ThemeType.light,
                      ),
                      useParentSelectionArea: true,
                    ),
                  ),
                )
              : const SizedBox(),
        ),
      );
      Finder block(int index) =>
          find.byKey(PageStorageKey('ai-message-code-wrap-message-$index'));
      Finder wrap(int index) => find.descendant(
        of: block(index),
        matching: find.byKey(const ValueKey('ai-code-wrap')),
      );
      bool wrapped(int index) =>
          tester
              .widget<Text>(
                find.descendant(
                  of: block(index),
                  matching: find.text('$code\n'),
                ),
              )
              .softWrap ??
          true;

      await pump(true);
      await tester.ensureVisible(wrap(0));
      await tester.tap(wrap(0));
      await tester.pump();
      expect(wrapped(0), isTrue);
      expect(wrapped(1), isFalse);
      await pump(true, dark: true);
      expect(wrapped(0), isTrue);
      expect(wrapped(1), isFalse);
      await pump(false);
      expect(find.byType(ChatCodeBlock), findsNothing);
      await pump(true);
      expect(wrapped(0), isTrue);
      expect(wrapped(1), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _host(PageStorageBucket bucket, Widget child) => MaterialApp(
  localizationsDelegates: appLocalizationDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: PageStorage(
      bucket: bucket,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 360, child: child),
      ),
    ),
  ),
);
