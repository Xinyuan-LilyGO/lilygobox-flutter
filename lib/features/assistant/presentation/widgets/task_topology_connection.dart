/*
 * @Description: 根据智能体卡片相对位置选择连接边，避免固定端点造成曲线回绕。
 */
import 'dart:math' as math;
import 'dart:ui';

/// 仅描述两张卡片的连接几何，不改变智能体归属或通信方向。
class TaskTopologyConnection {
  const TaskTopologyConnection._(
    this.start,
    this.end,
    this._first,
    this._second,
    this.path,
  );

  final Offset start;
  final Offset end;
  final Path path;
  final Offset _first;
  final Offset _second;

  /// 连线没有填充区域，以可缩放的笔划容差检测点击和切断目标。
  bool hitTest(Offset point, {double tolerance = 8}) {
    if (tolerance <= 0 ||
        !tolerance.isFinite ||
        !path.getBounds().inflate(tolerance).contains(point)) {
      return false;
    }
    for (final metric in path.computeMetrics()) {
      final steps = math.max(1, (metric.length / 8).ceil());
      var previous = metric.getTangentForOffset(0)?.position ?? start;
      for (var index = 1; index <= steps; index++) {
        final next =
            metric
                .getTangentForOffset(metric.length * index / steps)
                ?.position ??
            end;
        final segment = next - previous;
        final lengthSquared = segment.distanceSquared;
        final projection = lengthSquared == 0
            ? 0.0
            : (((point - previous).dx * segment.dx +
                          (point - previous).dy * segment.dy) /
                      lengthSquared)
                  .clamp(0.0, 1.0);
        if ((point - (previous + segment * projection)).distance <= tolerance) {
          return true;
        }
        previous = next;
      }
    }
    return false;
  }

  /// Select actual curve crossings, including a touch at the selection boundary.
  /// The router keeps both coordinates monotonic, so each axis contributes one
  /// parameter interval. Their intersection avoids bounding-box false positives
  /// and does not miss narrow rectangles between sampled points.
  bool intersectsRect(Rect rect) => _parameterRange(rect) != null;

  Path? clippedPath(Rect bounds) {
    final controls = _clippedControls(bounds);
    if (controls == null) return null;
    final (from, first, second, to) = controls;
    if (from == start && to == end) return path;
    return Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(first.dx, first.dy, second.dx, second.dy, to.dx, to.dy);
  }

  List<Offset>? clippedPolyline(Rect bounds, double tolerance) {
    assert(tolerance.isFinite && tolerance > 0);
    final controls = _clippedControls(bounds);
    if (controls == null) return null;
    final points = [controls.$1];
    final toleranceSquared = tolerance * tolerance;
    void subdivide(Offset from, Offset first, Offset second, Offset to) {
      final chord = to - from;
      final lengthSquared = chord.distanceSquared;
      bool nearChord(Offset point) {
        final offset = point - from;
        final cross = chord.dx * offset.dy - chord.dy * offset.dx;
        return cross * cross <= toleranceSquared * lengthSquared;
      }

      if (nearChord(first) && nearChord(second)) {
        points.add(to);
        return;
      }
      final left = (from + first) * .5;
      final middle = (first + second) * .5;
      final right = (second + to) * .5;
      final leftBend = (left + middle) * .5;
      final rightBend = (middle + right) * .5;
      final split = (leftBend + rightBend) * .5;
      if (split == from || split == to) {
        points.add(to);
        return;
      }
      subdivide(from, left, leftBend, split);
      subdivide(split, rightBend, right, to);
    }

    subdivide(controls.$1, controls.$2, controls.$3, controls.$4);
    return points;
  }

  (Offset, Offset, Offset, Offset)? _clippedControls(Rect bounds) {
    final range = _parameterRange(bounds);
    if (range == null) return null;
    final (entry, exit) = range;
    if (entry == 0 && exit == 1) return (start, _first, _second, end);
    (Offset, Offset) pointAndTangent(double parameter) {
      final first = Offset.lerp(start, _first, parameter)!;
      final middle = Offset.lerp(_first, _second, parameter)!;
      final last = Offset.lerp(_second, end, parameter)!;
      final left = Offset.lerp(first, middle, parameter)!;
      final right = Offset.lerp(middle, last, parameter)!;
      return (Offset.lerp(left, right, parameter)!, right - left);
    }

    final span = exit - entry;
    final (from, startTangent) = pointAndTangent(entry);
    final (to, endTangent) = pointAndTangent(exit);
    final first = from + startTangent * span;
    final second = to - endTangent * span;
    return (from, first, second, to);
  }

