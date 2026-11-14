import 'dart:math' as math;
import 'dart:ui';

import '../../state/agent_workspace.dart';

/// Automatic positions only; the page applies any manual positions afterwards.
Map<String, Offset> layoutTaskTopology({
  required List<AiAgentWorkspace> sessions,
  required Map<String, Size> nodeSizes,
  required List<AiTaskConnection> connections,
}) {
  const siblingGap = 64.0;
  const columnWidth = 470.0;
  const fallbackSize = Size(252, 164);
  final visible = sessions.toList();
  final byId = {for (final task in visible) task.id: task};
  final order = {for (var i = 0; i < visible.length; i++) visible[i].id: i};
  Size size(String id) => nodeSizes[id] ?? fallbackSize;
  final hierarchy = <String, List<String>>{};
  for (final task in visible) {
    if (byId.containsKey(task.parentId)) {
      hierarchy.putIfAbsent(task.parentId!, () => []).add(task.id);
    }
  }
  final peers = connections
      .where(
        (edge) =>
            !edge.isHierarchy &&
            byId.containsKey(edge.fromId) &&
            byId.containsKey(edge.toId),
      )
      .toList();
  if (peers.isEmpty) {
    final positions = <String, Offset>{};
    final heights = <String, double>{};
    double measure(String id, Set<String> ancestors) {
      if (ancestors.contains(id)) return size(id).height;
      if (heights[id] case final height?) return height;
      final children = hierarchy[id] ?? const <String>[];
      final childHeight =
          children.fold<double>(
            0,
            (sum, child) => sum + measure(child, {...ancestors, id}),
          ) +
          math.max(0, children.length - 1) * siblingGap;
      return heights[id] = math.max(size(id).height, childHeight);
    }

    void place(String id, double x, double top) {
      if (positions.containsKey(id)) return;
      final height = measure(id, {});
      positions[id] = Offset(x, top + (height - size(id).height) / 2);
      final children = hierarchy[id] ?? const <String>[];
      final span = children.length < 2
          ? 0.0
          : height -
                (measure(children.first, {}) + measure(children.last, {})) / 2;
      // Give tall fans enough horizontal runway without stretching small trees.
      final childX =
          x + math.max(columnWidth, size(id).width + math.max(218, span / 4));
      var childTop = top;
      for (final child in children) {
        place(child, childX, childTop);
        childTop += measure(child, {}) + siblingGap;
      }
    }

    var top = 140.0;
    for (final task in [
      ...visible.where((task) => !byId.containsKey(task.parentId)),
      ...visible,
    ]) {
      if (positions.containsKey(task.id)) continue;
      place(task.id, 180, top);
      top += measure(task.id, {}) + 160;
    }
    return positions;
  }

  // Ownership is directed, whereas communication edges are undirected. Lay out
  // each complete connected component once, including legacy orphan/root links.
  final adjacent = {for (final task in visible) task.id: <String>{}};
  void link(String a, String b) {
    adjacent[a]!.add(b);
    adjacent[b]!.add(a);
  }

  for (final parent in hierarchy.entries) {
    for (final child in parent.value) {
      link(parent.key, child);
    }
  }
  for (final edge in peers) {
    link(edge.fromId, edge.toId);
  }
  final positions = <String, Offset>{};
  var componentTop = 140.0;
  final seeds = [
    ...visible.where((task) => task.kind == AiWorkspaceKind.primary),
    ...visible.where((task) => !byId.containsKey(task.parentId)),
    ...visible,
  ];
  for (final seed in seeds) {
    if (positions.containsKey(seed.id)) continue;
    final component = <String>[];
    final rank = <String, int>{seed.id: 0};
    final queue = <String>[seed.id];
    for (var cursor = 0; cursor < queue.length; cursor++) {
      final id = queue[cursor];
      component.add(id);
      final neighbors = adjacent[id]!.toList()
        ..sort((a, b) {
          final aChild = byId[a]!.parentId == id;
          final bChild = byId[b]!.parentId == id;
          if (aChild != bChild) return aChild ? -1 : 1;
          return order[a]!.compareTo(order[b]!);
        });
      for (final neighbor in neighbors) {
        if (rank.containsKey(neighbor)) continue;
        rank[neighbor] = rank[id]! + 1;
        queue.add(neighbor);
      }
    }
    // Keep children to the right of their actual parent even when a peer edge
    // supplied a shorter route. Bounded passes also tolerate malformed cycles.
    for (var pass = 0; pass < component.length; pass++) {
      var changed = false;
      for (final id in component) {
        final parent = byId[id]!.parentId;
        if (rank.containsKey(parent) && rank[id]! <= rank[parent]!) {
          rank[id] = rank[parent]! + 1;
          changed = true;
        }
      }
      if (!changed) break;
    }
    final columns = <int, List<String>>{};
    for (final id in component) {
      columns.putIfAbsent(rank[id]!, () => []).add(id);
    }
    final ranks = columns.keys.toList()..sort();
    // Stable ownership preorder keeps siblings and their descendants adjacent.
    final preorder = <String, int>{};
    void visit(String id) {
      if (preorder.containsKey(id)) return;
      preorder[id] = preorder.length;
      for (final child in hierarchy[id] ?? const <String>[]) {
        visit(child);
      }
    }

    visit(seed.id);
    for (final id in component) {
      visit(id);
    }
    for (final column in columns.values) {
      column.sort((a, b) => preorder[a]!.compareTo(preorder[b]!));
    }
    double columnHeight(List<String> ids) =>
        ids.fold<double>(0, (sum, id) => sum + size(id).height) +
        math.max(0, ids.length - 1) * siblingGap;
    final componentHeight = columns.values.map(columnHeight).reduce(math.max);
    var x = 180.0;
    for (final depth in ranks) {
      final column = columns[depth]!;
      var y = componentTop + (componentHeight - columnHeight(column)) / 2;
      for (final id in column) {
        positions[id] = Offset(x, y);
        y += size(id).height + siblingGap;
      }
      final nextRank = ranks.indexOf(depth) + 1;
      final nextHeight = nextRank < ranks.length
          ? columnHeight(columns[ranks[nextRank]]!)
          : 0.0;
      final span = math.max(columnHeight(column), nextHeight);
      x += math.max(
        columnWidth,
        column.map((id) => size(id).width).reduce(math.max) +
            math.max(218, span / 4),
      );
    }
    componentTop += componentHeight + 160;
  }
  return positions;
}
