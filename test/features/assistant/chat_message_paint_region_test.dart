import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_message_paint_region.dart';

void main() {
  testWidgets('offscreen messages keep exact heights but skip painting', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final paints = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: List.generate(
                  100,
                  (index) => ChatMessagePaintRegion(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: const Size(400, 100),
                        painter: _PaintCounter(() => paints.add(index)),
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
    expect(controller.position.maxScrollExtent, 9800);
    expect(paints, [0, 1]);
    paints.clear();
    controller.jumpTo(5050);
    await tester.pump();
    expect(paints, [50, 51, 52]);
    expect(controller.position.maxScrollExtent, 9800);
    paints.clear();
    controller.jumpTo(0);
    await tester.pump();
    // Previously visible messages reuse their clean repaint layers.
    expect(paints, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _PaintCounter extends CustomPainter {
  _PaintCounter(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff777777),
    );
  }

  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}
