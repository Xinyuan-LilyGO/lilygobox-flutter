import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_message_list.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('相邻屏外消息可由无障碍动作滚入，外层滚动动作保持可用', (tester) async {
    final controller = ScrollController();
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 200,
                child: SingleChildScrollView(
                  controller: controller,
                  child: ChatMessageList(
                    children: List.generate(
                      60,
                      (index) => SizedBox(
                        height: 100,
                        child: Semantics(
                          key: ValueKey('history-$index'),
                          container: true,
                          label: 'History $index',
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final owner = tester.binding.renderViews.single.owner!.semanticsOwner!;

      // 检查真实框架树的连接和父子归属；增量更新检查继续由原图回归覆盖。
      List<SemanticsNode> nodes() {
        final result = <SemanticsNode>[];
        final visited = <int>{};
        void visit(SemanticsNode node) {
          expect(visited.add(node.id), isTrue, reason: '语义节点不能重复归属或成环');
          result.add(node);
          node.visitChildren((child) {
            expect(child.parent, same(node));
            visit(child);
            return true;
          });
        }

        visit(owner.rootSemanticsNode!);
        return result;
      }

      SemanticsNode history(int index) => nodes().singleWhere(
        (node) => node.getSemanticsData().label == 'History $index',
      );

      final adjacent = history(3);
      expect(adjacent.getSemanticsData().flagsCollection.isHidden, isTrue);
      expect(controller.offset, 0);
      expect(controller.position.maxScrollExtent, 5800);
      expect(history(59).getSemanticsData().flagsCollection.isHidden, isTrue);

      // 走 Windows bridge 同样派发的语义动作，不能以 controller.jumpTo 替代。
      owner.performAction(adjacent.id, ui.SemanticsAction.showOnScreen);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(200, .01));
      expect(history(3).getSemanticsData().flagsCollection.isHidden, isFalse);
      expect(history(5).getSemanticsData().flagsCollection.isHidden, isTrue);

      final scrollMetadata = nodes().where(
        (node) => node.getSemanticsData().scrollExtentMax == 5800,
      );
      expect(scrollMetadata, isNotEmpty);
      expect(
        scrollMetadata.any(
          (node) =>
              node.getSemanticsData().flagsCollection.hasImplicitScrolling,
        ),
        isTrue,
      );
      final scrollDown = nodes().firstWhere(
        (node) =>
            node.getSemanticsData().hasAction(ui.SemanticsAction.scrollDown),
      );
      final beforeScrollDown = controller.offset;
      owner.performAction(scrollDown.id, ui.SemanticsAction.scrollDown);
      await tester.pumpAndSettle();
      // Flutter 动作名称表示手势方向：向下拉使历史偏移减小，向上拉则增大。
      expect(controller.offset, lessThan(beforeScrollDown));
      final scrollUp = nodes().firstWhere(
        (node) =>
            node.getSemanticsData().hasAction(ui.SemanticsAction.scrollUp),
      );
      final beforeScrollUp = controller.offset;
      owner.performAction(scrollUp.id, ui.SemanticsAction.scrollUp);
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(beforeScrollUp));
      expect(controller.position.maxScrollExtent, 5800);
      expect(tester.takeException(), isNull);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        controller.dispose();
        semantics.dispose();
      }
    }
  });
}
