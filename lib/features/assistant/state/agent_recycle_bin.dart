part of 'agent_workspace_provider.dart';

/// 持久化会话快照；回收站不持有运行中的状态对象。
class AiRecycledAgent {
  AiRecycledAgent({
    required Map<String, dynamic> record,
    required this.deletedAt,
    this.position,
    this.connections = const [],
  }) : id = record['id'] as String,
       title = record['title'] as String,
       task = record['task'] as String,
       _record = jsonEncode(record);
  final String _record;
  Map<String, dynamic> get record =>
      jsonDecode(_record) as Map<String, dynamic>;
  final DateTime deletedAt;
  final List<double>? position;
  final List<Map<String, dynamic>> connections;
  final String id;
  final String title;
  final String task;
  Map<String, Object?> toJson() => {
    'record': record,
    'deletedAt': deletedAt.toIso8601String(),
    'position': position,
    'connections': connections,
  };
  factory AiRecycledAgent.fromJson(Map value) {
    final record = Map<String, dynamic>.from(value['record'] as Map);
    if (record['id'] is! String ||
        !RegExp(r'^\d+-\d+$').hasMatch(record['id'] as String) ||
        record['title'] is! String ||
        record['task'] is! String ||
        record['conversation'] is! Map) {
      throw const FormatException('Invalid recycled agent');
    }
    return AiRecycledAgent(
      record: record,
      deletedAt: DateTime.parse(value['deletedAt'] as String),
      position: (value['position'] as List?)
          ?.map((v) => (v as num).toDouble())
          .toList(),
      connections: (value['connections'] as List? ?? [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList(),
    );
  }
}

extension AiAgentRecycleBin on AiWorkspaceProvider {
  List<AiRecycledAgent> get recycledAgents =>
      _recycledAgentsCache ??= List.unmodifiable(
        [..._recycledAgents]
          ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt)),
      );
  int get recycleRetentionDays => _recycleRetentionDays;
  bool get recycleBusy => _recycleOperation;
  DateTime? recycleExpiry(AiRecycledAgent entry) => _recycleRetentionDays == 0
      ? null
      : entry.deletedAt.add(Duration(days: _recycleRetentionDays));

  void _restoreRecycleState(Map data) {
    _recycledAgentsCache = null;
    _recycleRetentionDays = switch (data['recycleRetentionDays']) {
      0 => 0,
      7 => 7,
      90 => 90,
      _ => 30,
    };
    final seen = <String>{};
    for (final raw in data['recycleBin'] as List? ?? []) {
      final entry = AiRecycledAgent.fromJson(raw as Map);
      if (!seen.add(entry.id)) {
        throw const FormatException('Duplicate recycled agent');
      }
      _recycledAgents.add(entry);
    }
  }

  void _moveToRecycleBin(List<AiAgentWorkspace> removing, Map snapshot) {
    _recycledAgentsCache = null;
    final ids = removing.map((s) => s.id).toSet();
    final now = DateTime.now();
    _recycledAgents.removeWhere((e) => ids.contains(e.id));
    for (final raw in (snapshot['sessions'] as List).cast<Map>().where(
      (r) => ids.contains(r['id']),
    )) {
      final id = raw['id'] as String;
      _recycledAgents.add(
        AiRecycledAgent(
          record: Map<String, dynamic>.from(raw),
          deletedAt: now,
          position: canvasPositions[id] == null
              ? null
              : List.of(canvasPositions[id]!),
          connections: (snapshot['connections'] as List)
              .cast<Map>()
              .where((c) => c['fromId'] == id || c['toId'] == id)
              .map((c) => Map<String, dynamic>.from(c))
              .toList(),
        ),
      );
    }
  }

  List<AiRecycledAgent> _prepareRecycleImport(
    Map data,
    Map<String, String> mapping,
  ) {
    final entries = [
      for (final raw in data['recycleBin'] as List? ?? [])
        AiRecycledAgent.fromJson(raw as Map),
    ];
    for (final entry in entries) {
      if (mapping.containsKey(entry.id)) {
        throw const FormatException('Duplicate imported agent');
      }
      mapping[entry.id] =
          '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    }
    return [
      for (final entry in entries)
        AiRecycledAgent(
          record: {
            ...entry.record,
            'id': mapping[entry.id],
            'parentId': mapping[entry.record['parentId']],
          },
          deletedAt: entry.deletedAt,
          position: entry.position,
          connections: [
            for (final c in entry.connections)
              if (mapping.containsKey(c['fromId']) &&
                  mapping.containsKey(c['toId']))
                {'fromId': mapping[c['fromId']], 'toId': mapping[c['toId']]},
          ],
        ),
    ];
  }

  void _invalidateRecycleHistory() {
    recycleRevision++;
    for (final snapshot in _editSnapshots.toList()) {
      releaseTopologyEdit(snapshot);
    }
  }

  Future<void> _saveRecycleState() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _lastSave;
    final storage = main.storage;
    if (storage == null) throw StateError('Storage unavailable');
    await storage.saveWorkflow(exportData());
  }

