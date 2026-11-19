import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show Listenable, ValueListenable;
import 'package:flutter/widgets.dart'
    show CustomPainter, MatrixUtils, TransformationController;

import '../../domain/task_canvas_style.dart';

class TaskCanvasAxesPainter extends CustomPainter {
  TaskCanvasAxesPainter({
    required this.transform,
    required this.color,
    required this.sceneOrigin,
  }) : super(repaint: Listenable.merge([transform, sceneOrigin]));

  final TransformationController transform;
  final Color color;
  final ValueListenable<Offset> sceneOrigin;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = MatrixUtils.transformPoint(
      transform.value,
      sceneOrigin.value,
    );
    final horizontal = origin.dy >= 0 && origin.dy < size.height;
    final vertical = origin.dx >= 0 && origin.dx < size.width;
    if (!horizontal && !vertical) return;
    final paint = Paint()
      ..color = color.withValues(alpha: .32)
      ..strokeWidth = 1;
    if (horizontal) {
      canvas.drawLine(
        Offset(0, origin.dy),
        Offset(size.width, origin.dy),
        paint,
      );
    }
    if (vertical) {
      canvas.drawLine(
        Offset(origin.dx, 0),
        Offset(origin.dx, size.height),
        paint,
      );
    }
    if (!horizontal || !vertical) return;
    canvas.drawCircle(origin, 2.5, paint..color = color.withValues(alpha: .60));
  }

  @override
  bool shouldRepaint(TaskCanvasAxesPainter oldDelegate) =>
      transform != oldDelegate.transform ||
      color != oldDelegate.color ||
      sceneOrigin != oldDelegate.sceneOrigin;
}

class TaskCanvasBackgroundPattern {
  static double spacingFor(double scale) {
    var spacing = scale < .35
        ? 96.0
        : scale < .65
        ? 48.0
        : 24.0;
    while (spacing * scale.clamp(taskCanvasMinScale, taskCanvasMaxScale) < 16) {
      spacing *= 2;
    }
    return spacing;
  }

  (AiTaskCanvasStyle, int, int, double)? _key;
  Float32List _points = Float32List(0);

  void paint(
    Canvas canvas,
    Rect bounds, {
    required AiTaskCanvasStyle style,
    required Color color,
    required double scale,
  }) {
    if (style == AiTaskCanvasStyle.plain || bounds.isEmpty) return;
    final spacing = spacingFor(scale);
    final columns = (bounds.width / spacing).ceil() + 2;
    final rows = (bounds.height / spacing).ceil() + 2;
    final key = (style, columns, rows, spacing);
    final dots = style == AiTaskCanvasStyle.dots;
    if (_key != key) {
      _key = key;
      final points = _points = Float32List(
        dots ? columns * rows * 2 : (columns + rows) * 4,
      );
      var index = 0;
      for (var column = 0; column < columns; column++) {
        if (dots) {
          for (var row = 0; row < rows; row++) {
            points[index++] = column * spacing;
            points[index++] = row * spacing;
          }
        } else {
          points[index++] = column * spacing;
          points[index++] = 0;
          points[index++] = column * spacing;
          points[index++] = rows * spacing;
        }
      }
      if (!dots) {
        for (var row = 0; row < rows; row++) {
          points[index++] = 0;
          points[index++] = row * spacing;
          points[index++] = columns * spacing;
          points[index++] = row * spacing;
        }
      }
    }
    canvas.save();
    canvas.clipRect(bounds);
    canvas.translate(
      (bounds.left / spacing).floor() * spacing,
      (bounds.top / spacing).floor() * spacing,
    );
    canvas.drawRawPoints(
      dots ? PointMode.points : PointMode.lines,
      _points,
      Paint()
        ..color = color
        ..strokeWidth = (dots ? 2 : .7) / scale
        ..strokeCap = dots ? StrokeCap.round : StrokeCap.butt,
    );
    canvas.restore();
  }
}
