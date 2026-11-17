import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/widgets/app_tooltip.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_message_list.dart';
import 'package:material_ui/material_ui.dart';

class _ChatSemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  final nodes = <int, ({List<int> children, String label})>{};
  var updates = 0;

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _ChatGraphUpdateBuilder(this);
}

class _ChatGraphUpdateBuilder extends Fake
    implements ui.SemanticsUpdateBuilder {
  _ChatGraphUpdateBuilder(this.binding);
  final _ChatSemanticsBinding binding;
  final changes = <int, ({List<int> children, String label})>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final arguments = invocation.namedArguments;
      changes[arguments[#id] as int] = (
        children: List<int>.from(
          arguments[#childrenInTraversalOrder] as Iterable<int>,
        ),
        label: arguments[#label] as String,
      );
      return null;
    }
    if (invocation.memberName == #updateCustomAction) return null;
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    binding.nodes.addAll(changes);
    final reachable = <int>{};
    void visit(int id) {
      expect(reachable.add(id), isTrue, reason: '语义节点不能重复归属或成环：$id');
      expect(binding.nodes.containsKey(id), isTrue, reason: '缺失语义子节点：$id');
      for (final child in binding.nodes[id]!.children) {
        visit(child);
      }
    }

    if (binding.nodes.containsKey(0)) visit(0);
    for (final id in changes.keys) {
      expect(reachable.contains(id), isTrue, reason: '新提交节点必须连接根节点：$id');
    }
    binding.nodes.removeWhere((id, _) => !reachable.contains(id));
    binding.updates++;
    return ui.SemanticsUpdateBuilder().build();
  }
}

void main() {
  final binding = _ChatSemanticsBinding();
  testWidgets('open tooltip is removed before viewport and font reflow', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = ScrollController();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(tester.view.resetPhysicalSize);
    late StateSetter update;
    var scale = 1.0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    controller: controller,
                    child: ChatMessageList(
                      children: List.generate(
                        30,
                        (i) => SizedBox(
                          height: 100,
                          child: AppTooltip(
                            message: 'Resize details $i',
                            child: TextButton(
                              key: ValueKey('resize-target-$i'),
                              onPressed: () {},
                              child: Text('Item $i'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('resize-target-4'))),
      );
      await tester.pump(
        AppTooltip.waitDuration + const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resize details 4'), findsOneWidget);
      // 尺寸改变会让原锚点超出语义缓存范围，不依赖 ScrollPosition 的位移通知。
      final oldSize = tester.view.physicalSize;
      tester.view.physicalSize = Size(
        oldSize.width,
        100 * tester.view.devicePixelRatio,
      );
      await tester.pumpAndSettle();
      expect(find.text('Resize details 4'), findsNothing);
      tester.view.physicalSize = oldSize;
      await tester.pumpAndSettle();
      await mouse.moveTo(Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('resize-target-4'))),
      );
      await tester.pump(
        AppTooltip.waitDuration + const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resize details 4'), findsOneWidget);
      update(() => scale = 1.1);
      await tester.pumpAndSettle();
      expect(find.text('Resize details 4'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      try {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        controller.dispose();
        semantics.dispose();
      }
    }
  });

  testWidgets(
    'viewport semantics retains adjacent history and tooltip anchors',
    (tester) async {
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
                        120,
                        (i) => SizedBox(
                          height: 100,
                          child: Semantics(
                            container: true,
                            explicitChildNodes: true,
                            label: 'Message $i',
                            child: Row(
                              children: [
                                Text('Body $i'),
                                AppTooltip(
                                  message: 'Message details $i',
                                  child: TextButton(
                                    key: ValueKey('details-$i'),
                                    onPressed: () {},
                                    child: const Text('Details'),
                                  ),
                                ),
                              ],
                            ),
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
        List<String> messages() => binding.nodes.values
            .map((node) => node.label)
            .where(
              (label) =>
                  label.startsWith('Message ') &&
                  !label.startsWith('Message details'),
            )
            .toList();
        expect(messages(), contains('Message 0'));
        if (ChatMessageList.semanticsViewportEnabled) {
          expect(messages().length, lessThan(10));
          expect(messages(), isNot(contains('Message 119')));
        } else {
          expect(messages().length, 120);
        }
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: tester.getCenter(find.byKey(const ValueKey('details-0'))),
        );
        await tester.pump(
          AppTooltip.waitDuration + const Duration(milliseconds: 200),
        );
        await tester.pumpAndSettle();
        expect(find.text('Message details 0'), findsOneWidget);
        // 保持提示开启时滚动，检查被裁剪的锚点不会留下悬空浮层语义节点。
        controller.jumpTo(5050);
        await tester.pumpAndSettle();
        expect(messages(), contains('Message 50'));
        if (ChatMessageList.semanticsViewportEnabled) {
          expect(messages(), isNot(contains('Message 0')));
          expect(messages().length, lessThan(10));
        }
        await mouse.removePointer();
        await tester.pumpAndSettle();
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(messages(), contains('Message 119'));
        expect(controller.position.maxScrollExtent, 11800);
        expect(find.byType(AppTooltip), findsNWidgets(120));
        expect(binding.updates, greaterThan(3));
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          controller.dispose();
          semantics.dispose();
        }
      }
    },
  );
}
