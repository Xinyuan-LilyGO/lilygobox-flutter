import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/conversation_scroll_controller.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget history(
    ConversationScrollController controller,
    PageStorageBucket bucket, {
    double height = 2400,
    bool visible = true,
  }) => MaterialApp(
    home: PageStorage(
      bucket: bucket,
      child: SizedBox(
        height: 400,
        child: visible
            ? SingleChildScrollView(
                key: const PageStorageKey('conversation'),
                controller: controller,
                child: SizedBox(height: height),
              )
            : const SizedBox.shrink(),
      ),
    ),
  );

  testWidgets('missing position starts at the latest message', (tester) async {
    final controller = ConversationScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(history(controller, PageStorageBucket()));
    await tester.pumpAndSettle();
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(controller.position.extentAfter, 0);
    expect(controller.initiallyFollowsLatest, isTrue);
  });

  for (final offset in [0.0, 320.0]) {
    testWidgets('valid saved reading position $offset survives recreation', (
      tester,
    ) async {
      final bucket = PageStorageBucket();
      final first = ConversationScrollController();
      final second = ConversationScrollController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(history(first, bucket));
      await tester.pumpAndSettle();
      first.jumpTo(offset);
      await tester.pumpWidget(history(first, bucket, visible: false));
      await tester.pumpWidget(history(second, bucket));
      await tester.pumpAndSettle();
      expect(second.offset, offset);
      expect(second.initiallyFollowsLatest, isFalse);
    });
  }

  for (final value in <Object>[
    double.nan,
    double.infinity,
    -100.0,
    1e8,
    'invalid',
  ]) {
    testWidgets(
      'invalid saved position $value falls back to the latest message',
      (tester) async {
        final bucket = PageStorageBucket();
        final first = ConversationScrollController();
        final second = ConversationScrollController();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        await tester.pumpWidget(history(first, bucket));
        await tester.pumpAndSettle();
        bucket.writeState(first.position.context.storageContext, value);
        await tester.pumpWidget(history(first, bucket, visible: false));
        await tester.pumpWidget(history(second, bucket));
        await tester.pumpAndSettle();
        expect(second.position.extentAfter, 0);
        expect(second.initiallyFollowsLatest, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'async history opens at the bottom but rebuilding preserves manual reading',
    (tester) async {
      final controller = ConversationScrollController();
      final bucket = PageStorageBucket();
      addTearDown(controller.dispose);
      await tester.pumpWidget(history(controller, bucket, visible: false));
      await tester.pumpAndSettle();
      expect(controller.hasClients, isFalse);
      await tester.pumpWidget(history(controller, bucket));
      await tester.pumpAndSettle();
      expect(controller.position.extentAfter, 0);
      controller.jumpTo(200);
      await tester.pumpWidget(history(controller, bucket, height: 3000));
      await tester.pumpAndSettle();
      expect(controller.offset, 200);
    },
  );
}
