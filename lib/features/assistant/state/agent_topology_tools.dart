part of 'agent_workspace_provider.dart';

extension _AiTopologyTools on AiWorkspaceProvider {
  Set<String> _managementGroup(String rootId) {
    final group = <String>{};
    final pending = [rootId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!group.add(current)) continue;
      pending.addAll(_topologyChildren[current] ?? const []);
    }
    return group;
  }

  Map<String, Object?> _agentTopology(AiAgentWorkspace? source) {
    if (source == null) throw StateError('A visible source agent is required');
    _synchronizeRelationships();
    final rootId = _rootId(source.id);
    final group = _managementGroup(rootId);
    final visible = <String>{...group};
    for (final id in group) {
      visible.addAll(_topologyAdjacency[id] ?? const {});
    }
    return {
      'revision': _topologyRevision,
      'agent_id': source.id,
      'primary_agent_id': rootId,
      'scope_agent_ids': group.toList()..sort(),
      'nodes': [
        for (final id in visible)
          if (_topologyAgents[id] case final agent?)
            {
              'agent_id': id,
              'title': agent.title,
              'role': agent.kind == AiWorkspaceKind.primary
                  ? 'primary'
                  : 'child',
              'parent_id': agent.parentId,
              'closed': agent.closed,
              'in_management_scope': group.contains(id),
            },
      ],
      'management_edges': [
        for (final id in group)
          if (_topologyAgents[id]?.parentId case final parent?)
            {'from_id': parent, 'to_id': id},
      ],
      'communication_edges': [
        for (final id in group)
          for (final neighbor in _topologyAdjacency[id] ?? const <String>{})
            if (!group.contains(neighbor) || id.compareTo(neighbor) < 0)
              {'from_id': id, 'to_id': neighbor},
      ],
    };
  }
}
