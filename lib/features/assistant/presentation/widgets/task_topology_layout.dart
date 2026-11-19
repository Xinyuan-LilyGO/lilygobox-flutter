import 'dart:math' as math;
import 'dart:ui';

import '../../state/agent_workspace.dart';

/// 仅计算自动布局位置，页面随后应用手动位置。
Map<String, Offset> layoutTaskTopology({
  required List<AiAgentWorkspace> sessions,
  required Map<String, Size> nodeSizes,
  required List<AiTaskConnection> connections,
}) {
  const siblingGap = 64.0;
  const columnWidth = 470.0;
  const fallbackSize = Size(252, 164);
  final byId = {for (final task in sessions) task.id: task};
  Size size(String id) => nodeSizes[id] ?? fallbackSize;
  final hierarchy = <String, List<String>>{};
  for (final task in sessions) {
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
  final roots = sessions.where((task) => !byId.containsKey(task.parentId));
  final seen = <String>{};
  final pending = <String>[];
  void appendSubtree(String start, List<String> preorder) {
    if (seen.contains(start)) return;
    pending.add(start);
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!seen.add(id)) continue;
      preorder.add(id);
      if (hierarchy[id] case final children?) {
        pending.addAll(children.reversed);
      }
    }
  }

  if (peers.isEmpty) {
    final positions = <String, Offset>{};
    final heights = <String, double>{};
    final origins = <String, Offset>{};
    final preorder = <String>[];
    var top = 140.0;
    for (final task in roots.followedBy(sessions)) {
      if (seen.contains(task.id)) continue;
      preorder.clear();
      appendSubtree(task.id, preorder);
      for (final id in preorder.reversed) {
        final children = hierarchy[id] ?? const <String>[];
        final childHeight = children.fold<double>(
          0,
          (sum, child) => sum + (heights[child] ?? size(child).height),
        );
        heights[id] = math.max(
          size(id).height,
          childHeight + math.max(0, children.length - 1) * siblingGap,
        );
      }
      origins[task.id] = Offset(180, top);
      top += heights[task.id]! + 160;
      for (final id in preorder) {
        final origin = origins.remove(id)!;
        final height = heights[id]!;
        positions[id] = Offset(
          origin.dx,
          origin.dy + (height - size(id).height) / 2,
        );
        if (hierarchy[id] case final children?) {
          final span = children.length < 2
              ? 0.0
              : height -
                    (heights[children.first]! + heights[children.last]!) / 2;
          // 为纵向跨度大的分支增加水平空间，不拉伸小型树。
          final childX =
              origin.dx +
              math.max(columnWidth, size(id).width + math.max(218, span / 4));
          var childTop = origin.dy;
          for (final child in children) {
            if (!positions.containsKey(child)) {
              origins[child] = Offset(childX, childTop);
            }
            childTop += heights[child]! + siblingGap;
          }
        }
      }
    }
    return positions;
  }

  // 归属关系有方向，沟通连接无方向。布局时
  // 每个完整连通分量只处理一次，包括独立的根节点。
  final order = {
    for (var index = 0; index < sessions.length; index++)
      sessions[index].id: index,
  };
  final adjacent = {for (final task in sessions) task.id: <String>{}};
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
  final seeds = sessions
      .where((task) => task.kind == AiWorkspaceKind.primary)
      .followedBy(roots)
      .followedBy(sessions);
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
    final ranked = <String>{};
    final parentPath = <String>[];
    for (final id in component) {
      if (ranked.contains(id)) continue;
      String? parent = id;
      while (parent != null && rank.containsKey(parent) && ranked.add(parent)) {
        parentPath.add(parent);
        parent = byId[parent]!.parentId;
      }
      final cycleStart = parentPath.contains(parent) ? parent : null;
      for (final child in parentPath.reversed) {
        if (child == cycleStart) continue;
        if (rank[byId[child]!.parentId] case final parentRank?) {
          rank[child] = math.max(rank[child]!, parentRank + 1);
        }
      }
      parentPath.clear();
    }
    final preorder = <String>[];
    for (final id in component) {
      appendSubtree(id, preorder);
    }
    final columns = <int, List<String>>{};
    for (final id in preorder) {
      columns.putIfAbsent(rank[id]!, () => []).add(id);
    }
    final ranks = columns.keys.toList()..sort();
    final columnHeights = [
      for (final depth in ranks)
        columns[depth]!.fold<double>(0, (sum, id) => sum + size(id).height) +
            (columns[depth]!.length - 1) * siblingGap,
    ];
    final componentHeight = columnHeights.reduce(math.max);
    var x = 180.0;
    for (var index = 0; index < ranks.length; index++) {
      final column = columns[ranks[index]]!;
      final height = columnHeights[index];
      var y = componentTop + (componentHeight - height) / 2;
      for (final id in column) {
        positions[id] = Offset(x, y);
        y += size(id).height + siblingGap;
      }
      final nextHeight = index + 1 < ranks.length
          ? columnHeights[index + 1]
          : 0.0;
      final span = math.max(height, nextHeight);
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