  (double, double)? _parameterRange(Rect rect) {
    if (!rect.isFinite || rect.width < 0 || rect.height < 0) return null;
    var lower = 0.0;
    var upper = 1.0;
    for (final axis in [
      (start.dx, _first.dx, _second.dx, end.dx, rect.left, rect.right),
      (start.dy, _first.dy, _second.dy, end.dy, rect.top, rect.bottom),
    ]) {
      final (a, b, c, d, minimum, maximum) = axis;
      final ascending = d >= a;
      if (math.max(a, d) < minimum || math.min(a, d) > maximum) {
        return null;
      }
      if (a == d) continue;
      double parameterAt(double coordinate) {
        var left = 0.0;
        var right = 1.0;
        for (var iteration = 0; iteration < 48; iteration++) {
          final t = (left + right) / 2;
          final u = 1 - t;
          final position =
              u * u * u * a +
              3 * u * u * t * b +
              3 * u * t * t * c +
              t * t * t * d;
          if ((position < coordinate) == ascending) {
            left = t;
          } else {
            right = t;
          }
        }
        return (left + right) / 2;
      }

      if (ascending ? a < minimum : a > maximum) {
        lower = math.max(lower, parameterAt(ascending ? minimum : maximum));
      }
      if (ascending ? d > maximum : d < minimum) {
        upper = math.min(upper, parameterAt(ascending ? maximum : minimum));
      }
      if (lower > upper + 1e-12) return null;
    }
    return (lower, math.max(lower, upper));
  }

  /// Drag previews follow the pointer in either direction without overshooting.
  factory TaskTopologyConnection.preview(Offset start, Offset end) {
    final delta = end - start;
    final horizontal = delta.dx.abs() >= delta.dy.abs();
    final distance = horizontal ? delta.dx : delta.dy;
    final bend = math.min(160.0, distance.abs() * .4) * distance.sign;
    final tangent = horizontal ? Offset(bend, 0) : Offset(0, bend);
    final first = start + tangent;
    final second = end - tangent;
    return TaskTopologyConnection._(
      start,
      end,
      first,
      second,
      Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(first.dx, first.dy, second.dx, second.dy, end.dx, end.dy),
    );
  }

  factory TaskTopologyConnection.between(Rect source, Rect target) {
    final delta = target.center - source.center;
    final horizontalGap = delta.dx.abs() - (source.width + target.width) / 2;
    final verticalGap = delta.dy.abs() - (source.height + target.height) / 2;
    // Keep left/right sockets whenever the cards have a horizontal corridor.
    // Vertical distance alone must not flip outer branches onto top/bottom
    // sockets. Geometry depends exclusively on the two endpoint cards.
    final horizontal =
        horizontalGap > 0 ||
        (verticalGap <= 0 &&
            delta.dx.abs() / math.max(1, source.width + target.width) >=
                delta.dy.abs() / math.max(1, source.height + target.height));
    final direction = horizontal
        ? (delta.dx >= 0 ? 1.0 : -1.0)
        : (delta.dy >= 0 ? 1.0 : -1.0);
    final start = horizontal
        ? Offset(direction > 0 ? source.right : source.left, source.center.dy)
        : Offset(source.center.dx, direction > 0 ? source.bottom : source.top);
    final end = horizontal
        ? Offset(direction > 0 ? target.left : target.right, target.center.dy)
        : Offset(target.center.dx, direction > 0 ? target.top : target.bottom);
    final gap = math.max(
      0.0,
      direction * (horizontal ? end.dx - start.dx : end.dy - start.dy),
    );
    final bend = math.min(160.0, gap * .45);
    final tangent = horizontal
        ? Offset(direction * bend, 0)
        : Offset(0, direction * bend);
    final first = start + tangent;
    final second = end - tangent;
    return TaskTopologyConnection._(
      start,
      end,
      first,
      second,
      Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(first.dx, first.dy, second.dx, second.dy, end.dx, end.dy),
    );
  }
}
