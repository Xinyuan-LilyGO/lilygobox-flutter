import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_connection.dart';

void main() {
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