  Future<void> restoreRecycledAgent(String id) async {
    await initialized;
    if (_recycleOperation) return;
    final entry = _recycledAgents.where((e) => e.id == id).firstOrNull;
    if (entry == null || find(id) != null) return;
    _recycleOperation = true;
    _recycleChanged();
    final assistant = main.forkForWorkspace();
    AiAgentWorkspace? restored;
    try {
      final raw = entry.record;
      final conversation = Map<String, dynamic>.from(
        raw['conversation'] as Map,
      );
      final serviceId = conversation['serviceId'] as String;
      final model = conversation['model'] as String;
      final service = main.services.where((s) => s.id == serviceId).firstOrNull;
      if (service != null &&
          service.models.contains(model) &&
          main.hasServiceKey(serviceId)) {
        await assistant.selectModel(serviceId, model);
        final effort = AiReasoningEffort.values
            .where((e) => e.name == conversation['effort'])
            .firstOrNull;
        if (effort != null) await assistant.setReasoningEffort(effort);
        final speed = assistant.processingSpeeds
            .where((e) => e.name == conversation['processingSpeed'])
            .firstOrNull;
        if (speed != null) await assistant.setProcessingSpeed(speed);
      } else {
        assistant.markWorkspaceSelectionUnavailable(
          serviceId: serviceId,
          model: model,
        );
      }
      assistant.setPermissions(AiPermissions());
      assistant.restoreWorkspaceConversation(conversation);
      final parent = find(raw['parentId'] as String? ?? '');
      restored = AiAgentWorkspace(
        id: id,
        title: entry.title,
        task: entry.task,
        assistant: assistant,
        createdAt: DateTime.parse(raw['createdAt'] as String),
        kind: parent != null && !parent.closed
            ? AiWorkspaceKind.permanent
            : AiWorkspaceKind.primary,
        parentId: parent != null && !parent.closed ? parent.id : null,
      );
      _register(restored);
      _recycledAgents.remove(entry);
      _recycledAgentsCache = null;
      if (entry.position != null) {
        canvasPositions[id] = List.of(entry.position!);
      }
      final added = <String>[];
      for (final c in entry.connections) {
        final from = c['fromId'] as String;
        final to = c['toId'] as String;
        if (find(from) == null ||
            find(to) == null ||
            find(from)!.closed ||
            find(to)!.closed) {
          continue;
        }
        final key = _connectionId(from, to);
        if (!_supplementalConnections.containsKey(key)) {
          final ends = [from, to]..sort();
          _supplementalConnections[key] = AiTaskConnection(
            id: key,
            fromId: ends.first,
            toId: ends.last,
            isHierarchy: false,
          );
          added.add(key);
        }
      }
      try {
        await _saveRecycleState();
      } catch (_) {
        _sessions.remove(restored);
        final listener = _sessionListeners.remove(assistant);
        if (listener != null) assistant.removeListener(listener);
        restored = null;
        _recycledAgents.add(entry);
        _recycledAgentsCache = null;
        canvasPositions.remove(id);
        for (final key in added) {
          _supplementalConnections.remove(key);
        }
        rethrow;
      }
      _invalidateRecycleHistory();
    } finally {
      if (restored == null) assistant.dispose();
      _recycleOperation = false;
      _notify();
    }
  }

  Future<void> permanentlyDeleteRecycledAgents(Iterable<String> ids) async {
    await initialized;
    await _purgeRecycled(ids.toSet());
  }

  Future<void> _purgeRecycled(Set<String> ids) async {
    if (_disposed || _recycleOperation) return;
    final removing = _recycledAgents.where((e) => ids.contains(e.id)).toList();
    if (removing.isEmpty) return;
    _recycleOperation = true;
    _recycleChanged();
    try {
      _saveTimer?.cancel();
      _saveTimer = null;
      await _lastSave;
      final workflow = exportData();
      workflow['recycleBin'] = [
        for (final e in _recycledAgents)
          if (!ids.contains(e.id)) e.toJson(),
      ];
      final storage = main.storage;
      if (storage == null) throw StateError('Storage unavailable');
      await storage.request('commitRecycle', {
        'value': workflow,
        'owners': removing.map((e) => e.id).toList(),
      });
      _recycledAgents.removeWhere((e) => ids.contains(e.id));
      _recycledAgentsCache = null;
      _purgedAgentIds.addAll(removing.map((e) => e.id));
      _invalidateRecycleHistory();
    } finally {
      _recycleOperation = false;
      if (!_disposed) _recycleChanged();
    }
  }

  Future<void> purgeExpiredRecycledAgents({DateTime? now}) async {
    if (_recycleRetentionDays == 0) return;
    final instant = now ?? DateTime.now();
    await _purgeRecycled({
      for (final e in _recycledAgents)
        if (!recycleExpiry(e)!.isAfter(instant)) e.id,
    });
  }

  Future<void> setRecycleRetentionDays(int days) async {
    await initialized;
    if (![0, 7, 30, 90].contains(days) || _recycleOperation) return;
    final previous = _recycleRetentionDays;
    _recycleRetentionDays = days;
    try {
      await _saveRecycleState();
    } catch (_) {
      _recycleRetentionDays = previous;
      rethrow;
    }
    await purgeExpiredRecycledAgents();
    _notify();
  }
}
