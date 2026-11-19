import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_connection.dart';

void main() {
  test(
    'clipped polyline follows the actual curve within 0.3 physical pixels',
    () {
      const start = Offset.zero;
      const first = Offset(160, 0);
      const second = Offset(440, 200);
      const end = Offset(600, 200);
      const bounds = Rect.fromLTRB(10, 0, 500, 200);
      final forward = TaskTopologyConnection.preview(start, end);
      final reverse = TaskTopologyConnection.preview(end, start);
      for (final scale in [.3125, .875, 1.25, 4.5]) {
        final points = forward.clippedPolyline(bounds, .3 / scale)!;
        final reversed = reverse.clippedPolyline(bounds, .3 / scale)!;
        expect(points.first.dx, closeTo(bounds.left, 1e-8));
        expect(points.last.dx, closeTo(bounds.right, 1e-8));
        expect(reversed, hasLength(points.length));
        for (var index = 0; index < points.length; index++) {
          expect(
            (points[index] - reversed[points.length - index - 1]).distance,
            lessThan(1e-8),
          );
        }
        for (var index = 0; index <= 512; index++) {
          final fraction = index / 512;
          final complement = 1 - fraction;
          final sample =
              start * (complement * complement * complement) +
              first * (3 * complement * complement * fraction) +
              second * (3 * complement * fraction * fraction) +
              end * (fraction * fraction * fraction);
          if (!bounds.contains(sample)) continue;
          var nearest = double.infinity;
          for (var segment = 1; segment < points.length; segment++) {
            final chord = points[segment] - points[segment - 1];
            final relative = sample - points[segment - 1];
            final projection =
                ((relative.dx * chord.dx + relative.dy * chord.dy) /
                        chord.distanceSquared)
                    .clamp(0.0, 1.0);
            nearest = math.min(
              nearest,
              (relative - chord * projection).distance,
            );
          }
          expect(nearest * scale, lessThanOrEqualTo(.300001));
        }
      }
      expect(
        forward.clippedPolyline(bounds.shift(const Offset(1000, 0)), .3),
        isNull,
      );
      expect(
        TaskTopologyConnection.preview(
          start,
          start,
        ).clippedPolyline(bounds.inflate(20), .3),
        [start, start],
      );
    },
  );

  test(
    'drag preview stays monotonic in every direction and mirrors on reversal',
    () {
      const start = Offset(500, 400);
      for (final delta in [
        const Offset(600, 400),
        const Offset(-600, -400),
        const Offset(-600, 400),
        const Offset(600, -400),
        const Offset(40, 600),
        const Offset(-40, -600),
        const Offset(0, 300),
        const Offset(-300, 0),
        const Offset(.01, -.01),
      ]) {
        final end = start + delta;
        final route = TaskTopologyConnection.preview(start, end);
        final reverse = TaskTopologyConnection.preview(end, start);
        final metric = route.path.computeMetrics().first;
        final reversedMetric = reverse.path.computeMetrics().first;
        expect(metric.length, closeTo(reversedMetric.length, .1));
        var previous = start;
        for (var step = 1; step <= 100; step++) {
          final point = metric
              .getTangentForOffset(metric.length * step / 100)!
              .position;
          expect(
            (point.dx - previous.dx) * delta.dx,
            greaterThanOrEqualTo(-.01),
          );
          expect(
            (point.dy - previous.dy) * delta.dy,
            greaterThanOrEqualTo(-.01),
          );
          final mirror = reversedMetric
              .getTangentForOffset(reversedMetric.length * (1 - step / 100))!
              .position;
          expect((point - mirror).distance, lessThan(.6));
          previous = point;
        }
        expect(route.start, start);
        expect(route.end, end);
      }
      expect(
        TaskTopologyConnection.preview(start, start).path.getBounds().isFinite,
        isTrue,
      );
    },
  );

  group('TaskTopologyConnection', () {
    const source = Rect.fromLTWH(400, 300, 252, 164);
    for (final entry in <String, Rect>{
      'right': const Rect.fromLTWH(850, 320, 252, 164),
      'left': const Rect.fromLTWH(50, 320, 252, 164),
      'below': const Rect.fromLTWH(420, 700, 252, 164),
      'above': const Rect.fromLTWH(420, 0, 252, 164),
    }.entries) {
      test('should route toward the ${entry.key} card without looping', () {
        final route = TaskTopologyConnection.between(source, entry.value);
        final expectedStart = switch (entry.key) {
          'right' => source.centerRight,
          'left' => source.centerLeft,
          'below' => source.bottomCenter,
          _ => source.topCenter,
        };
        final expectedEnd = switch (entry.key) {
          'right' => entry.value.centerLeft,
          'left' => entry.value.centerRight,
          'below' => entry.value.topCenter,
          _ => entry.value.bottomCenter,
        };
        expect(route.start, expectedStart);
        expect(route.end, expectedEnd);
        final metric = route.path.computeMetrics().single;
        final vector = route.end - route.start;
        var previous = -1.0;
        for (var step = 1; step < 30; step++) {
          final point = metric
              .getTangentForOffset(metric.length * step / 30)!
              .position;
          expect(source.deflate(.1).contains(point), isFalse);
          expect(entry.value.deflate(.1).contains(point), isFalse);
          final progress =
              (point.dx - route.start.dx) * vector.dx +
              (point.dy - route.start.dy) * vector.dy;
          expect(progress, greaterThanOrEqualTo(previous));
          previous = progress;
        }
      });
    }
    test('should use vertical edges for a mostly vertical diagonal', () {
      const target = Rect.fromLTWH(600, 800, 252, 164);
      final route = TaskTopologyConnection.between(source, target);
      expect(route.start, source.bottomCenter);
      expect(route.end, target.topCenter);
    });
    test('should keep a short gap inside the endpoint bounds', () {
      final route = TaskTopologyConnection.between(
        source,
        const Rect.fromLTWH(655, 310, 252, 164),
      );
      final bounds = route.path.getBounds();
      expect(bounds.left, greaterThanOrEqualTo(route.start.dx));
      expect(bounds.right, lessThanOrEqualTo(route.end.dx));
    });
    test('should select a curved wire within its stroke tolerance', () {
      final route = TaskTopologyConnection.between(
        source,
        const Rect.fromLTWH(850, 700, 252, 164),
      );
      final metric = route.path.computeMetrics().single;
      final middle = metric.getTangentForOffset(metric.length / 2)!.position;
      expect(route.hitTest(middle), isTrue);
      expect(route.hitTest(middle + const Offset(2, 2)), isTrue);
      expect(route.hitTest(middle + const Offset(50, -50)), isFalse);
      expect(route.hitTest(source.center), isFalse);
      expect(route.hitTest(middle, tolerance: 0), isFalse);
    });
    test('marquee selects a narrow crossing with both endpoints outside', () {
      final route = TaskTopologyConnection.between(
        source,
        const Rect.fromLTWH(850, 300, 252, 164),
      );
      const selection = Rect.fromLTWH(750, 350, .01, 64);
      expect(selection.contains(route.start), isFalse);
      expect(selection.contains(route.end), isFalse);
      expect(route.intersectsRect(selection), isTrue);
      expect(
        route.intersectsRect(const Rect.fromLTWH(750, 400, 5, 20)),
        isFalse,
      );
    });

    test(
      'painting keeps whole paths and excludes bounding-box-only overlaps',
      () {
        final route = TaskTopologyConnection.preview(
          Offset.zero,
          const Offset(1000, 500),
        );
        const whole = Rect.fromLTRB(0, 0, 1000, 500);
        expect(route.clippedPath(whole), same(route.path));
        const corner = Rect.fromLTWH(1, 490, 5, 5);
        expect(route.path.getBounds().overlaps(corner), isTrue);
        expect(route.clippedPath(corner), isNull);
        expect(route.clippedPath(const Rect.fromLTWH(-50, 0, 1, 25)), isNull);
        expect(
          route.clippedPath(const Rect.fromLTWH(double.nan, 0, 2, 2)),
          isNull,
        );
      },
    );

    test('clipping retains the exact cubic segment in both directions', () {
      const bounds = Rect.fromLTRB(201.25, 78.125, 798.75, 421.875);
      for (final reversed in [false, true]) {
        const origin = Offset.zero;
        const end = Offset(1000, 500);
        final route = TaskTopologyConnection.preview(
          reversed ? end : origin,
          reversed ? origin : end,
        );
        const quarter = Offset(201.25, 78.125);
        const first = Offset(378.75, 171.875);
        const second = Offset(621.25, 328.125);
        const threeQuarters = Offset(798.75, 421.875);
        final startPoint = reversed ? threeQuarters : quarter;
        final endPoint = reversed ? quarter : threeQuarters;
        final firstControl = reversed ? second : first;
        final secondControl = reversed ? first : second;
        final reference = Path()
          ..moveTo(startPoint.dx, startPoint.dy)
          ..cubicTo(
            firstControl.dx,
            firstControl.dy,
            secondControl.dx,
            secondControl.dy,
            endPoint.dx,
            endPoint.dy,
          );
        final clipped = route.clippedPath(bounds)!.computeMetrics().single;
        final expected = reference.computeMetrics().single;
        expect(clipped.length, closeTo(expected.length, .01));
        for (var step = 0; step <= 16; step++) {
          final actualTangent = clipped.getTangentForOffset(
            clipped.length * step / 16,
          )!;
          final expectedTangent = expected.getTangentForOffset(
            expected.length * step / 16,
          )!;
          expect(
            (actualTangent.position - expectedTangent.position).distance,
            lessThan(.01),
          );
          expect(
            (actualTangent.vector - expectedTangent.vector).distance,
            lessThan(.001),
          );
        }
      }
    });

    test('axis-aligned clipping keeps a single straight visible segment', () {
      final route = TaskTopologyConnection.preview(
        const Offset(300, 20),
        const Offset(-100, 20),
      );
      const bounds = Rect.fromLTRB(-10, 20, 100, 30);
      final clipped = route.clippedPath(bounds)!.computeMetrics().single;
      expect(clipped.length, closeTo(110, .01));
      expect(clipped.getTangentForOffset(0)!.position, const Offset(100, 20));
      expect(
        clipped.getTangentForOffset(clipped.length)!.position,
        const Offset(-10, 20),
      );
      expect(route.clippedPath(bounds.translate(0, .1)), isNull);
    });

    test(
      'marquee tests the curve instead of its bounds in every direction',
      () {
        for (final target in [
          const Rect.fromLTWH(850, 700, 252, 164),
          const Rect.fromLTWH(-50, -100, 252, 164),
          const Rect.fromLTWH(700, 850, 252, 164),
          const Rect.fromLTWH(50, -500, 252, 164),
        ]) {
          final route = TaskTopologyConnection.between(source, target);
          final bounds = route.path.getBounds();
          final corner = Rect.fromLTWH(
            bounds.left + 1,
            bounds.bottom - 3,
            2,
            2,
          );
          expect(bounds.overlaps(corner), isTrue);
          expect(route.intersectsRect(corner), isFalse);
          final middle = (route.start + route.end) / 2;
          expect(
            route.intersectsRect(
              Rect.fromCenter(center: middle, width: .01, height: .01),
            ),
            isTrue,
          );
        }
      },
    );

    test(
      'marquee includes a boundary touch and rejects invalid rectangles',
      () {
        final route = TaskTopologyConnection.between(
          source,
          const Rect.fromLTWH(850, 300, 252, 164),
        );
        final touch = Rect.fromLTWH(700, route.start.dy, 10, 10);
        expect(route.intersectsRect(touch), isTrue);
        expect(route.intersectsRect(touch.translate(0, .01)), isFalse);
        expect(
          route.intersectsRect(const Rect.fromLTWH(700, 300, -1, 2)),
          isFalse,
        );
        expect(
          route.intersectsRect(const Rect.fromLTWH(double.nan, 0, 2, 2)),
          isFalse,
        );
      },
    );
  });
}
