import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/widgets.dart' show Matrix4, TransformationController;
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/domain/task_canvas_style.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_canvas_background.dart';

void main() {
  testWidgets('axes cross at scene zero through pan and zoom', (tester) async {
    final transform = TransformationController();
    addTearDown(transform.dispose);
    final sceneOrigin = ValueNotifier(Offset.zero);
    addTearDown(sceneOrigin.dispose);
    final painter = TaskCanvasAxesPainter(
      transform: transform,
      color: const Color(0xffffffff),
      sceneOrigin: sceneOrigin,
    );
    void paint(Canvas canvas) => painter.paint(canvas, const Size(100, 100));
    for (final (origin, scale) in [
      (const Offset(17, 27), .25),
      (const Offset(72, 60), 1.8),
      (const Offset(-20, 35), 1.0),
    ]) {
      transform.value =
          Matrix4.translationValues(origin.dx, origin.dy, 0) *
          Matrix4.diagonal3Values(scale, scale, 1);
      expect(
        paint,
        paints..line(p1: Offset(0, origin.dy), p2: Offset(100, origin.dy)),
      );
      if (origin.dx >= 0) {
        expect(
          paint,
          paints
            ..line()
            ..line(p1: Offset(origin.dx, 0), p2: Offset(origin.dx, 100))
            ..circle(x: origin.dx, y: origin.dy),
        );
      } else {
        expect(paint, isNot(paints..circle()));
      }
      expect(paint, paintsExactlyCountTimes(#drawParagraph, 0));
    }
  });
  testWidgets('backgrounds keep their origin, spacing and style at each zoom', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final pattern = TaskCanvasBackgroundPattern();
      for (final scale in [.01, .25, .5, 1.0]) {
        for (final style in AiTaskCanvasStyle.values) {
          final recorder = PictureRecorder();
          final canvas = Canvas(recorder)
            ..translate(36.5, 36.5)
            ..scale(scale);
          pattern.paint(
            canvas,
            Rect.fromCenter(
              center: Offset.zero,
              width: 74 / scale,
              height: 74 / scale,
            ),
            style: style,
            color: const Color(0xFFFFFFFF),
            scale: scale,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(74, 74);
          final bytes = (await image.toByteData(
            format: ImageByteFormat.rawRgba,
          ))!;
          int alpha(int column, int row) =>
              bytes.getUint8((row * image.width + column) * 4 + 3);
          final step = (TaskCanvasBackgroundPattern.spacingFor(scale) * scale)
              .round();
          final ink = style == AiTaskCanvasStyle.plain
              ? equals(0)
              : greaterThan(30);
          for (final column in [36 - step, 36, 36 + step]) {
            expect(alpha(column, 36), ink, reason: '$style at $scale');
          }
          expect(alpha(36 + step ~/ 2, 36 + step ~/ 2), 0);
          expect(
            alpha(36, 36 + step ~/ 2),
            style == AiTaskCanvasStyle.grid ? greaterThan(25) : equals(0),
          );
          image.dispose();
          picture.dispose();
        }
      }
    });
  });
}
