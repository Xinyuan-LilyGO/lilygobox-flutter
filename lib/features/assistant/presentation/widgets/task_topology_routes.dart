import 'dart:ui';

import '../../state/agent_workspace.dart';
import 'task_topology_connection.dart';

/// Each curve depends only on its endpoint cards. Painting and selection share
/// this path; unrelated cards cover the curve without rerouting it.
Map<String, TaskTopologyConnection> buildTaskTopologyRoutes({
  required Map<String, Rect> nodes,
  required List<AiTaskConnection> connections,
}) => {
  for (final edge in connections)
    if (nodes.containsKey(edge.fromId) && nodes.containsKey(edge.toId))
      edge.id: TaskTopologyConnection.between(
        nodes[edge.fromId]!,
        nodes[edge.toId]!,
      ),
};
