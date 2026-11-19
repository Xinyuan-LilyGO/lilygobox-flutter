import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_message_list.dart';

void main() {
  testWidgets(
    'a cached message still paints rows revealed by outer scrolling',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final paints = <int>{};
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 400,
              height: 200,
              child: SingleChildScrollView(
                controller: scroll,
                child: RepaintBoundary(
                  child: ChatMessageList(
                    children: List.generate(
                      8,
                      (index) => _MessageProbe(
                        index: index,
                        height: 100,
                        onPaint: paints.add,
                        onHit: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      scroll.jumpTo(400);
      await tester.pump();
      expect(paints, containsAll([4, 5]));
    },
  );

  testWidgets(
    'cached horizontal code viewport includes rows exposed by vertical scroll alone',
    (tester) async {
      final vertical = ScrollController();
      final horizontal = ScrollController();
      addTearDown(vertical.dispose);
      addTearDown(horizontal.dispose);
      final paints = <int>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 400,
              height: 200,
              child: SingleChildScrollView(
                controller: vertical,
                child: SingleChildScrollView(
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 1200,
                    child: ChatMessageList(
                      children: List.generate(
                        100,
                        (index) => _MessageProbe(
                          index: index,
                          height: 100,
                          onPaint: paints.add,
                          onHit: (_) {},
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
      vertical.jumpTo(5050);
      await tester.pump();
      expect(paints, containsAll([50, 51, 52]));
      horizontal.jumpTo(500);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a thousand messages paint and hit test only visible entries', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final paints = <int>[];
    final hits = <int>[];
    const viewportKey = ValueKey('message-viewport');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            key: viewportKey,
            width: 400,
            height: 200,
            child: SingleChildScrollView(
              controller: controller,
              child: ChatMessageList(
                children: List.generate(
                  1000,
                  (index) => RepaintBoundary(
                    child: _MessageProbe(
                      index: index,
                      height: 100,
                      onPaint: paints.add,
                      onHit: hits.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(controller.position.maxScrollExtent, 99800);
    expect(find.byType(_MessageProbe), findsNWidgets(1000));
    expect(paints, [0, 1]);
    paints.clear();
    controller.jumpTo(5050);
    await tester.pump();
    expect(paints, [50, 51, 52]);
    await tester.tapAt(
      tester.getTopLeft(find.byKey(viewportKey)) + const Offset(40, 70),
    );
    expect(hits, isNotEmpty);
    expect(hits.toSet(), {51});
    expect(hits.length, lessThan(10));
    paints.clear();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(paints, [998, 999]);
    expect(controller.position.maxScrollExtent, 99800);
    paints.clear();
    controller.jumpTo(0);
    await tester.pump();
    expect(paints, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'message height changes refresh visible bounds and exact extent',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 200);
      addTearDown(controller.dispose);
      final paints = <int>[];
      var firstHeight = 100.0;
      late StateSetter update;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 400,
              height: 200,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return SingleChildScrollView(
                    controller: controller,
                    child: ChatMessageList(
                      children: List.generate(
                        100,
                        (index) => _MessageProbe(
                          index: index,
                          height: index == 0 ? firstHeight : 100,
                          onPaint: paints.add,
                          onHit: (_) {},
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(paints, [2, 3]);
      expect(controller.position.maxScrollExtent, 9800);
      paints.clear();
      update(() => firstHeight = 250);
      await tester.pump();
      expect(controller.offset, 200);
      expect(controller.position.maxScrollExtent, 9950);
      expect(paints, [0, 1, 2]);
      paints.clear();
      update(() => firstHeight = 0);
      await tester.pump();
      expect(controller.position.maxScrollExtent, 9700);
      expect(paints, [3, 4]);
      expect(tester.takeException(), isNull);
    },
  );
}

class _MessageProbe extends LeafRenderObjectWidget {
  const _MessageProbe({
    required this.index,
    required this.height,
    required this.onPaint,
    required this.onHit,
  });

  final int index;
  final double height;
  final ValueChanged<int> onPaint;
  final ValueChanged<int> onHit;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMessageProbe(
    index: index,
    height: height,
    onPaint: onPaint,
    onHit: onHit,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMessageProbe renderObject,
  ) {
    renderObject.height = height;
  }
}

class _RenderMessageProbe extends RenderBox {
  _RenderMessageProbe({
    required this.index,
    required this._height,
    required this.onPaint,
    required this.onHit,
  });

  final int index;
  final ValueChanged<int> onPaint;
  final ValueChanged<int> onHit;
  double _height;

  set height(double value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  @override
  void performLayout() => size = constraints.constrain(Size(400, _height));

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint(index);
    context.canvas.drawRect(
      offset & size,
      Paint()..color = const Color(0xff777777),
    );
  }

  @override
  bool hitTestSelf(Offset position) {
    onHit(index);
    return true;
  }
}
