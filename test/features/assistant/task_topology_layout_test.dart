import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_layout.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';

class _Assistant extends Fake implements AiAssistantProvider {}

void main() {
  final assistant = _Assistant();
  AiAgentWorkspace task(String id, {String? parent, bool root = false}) =>
      AiAgentWorkspace(
        id: id,
        title: id,
        task: id,
        assistant: assistant,
        createdAt: DateTime(2026),
        parentId: parent,
        kind: root ? AiWorkspaceKind.primary : AiWorkspaceKind.permanent,
      );
  AiTaskConnection peer(String a, String b) =>
      AiTaskConnection(id: '$a-$b', fromId: a, toId: b, isHierarchy: false);
  Map<String, Offset> layout(
    List<AiAgentWorkspace> nodes,
    List<AiTaskConnection> edges, {
    Map<String, Size> sizes = const {},
  }) =>
      layoutTaskTopology(sessions: nodes, nodeSizes: sizes, connections: edges);
  void noOverlap(
    Map<String, Offset> positions, {
    Map<String, Size> sizes = const {},
  }) {
    final ids = positions.keys.toList();
    for (var a = 0; a < ids.length; a++) {
      for (var b = a + 1; b < ids.length; b++) {
        expect(
          (positions[ids[a]]! & (sizes[ids[a]] ?? const Size(252, 164)))
              .overlaps(
                positions[ids[b]]! & (sizes[ids[b]] ?? const Size(252, 164)),
              ),
          isFalse,
          reason: '${ids[a]} overlaps ${ids[b]}',
        );
      }
    }
  }

  test(
    'pure hierarchy retains original subtree spacing and centered parents',
    () {
      final nodes = [
        task('root', root: true),
        task('a', parent: 'root'),
        task('b', parent: 'root'),
        task('nested', parent: 'a'),
      ];
      final positions = layout(nodes, []);
      expect(positions['a'], const Offset(650, 140));
      expect(positions['b'], const Offset(650, 368));
      expect(positions['root'], const Offset(180, 254));
      expect(positions['nested'], const Offset(1120, 140));
      noOverlap(positions);
    },
  );
  test(
    'large fans receive more horizontal room with consistent sibling columns',
    () {
      double width(int count) {
        final nodes = [
          task('root', root: true),
          for (var i = 0; i < count; i++) task('c$i', parent: 'root'),
        ];
        final positions = layout(nodes, []);
        noOverlap(positions);
        expect({
          for (var i = 0; i < count; i++) positions['c$i']!.dx,
        }, hasLength(1));
        expect(
          positions['root']!.dy,
          closeTo(
            (positions['c0']!.dy + positions['c${count - 1}']!.dy) / 2,
            .001,
          ),
        );
        return positions['c0']!.dx - positions['root']!.dx;
      }

      final small = width(3);
      final medium = width(10);
      final large = width(20);
      expect(small, 470);
      expect(medium, greaterThan(small));
      expect(large, greaterThan(medium));
    },
  );

  test(
    'incremental children use a negative parent position in any record order',
    () {
      final added = placeNewTaskChildren(
        sessions: [
          task('nested', parent: 'a'),
          task('a', parent: 'root'),
          task('root', root: true),
        ],
        anchors: {'root': const Offset(-5000, -3000)},
        sizeOf: (_) => const Size(252, 164),
      );
      expect(added, {
        'a': const Offset(-4530, -3000),
        'nested': const Offset(-4060, -3000),
      });
    },
  );

  test('sibling communication fans both branches into distinct rows', () {
    final nodes = [
      task('root', root: true),
      task('a', parent: 'root'),
      task('b', parent: 'root'),
    ];
    final positions = layout(nodes, [peer('a', 'b')]);
    expect(positions['a']!.dx, positions['b']!.dx);
    expect(
      (positions['a']!.dy - positions['b']!.dy).abs(),
      greaterThanOrEqualTo(228),
    );
    expect(positions['root']!.dx, lessThan(positions['a']!.dx));
    noOverlap(positions);
  });
  test('independent root communication chain uses columns instead of one vertical line', () {
    final nodes = [
      task('root', root: true),
      task('a', root: true),
      task('b', root: true),
      task('c', root: true),
    ];
    final positions = layout(nodes, [
      peer('root', 'a'),
      peer('a', 'b'),
      peer('b', 'c'),
    ]);
    expect(positions['root']!.dx, lessThan(positions['a']!.dx));
    expect(positions['a']!.dx, lessThan(positions['b']!.dx));
    expect(positions['b']!.dx, lessThan(positions['c']!.dx));
    noOverlap(positions);
  });
  test(
    'extra shortcut never puts ownership child to the left of its parent',
    () {
      final nodes = [
        task('root', root: true),
        task('a', parent: 'root'),
        task('b', parent: 'a'),
        task('c', parent: 'b'),
      ];
      final positions = layout(nodes, [peer('root', 'c')]);
      for (final node in nodes.where((node) => node.parentId != null)) {
        expect(
          positions[node.id]!.dx,
          greaterThan(positions[node.parentId]!.dx),
        );
      }
      noOverlap(positions);
    },
  );
  for (final withShortcut in [false, true]) {
    test(
      '10,000-level hierarchy preserves each column (peer: $withShortcut)',
      () {
        const count = 10000;
        final nodes = [
          task('0', root: true),
          for (var depth = 1; depth < count; depth++)
            task('$depth', parent: '${depth - 1}'),
        ];
        final edges = [if (withShortcut) peer('0', '${count - 1}')];
        final positions = layout(nodes, edges);
        expect(positions, hasLength(count));
        for (var depth = 0; depth < count; depth++) {
          expect(positions['$depth'], Offset(180 + 470.0 * depth, 140));
        }
      },
    );
  }
  test('ownership cycles retain every card and a deterministic layout', () {
    final nodes = [
      task('a', parent: 'c', root: true),
      task('b', parent: 'a'),
      task('c', parent: 'b'),
      task('branch', parent: 'b'),
      task('self', parent: 'self'),
    ];
    for (final edges in [
      <AiTaskConnection>[],
      [peer('a', 'c')],
    ]) {
      final positions = layout(nodes, edges);
      expect(positions.keys, unorderedEquals(nodes.map((node) => node.id)));
      expect(layout(nodes, edges), positions);
      noOverlap(positions);
    }
  });
  test('variable heights widths and disconnected components never overlap', () {
    final nodes = [
      task('root', root: true),
      task('a', parent: 'root'),
      task('b', parent: 'root'),
      task('c', parent: 'a'),
      task('other', root: true),
    ];
    const sizes = {
      'root': Size(600, 340),
      'a': Size(252, 600),
      'b': Size(252, 240),
      'c': Size(252, 700),
      'other': Size(600, 200),
    };
    final positions = layout(nodes, [peer('a', 'b')], sizes: sizes);
    noOverlap(positions, sizes: sizes);
    final lastBottom = nodes
        .where((node) => node.id != 'other')
        .map((node) => positions[node.id]!.dy + sizes[node.id]!.height)
        .reduce((a, b) => a > b ? a : b);
    expect(positions['other']!.dy, greaterThan(lastBottom));
  });
  test(
    'communication cycle is deterministic with shuffled undirected edges',
    () {
      final nodes = [
        task('root', root: true),
        task('a', parent: 'root'),
        task('b', parent: 'root'),
        task('c', parent: 'a'),
      ];
      final edges = [peer('a', 'b'), peer('b', 'c'), peer('c', 'root')];
      final first = layout(nodes, edges);
      expect(layout(nodes, edges.reversed.toList()), first);
      expect(layout(nodes, edges), first);
      expect(first, hasLength(4));
      noOverlap(first);
    },
  );
  test(
    'every child is visible and unknown supplemental endpoints are ignored',
    () {
      final root = task('root', root: true);
      final child = task('child', parent: 'root');
      final positions = layout([root, child], [peer('root', 'missing')]);
      expect(positions, {
        'root': const Offset(180, 140),
        'child': const Offset(650, 140),
      });
      noOverlap(positions);
      expect(layout([], []), isEmpty);
    },
  );
}
