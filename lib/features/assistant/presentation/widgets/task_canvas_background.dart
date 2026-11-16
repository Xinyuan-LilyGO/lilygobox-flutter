/*
 * @Description: 绘制可选择的点阵和网格画布背景，缩放时保持线条和点的屏幕尺寸。
 */
import 'dart:typed_data';
import 'dart:ui';

import '../../domain/task_canvas_style.dart';

void paintTaskCanvasBackground(
  Canvas canvas,
  Size size, {
  required AiTaskCanvasStyle style,
  required Color color,
  double scale = 1,
}) {
  if (style == AiTaskCanvasStyle.plain) return;
  final zoom = scale.clamp(.25, 1.8);
  const spacing = 24.0;
  final paint = Paint()
    ..color = color
    ..strokeWidth = .7 / zoom;
  if (style == AiTaskCanvasStyle.grid) {
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    return;
  }
  final columns = (size.width / spacing).ceil();
  final rows = (size.height / spacing).ceil();
  final points = Float32List(columns * rows * 2);
  var index = 0;
  for (var x = 0; x < columns; x++) {
    for (var y = 0; y < rows; y++) {
      points[index++] = x * spacing;
      points[index++] = y * spacing;
    }
  }
  paint
    ..strokeWidth = 2 / zoom
    ..strokeCap = StrokeCap.round;
  canvas.drawRawPoints(PointMode.points, points, paint);
}
