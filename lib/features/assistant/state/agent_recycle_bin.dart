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
       parentId = record['parentId'] as String?,
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
  final String? parentId;
  Map<String, Object?> toJson() => {
    'record': record,
    'deletedAt': deletedAt.toIso8601String(),
    'position': position,
    'connections': connections,
  };
  Map<String, Object?> toStorage() => {
    'record': _record,
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

  Future<void> restoreRecycledAgent(String id) => restoreRecycledAgents([id]);

  Future<void> restoreRecycledAgents(
    Iterable<String> ids, {
    ValueChanged<double?>? onProgress,
    bool Function()? isCancelled,
  }) async {
    await initialized;
    if (_disposed || _recycleOperation || isCancelled?.call() == true) return;
    final selected = ids.toSet();
    final pending = {
      for (final entry in _recycledAgents)
        if (selected.contains(entry.id) && find(entry.id) == null)
          entry.id: entry,
    };
    if (pending.isEmpty) return;
    _recycleOperation = true;
    _recycleChanged();
    final staged = <AiAgentWorkspace>[];
    final snapshots = <Map<String, Object?>>[];
    final positions = <String, List<double>>{};
    var published = false;
    try {
      final ordered = <AiRecycledAgent>[];
      final visited = <String>{};
      for (final entry in pending.values) {
        final chain = <AiRecycledAgent>[];
        AiRecycledAgent? current = entry;
        while (current != null && visited.add(current.id)) {
          chain.add(current);
          current = pending[current.parentId];
        }
        ordered.addAll(chain.reversed);
      }
      final slice = Stopwatch()..start();
      var lastPercent = -1;
      for (final (index, entry) in ordered.indexed) {
        final percent = index * 100 ~/ ordered.length;
        if (percent != lastPercent) {
          onProgress?.call(index / ordered.length);
          lastPercent = percent;
        }
        if (slice.elapsedMilliseconds >= 8) {
          await Future<void>.delayed(Duration.zero);
          slice.reset();
        }
        if (_disposed || isCancelled?.call() == true) return;
        final session = await _prepareRecycledAgent(entry);
        staged.add(session);
        if (_disposed || isCancelled?.call() == true) return;
        snapshots.add(
          _sessionForStorage(
            session,
            session.assistant.snapshotWorkspaceConversation(),
          ),
        );
        if (entry.position case final position?) {
          positions[entry.id] = List.of(position);
        }
      }
      await Future<void>.delayed(Duration.zero);
      await _lastSave;
      if (_disposed || isCancelled?.call() == true) return;
      final storage = main.storage;
      if (storage == null) throw StateError('Storage unavailable');

      void restoreParent(AiAgentWorkspace session, Set<String> earlier) {
        final parentId = pending[session.id]!.parentId;
        session.parentId =
            earlier.contains(parentId) || find(parentId)?.closed == false
            ? parentId
            : null;
        session.kind = session.parentId == null
            ? AiWorkspaceKind.primary
            : AiWorkspaceKind.permanent;
        earlier.add(session.id);
      }

      final earlier = <String>{};
      for (final (index, session) in staged.indexed) {
        restoreParent(session, earlier);
        snapshots[index]['parentId'] = session.parentId;
        snapshots[index]['kind'] = session.kind.name;
      }
      final edges = <String, AiTaskConnection>{};
      for (final entry in ordered) {
        for (final connection in entry.connections) {
          final from = connection['fromId'] as String;
          final to = connection['toId'] as String;
          if (from == to ||
              !(earlier.contains(from) || _canLink(find(from))) ||
              !(earlier.contains(to) || _canLink(find(to)))) {
            continue;
          }
          final key = _connectionId(from, to);
          if (_supplementalConnections.containsKey(key) ||
              edges.containsKey(key)) {
            continue;
          }
          final ends = [from, to]..sort();
          edges[key] = AiTaskConnection(
            id: key,
            fromId: ends.first,
            toId: ends.last,
            isHierarchy: false,
          );
        }
      }
      final dirty = Set<String>.of(_dirtyConversations);
      try {
        final workflow = _workflowForStorage(omitRecycled: earlier);
        (workflow['sessions'] as List<Map<String, Object?>>).addAll(snapshots);
        workflow['canvas'] = {...canvasPositions, ...positions};
        (workflow['connections'] as List<Map<String, String>>).addAll([
          for (final edge in edges.values)
            {'fromId': edge.fromId, 'toId': edge.toId},
        ]);
        normalizeWorkflowData(workflow);
        onProgress?.call(null);
        await storage.saveWorkflow(workflow);
      } catch (_) {
        _dirtyConversations.addAll(dirty);
        rethrow;
      }
      if (_disposed) return;

      earlier.clear();
      for (final session in staged) {
        restoreParent(session, earlier);
        _register(session, synchronize: false);
        _dirtyConversations.remove(session.id);
      }
      published = true;
      for (final edge in edges.values) {
        _supplementalConnections.putIfAbsent(edge.id, () => edge);
      }
      _pruneConnections();
      canvasPositions.addAll(positions);
      _recycledAgents.removeWhere((entry) => earlier.contains(entry.id));
      _recycledAgentsCache = null;
      _invalidateRecycleHistory();
    } finally {
      if (!published) {
        for (final session in staged) {
          session.assistant.dispose();
        }
      }
      _recycleOperation = false;
      _notify();
    }
  }

  Future<AiAgentWorkspace> _prepareRecycledAgent(AiRecycledAgent entry) async {
    final assistant = main.forkForWorkspace();
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
      return AiAgentWorkspace(
        id: entry.id,
        title: entry.title,
        task: entry.task,
        assistant: assistant,
        createdAt: DateTime.parse(raw['createdAt'] as String),
        kind: AiWorkspaceKind.primary,
      );
    } catch (_) {
      assistant.dispose();
      rethrow;
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
