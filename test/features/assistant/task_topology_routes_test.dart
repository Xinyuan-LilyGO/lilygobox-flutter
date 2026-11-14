import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_routes.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_connection.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace.dart';

void main() {
  test(
    'moving adding deleting unrelated cards and wires never changes a curve',
    () {
      const source = Rect.fromLTWH(0, 300, 252, 144);
      const target = Rect.fromLTWH(700, 300, 252, 144);
      const edge = AiTaskConnection(
        id: 'ab',
        fromId: 'a',
        toId: 'b',
        isHierarchy: true,
      );
      final baseline = TaskTopologyConnection.between(
        source,
        target,
      ).path.computeMetrics().single;
      for (final obstacle in [
        const Rect.fromLTWH(350, 280, 252, 144),
        const Rect.fromLTWH(350, -400, 252, 144),
        source.translate(10, 10),
        target.translate(-10, -10),
      ]) {
        for (final otherConnected in [false, true]) {
          final nodes = {'a': source, 'b': target, 'other': obstacle};
          final routes = buildTaskTopologyRoutes(
            nodes: nodes,
            connections: [
              edge,
              if (otherConnected)
                const AiTaskConnection(
                  id: 'extra',
                  fromId: 'a',
                  toId: 'other',
                  isHierarchy: true,
                ),
            ],
          );
          final metric = routes['ab']!.path.computeMetrics().single;
          expect(metric.length, closeTo(baseline.length, .001));
          for (var i = 0; i <= 50; i++) {
            final original = baseline.getTangentForOffset(
              baseline.length * i / 50,
            )!;
            final actual = metric.getTangentForOffset(metric.length * i / 50)!;
            expect(
              (actual.position - original.position).distance,
              lessThan(.001),
            );
            expect(routes['ab']!.hitTest(actual.position), isTrue);
            expect(
              routes['ab']!.intersectsRect(
                Rect.fromCenter(center: actual.position, width: .1, height: .1),
              ),
              isTrue,
            );
          }
        }
      }
      final moved = buildTaskTopologyRoutes(
        nodes: {'a': source, 'b': target.translate(0, 120)},
        connections: [edge],
      )['ab']!;
      expect(moved.end, target.translate(0, 120).centerLeft);
      expect(moved.end, isNot(target.centerLeft));
    },
  );
  for (final count in [5, 10, 20]) {
    for (final direction in [-1.0, 1.0]) {
      test(
        '$count shared branches keep single curves in direction $direction',
        () {
          final center = (count - 1) * 208 / 2;
          final nodes = <String, Rect>{
            'root': Rect.fromLTWH(600, center, 252, 144),
            for (var i = 0; i < count; i++)
              'child$i': Rect.fromLTWH(
                600 + direction * 470,
                i * 208,
                252,
                144,
              ),
          };
          final edges = [
            for (var i = 0; i < count; i++)
              AiTaskConnection(
                id: '$i',
                fromId: i.isEven ? 'root' : 'child$i',
                toId: i.isEven ? 'child$i' : 'root',
                isHierarchy: true,
              ),
          ];
          final routes = buildTaskTopologyRoutes(
            nodes: nodes,
            connections: edges,
          );
          for (final edge in edges) {
            final actual = routes[edge.id]!.path.computeMetrics().single;
            final direct = TaskTopologyConnection.between(
              nodes[edge.fromId]!,
              nodes[edge.toId]!,
            );
            final expected = direct.path.computeMetrics().single;
            expect(actual.length, closeTo(expected.length, .001));
            for (var step = 0; step <= 30; step++) {
              final at = actual.getTangentForOffset(actual.length * step / 30)!;
              final original = expected.getTangentForOffset(
                expected.length * step / 30,
              )!;
              expect(
                (at.position - original.position).distance,
                lessThan(.001),
                reason: 'A shared socket must not add a lane kink',
              );
            }
          }
        },
      );
    }
  }
  test('five vertically spread children keep the same smooth side sockets', () {
    for (final direction in [-1.0, 1.0]) {
      final nodes = <String, Rect>{
        'source': const Rect.fromLTWH(500, 400, 252, 164),
        for (var i = 0; i < 5; i++)
          'child$i': Rect.fromLTWH(500 + direction * 470, i * 230, 252, 164),
      };
      final edges = [
        for (var i = 0; i < 5; i++)
          AiTaskConnection(
            id: 'edge$i',
            fromId: 'source',
            toId: 'child$i',
            isHierarchy: true,
          ),
      ];
      final routes = buildTaskTopologyRoutes(nodes: nodes, connections: edges);
      for (final edge in edges) {
        final route = routes[edge.id]!;
        final source = nodes[edge.fromId]!;
        final target = nodes[edge.toId]!;
        expect(
          route.start,
          direction > 0 ? source.centerRight : source.centerLeft,
        );
        expect(
          route.end,
          direction > 0 ? target.centerLeft : target.centerRight,
        );
        final metric = route.path.computeMetrics().single;
        for (var step = 1; step < 100; step++) {
          final tangent = metric.getTangentForOffset(
            metric.length * step / 100,
          )!;
          expect(
            tangent.vector.dx * direction,
            greaterThan(0),
            reason: 'Side-by-side branches must not turn into vertical rails',
          );
          for (final node in nodes.values) {
            expect(node.deflate(.1).contains(tangent.position), isFalse);
          }
        }
      }
    }
  });
  test(
    'overlapping copied endpoints keep curved routes instead of false obstacle stairs',
    () {
      const nodes = {
        'source': Rect.fromLTWH(100, 240, 380, 250),
        'top': Rect.fromLTWH(810, 100, 380, 215),
        'bottom': Rect.fromLTWH(810, 414, 380, 250),
        'copy': Rect.fromLTWH(835, 427, 380, 245),
      };
      const edges = [
        AiTaskConnection(
          id: 'top',
          fromId: 'source',
          toId: 'top',
          isHierarchy: true,
        ),
        AiTaskConnection(
          id: 'bottom',
          fromId: 'source',
          toId: 'bottom',
          isHierarchy: true,
        ),
        AiTaskConnection(
          id: 'copy',
          fromId: 'source',
          toId: 'copy',
          isHierarchy: true,
        ),
      ];
      final routes = buildTaskTopologyRoutes(nodes: nodes, connections: edges);
      for (final edge in edges) {
        final route = routes[edge.id]!;
        final metric = route.path.computeMetrics().single;
        // A curve between these sockets stays within their vertical interval.
        final bounds = route.path.getBounds();
        expect(
          bounds.top,
          greaterThanOrEqualTo(
            route.start.dy < route.end.dy
                ? route.start.dy - 1
                : route.end.dy - 1,
          ),
        );
        expect(
          bounds.bottom,
          lessThanOrEqualTo(
            route.start.dy > route.end.dy
                ? route.start.dy + 1
                : route.end.dy + 1,
          ),
        );
        var previous = metric.getTangentForOffset(0)!.vector;
        for (var d = .5; d < metric.length; d += .5) {
          final tangent = metric.getTangentForOffset(d)!;
          expect((tangent.vector - previous).distance, lessThan(.15));
          previous = tangent.vector;
          if (d > 30 && d < metric.length - 30) {
            expect(route.hitTest(tangent.position), isTrue);
            expect(
              route.intersectsRect(
                Rect.fromCenter(
                  center: tangent.position,
                  width: .01,
                  height: .01,
                ),
              ),
              isTrue,
            );
          }
        }
      }
    },
  );

  test(
    'coincident endpoints keep their natural path without global lane offsets',
    () {
      const nodes = {
        'a': Rect.fromLTWH(0, 0, 100, 80),
        'b': Rect.fromLTWH(0, 0, 100, 80),
        'target': Rect.fromLTWH(500, 0, 100, 80),
      };
      const connections = [
        AiTaskConnection(
          id: 'a-target',
          fromId: 'a',
          toId: 'target',
          isHierarchy: false,
        ),
        AiTaskConnection(
          id: 'b-target',
          fromId: 'b',
          toId: 'target',
          isHierarchy: false,
        ),
      ];
      final routes = buildTaskTopologyRoutes(
        nodes: nodes,
        connections: connections,
      );
      final first = routes['a-target']!;
      final second = routes['b-target']!;
      final metric = first.path.computeMetrics().first;
      final point = metric.getTangentForOffset(metric.length / 2)!.position;
      expect(first.hitTest(point), isTrue);
      expect(second.hitTest(point), isTrue);
      expect(first.start, second.start);
      expect(first.end, second.end);
    },
  );
  test(
    'drawn and selectable routes pass under intervening cards and stay deterministic',
    () {
      const nodes = {
        'a': Rect.fromLTWH(0, 0, 100, 80),
        'middle': Rect.fromLTWH(250, 0, 100, 80),
        'b': Rect.fromLTWH(500, 0, 100, 80),
      };
      const connections = [
        AiTaskConnection(id: 'ab', fromId: 'a', toId: 'b', isHierarchy: false),
        AiTaskConnection(
          id: 'am',
          fromId: 'a',
          toId: 'middle',
          isHierarchy: true,
        ),
        AiTaskConnection(
          id: 'mb',
          fromId: 'middle',
          toId: 'b',
          isHierarchy: true,
        ),
      ];
      final routes = buildTaskTopologyRoutes(
        nodes: nodes,
        connections: connections,
      );
      final repeated = buildTaskTopologyRoutes(
        nodes: nodes,
        connections: connections,
      );
      expect(routes.keys, ['ab', 'am', 'mb']);
      expect(routes['ab']!.intersectsRect(nodes['middle']!.deflate(1)), isTrue);
      expect(routes['ab']!.hitTest(nodes['middle']!.center), isTrue);
      for (final id in routes.keys) {
        final route = routes[id]!;
        final metric = route.path.computeMetrics().first;
        final other = repeated[id]!.path.computeMetrics().first;
        expect(metric.length, closeTo(other.length, .001));
        final point = metric.getTangentForOffset(metric.length / 2)!.position;
        expect(route.hitTest(point), isTrue);
        expect(
          route.intersectsRect(
            Rect.fromCenter(center: point, width: 1, height: 1),
          ),
          isTrue,
        );
      }
    },
  );
  test(
    'free unrelated edges preserve curves and missing endpoints are ignored',
    () {
      const nodes = {
        'a': Rect.fromLTWH(0, 0, 100, 80),
        'b': Rect.fromLTWH(400, 50, 100, 80),
      };
      const connections = [
        AiTaskConnection(id: 'ab', fromId: 'a', toId: 'b', isHierarchy: true),
        AiTaskConnection(
          id: 'missing',
          fromId: 'a',
          toId: 'deleted',
          isHierarchy: false,
        ),
      ];
      final routes = buildTaskTopologyRoutes(
        nodes: nodes,
        connections: connections,
      );
      expect(routes.keys, ['ab']);
      expect(routes['ab']!.start, nodes['a']!.centerRight);
      expect(routes['ab']!.end, nodes['b']!.centerLeft);
    },
  );
}
