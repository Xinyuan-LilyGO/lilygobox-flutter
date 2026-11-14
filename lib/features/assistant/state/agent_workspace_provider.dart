/*
 * @Description: 管理智能体拓扑、可见子智能体、独立会话及协作工具。
 * @Author: LILYGO_L
 * @Date: 2026-11-13 20:10:00
 * @LastEditTime: 2026-11-13 21:30:00
 */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/permissions.dart';
import '../domain/reasoning.dart';
import '../domain/task_canvas_style.dart';
import 'agent_workspace.dart';
import 'provider.dart';

export 'agent_workspace.dart';

/// A real message dispatch, retained only for the short transport animation.
class AiAgentTransfer {
  const AiAgentTransfer(this.id, this.fromId, this.toId, this.startedAt);
  final int id;
  final String fromId;
  final String toId;
  final DateTime startedAt;
  static const duration = Duration(milliseconds: 1400);
}

/// In-memory editor state. Conversations stay on their original task objects.
class AiTopologyEditSnapshot {
  AiTopologyEditSnapshot._(
    this._owner,
    List<AiAgentWorkspace> tasks,
    this._connections,
    this._selectedId,
  ) : _tasks = List.unmodifiable(tasks),
      _fields = {
        for (final task in tasks)
          task.id: (task.title, task.parentId, task.kind, task.closed),
      },
      _deliveryCounts = Map.of(_owner._deliveryCounts),
      _deliveredMessages = {
        for (final entry in _owner._deliveredMessages.entries)
          entry.key: Set<String>.of(entry.value),
      };
  final Map<String, int> _deliveryCounts;
  final Map<String, Set<String>> _deliveredMessages;
  final AiWorkspaceProvider _owner;
  final List<AiAgentWorkspace> _tasks;
  final Map<String, (String, String?, AiWorkspaceKind, bool)> _fields;
  final List<AiTaskConnection> _connections;
  final String? _selectedId;
  bool matches(AiTopologyEditSnapshot other) =>
      identical(_owner, other._owner) &&
      mapEquals(_fields, other._fields) &&
      listEquals(
        _tasks.map((task) => task.id).toList(),
        other._tasks.map((task) => task.id).toList(),
      ) &&
      listEquals(
        _connections
            .map((edge) => (edge.id, edge.fromId, edge.toId, edge.isHierarchy))
            .toList(),
        other._connections
            .map((edge) => (edge.id, edge.fromId, edge.toId, edge.isHierarchy))
            .toList(),
      );
}

class AiWorkspaceProvider extends ChangeNotifier {
  AiWorkspaceProvider(this.main) {
    // 模板会话提供共享配置；拓扑主智能体各自使用专属分派闭包。
    main.workspaceToolDefinitions = _tools;
    main.workspaceToolHandler = (name, args) =>
        _executeTool('main', name, args);
    initialized = _restore();
  }
  static const storageKey = 'ai.agentWorkflow.v2';
  static const canvasStyleStorageKey = 'ai.agentCanvasStyle.v1';
  final ValueNotifier<List<AiAgentTransfer>> _transfers = ValueNotifier(
    const [],
  );
  ValueListenable<List<AiAgentTransfer>> get transfers => _transfers;
  final Map<int, Timer> _transferTimers = {};
  int _transferSequence = 0;

  void _recordTransfer(String? fromId, String toId) {
    if (_disposed || fromId == null || find(fromId) == null) return;
    if (!connections.any(
      (edge) =>
          (edge.fromId == fromId && edge.toId == toId) ||
          (edge.toId == fromId && edge.fromId == toId),
    )) {
      return;
    }
    final transfer = AiAgentTransfer(
      ++_transferSequence,
      fromId,
      toId,
      DateTime.now(),
    );
    _transfers.value = List.unmodifiable([..._transfers.value, transfer]);
    _transferTimers[transfer.id] = Timer(AiAgentTransfer.duration, () {
      _transferTimers.remove(transfer.id);
      if (!_disposed) {
        _transfers.value = List.unmodifiable(
          _transfers.value.where((item) => item.id != transfer.id),
        );
      }
    });
  }

  final Map<(String, String), String> _observedReplies = {};

  Map<String, Object?> _observedResult(
    AiAgentWorkspace agent,
    String? receiverId,
  ) {
    final result = agent.toToolResult();
    if (receiverId != null &&
        find(receiverId) != null &&
        !agent.busy &&
        !agent.closed &&
        agent.result.isNotEmpty) {
      final reply = agent.assistant.messages
          .where(
            (message) =>
                message.role == 'assistant' && message.content.isNotEmpty,
          )
          .last;
      final revision =
          '${reply.id}:${reply.content.length}:${reply.content.hashCode}';
      final key = (receiverId, agent.id);
      if (_observedReplies[key] != revision) {
        _observedReplies[key] = revision;
        _recordTransfer(agent.id, receiverId);
      }
    }
    return result;
  }

  final AiAssistantProvider main;
  final List<AiAgentWorkspace> _sessions = [];
  final Map<String, AiTaskConnection> _supplementalConnections = {};
  late final Future<void> initialized;
  bool _disposed = false;
  bool _restoring = true;
  int _sequence = 0;
  String? _selectedId;

  /// UI sets this only while an active agent conversation is being viewed.
  String? activeConversationId;
  int _navigationRevision = 0;
  ({int revision, String? sourceId, String targetId})? _navigationRequest;

  /// One-shot UI request. Consumers track revision and only follow their active source.
  ({int revision, String? sourceId, String targetId})? get navigationRequest =>
      _navigationRequest;
  Timer? _saveTimer;
  Object? persistenceError;
  static const maximumAutomaticMessages = 12;
  final Map<String, int> _deliveryCounts = {};
  final Map<String, Set<String>> _deliveredMessages = {};
  List<AiAgentWorkspace> get sessions => List.unmodifiable(_sessions);
  List<AiAgentWorkspace> get primaries => List.unmodifiable(
    _sessions.where((s) => s.kind == AiWorkspaceKind.primary),
  );
  AiTaskCanvasStyle get canvasStyle {
    final saved = main.workspacePreferences.stringValue(
      canvasStyleStorageKey,
      'dots',
    );
    return AiTaskCanvasStyle.values
            .where((style) => style.name == saved)
            .firstOrNull ??
        AiTaskCanvasStyle.dots;
  }

  void setCanvasStyle(AiTaskCanvasStyle style) {
    if (_disposed || canvasStyle == style) return;
    main.workspacePreferences.setValue(canvasStyleStorageKey, style.name);
    _notify();
  }

  final Set<AiTopologyEditSnapshot> _editSnapshots = {};
  final Map<String, AiAgentWorkspace> _detachedEditTasks = {};

  AiTopologyEditSnapshot captureTopologyEdit() {
    if (_disposed) throw StateError('Workspace is closed');
    final snapshot = AiTopologyEditSnapshot._(
      this,
      _sessions,
      connections,
      _selectedId,
    );
    _editSnapshots.add(snapshot);
    return snapshot;
  }

  /// Restore graph edits without replaying tools, messages, or active requests.
  Future<void> restoreTopologyEdit(
    AiTopologyEditSnapshot snapshot, {
    AiTopologyEditSnapshot? previous,
  }) async {
    if (_disposed ||
        !_editSnapshots.contains(snapshot) ||
        !identical(snapshot._owner, this)) {
      throw StateError('Topology edit snapshot is no longer available');
    }
    if (previous != null &&
        (!_editSnapshots.contains(previous) ||
            !identical(previous._owner, this))) {
      throw StateError('Previous topology snapshot is no longer available');
    }
    final desired = snapshot._tasks.map((task) => task.id).toSet();
    final externalTasks = previous == null
        ? <AiAgentWorkspace>[]
        : _sessions
              .where(
                (task) =>
                    !previous._fields.containsKey(task.id) &&
                    !desired.contains(task.id),
              )
              .toList();
    desired.addAll(externalTasks.map((task) => task.id));
    for (final task in _sessions.toList()) {
      if (!desired.contains(task.id)) {
        _sessions.remove(task);
        _detachForEdit(task);
      }
    }
    for (final task in snapshot._tasks) {
      if (previous != null &&
          previous._fields[task.id] == snapshot._fields[task.id]) {
        continue;
      }
      if (!_sessions.contains(task)) {
        _detachedEditTasks.remove(task.id);
        _register(task);
      }
      final (title, parentId, kind, closed) = snapshot._fields[task.id]!;
      final old = previous?._fields[task.id];
      if (old == null || old.$1 != title) task.title = title;
      if (old == null || old.$2 != parentId) task.parentId = parentId;
      if (old == null || old.$3 != kind) task.kind = kind;
      if (old == null || old.$4 != closed) task.closed = closed;
    }
    _sessions.sort(
      (a, b) =>
          snapshot._tasks.indexOf(a).compareTo(snapshot._tasks.indexOf(b)),
    );
    final targetPeers = {
      for (final edge in snapshot._connections.where(
        (edge) => !edge.isHierarchy,
      ))
        edge.id: edge,
    };
    if (previous == null) {
      _supplementalConnections
        ..clear()
        ..addAll(targetPeers);
    } else {
      final oldPeers = {
        for (final edge in previous._connections.where(
          (edge) => !edge.isHierarchy,
        ))
          edge.id: edge,
      };
      for (final id in {...oldPeers.keys, ...targetPeers.keys}) {
        final before = oldPeers[id];
        final after = targetPeers[id];
        if (before?.fromId == after?.fromId && before?.toId == after?.toId) {
          continue;
        }
        _supplementalConnections.remove(id);
        if (after != null) _supplementalConnections[id] = after;
      }
    }
    _pruneConnections();
    // History never resets safety quotas or permits automatic-message replay.
    for (final entry in snapshot._deliveryCounts.entries) {
      if ((_deliveryCounts[entry.key] ?? 0) < entry.value) {
        _deliveryCounts[entry.key] = entry.value;
      }
    }
    for (final entry in snapshot._deliveredMessages.entries) {
      (_deliveredMessages[entry.key] ??= {}).addAll(entry.value);
    }
    _selectedId = desired.contains(snapshot._selectedId)
        ? snapshot._selectedId
        : _sessions.firstOrNull?.id;
    _notify();
  }

  /// Release when a history step is discarded, including page disposal.
  void releaseTopologyEdit(AiTopologyEditSnapshot snapshot) {
    if (!_editSnapshots.remove(snapshot)) return;
    for (final task in _detachedEditTasks.values.toList()) {
      if (!_editSnapshots.any((saved) => saved._tasks.contains(task))) {
        _detachedEditTasks.remove(task.id);
        task.assistant.dispose();
      }
    }
  }

  final Map<String, Object> _pendingNames = {};

  void _detachForEdit(AiAgentWorkspace task) {
    _pendingNames.remove(task.id);
    task.assistant.removeListener(_notify);
    task.assistant.closeWorkspaceRuntime();
    if (_editSnapshots.any((snapshot) => snapshot._tasks.contains(task))) {
      _detachedEditTasks[task.id] = task;
    } else {
      task.assistant.dispose();
    }
  }

  String? get selectedId => _selectedId;
  AiAgentWorkspace? get selected => find(_selectedId);
  int get runningCount => _sessions
      .where((s) => s.kind != AiWorkspaceKind.primary && s.busy)
      .length;
  AiAgentWorkspace? find(String? id) =>
      _sessions.where((s) => s.id == id).firstOrNull;
  List<AiAgentWorkspace> childrenOf(String id) =>
      List.unmodifiable(_sessions.where((s) => s.parentId == id));

  bool _canLink(AiAgentWorkspace? task) => task != null && !task.closed;

  bool _isHierarchyPair(String first, String second) =>
      find(first)?.parentId == second || find(second)?.parentId == first;

  String _connectionId(String first, String second) {
    final endpoints = [first, second]..sort();
    return 'task-link:${jsonEncode(endpoints)}';
  }

  List<AiTaskConnection> get connections => List.unmodifiable([
    for (final child in _sessions)
      if (_canLink(child) && _canLink(find(child.parentId)))
        AiTaskConnection(
          id: child.id,
          fromId: child.parentId!,
          toId: child.id,
          isHierarchy: true,
        ),
    for (final connection in _supplementalConnections.values)
      if (_canLink(find(connection.fromId)) &&
          _canLink(find(connection.toId)) &&
          !_isHierarchyPair(connection.fromId, connection.toId))
        connection,
  ]);

  void _validateConnectionEndpoints(String fromId, String toId) {
    if (_disposed) throw StateError('Workspace is closed');
    if (fromId == toId || !_canLink(find(fromId)) || !_canLink(find(toId))) {
      throw StateError(
        'Only distinct active root or child agents may be connected',
      );
    }
  }

  AiAgentWorkspace _topTask(String id) {
    var task = find(id)!;
    var parent = find(task.parentId);
    while (parent != null) {
      task = parent;
      parent = find(task.parentId);
    }
    return task;
  }

  /// Preview role and hierarchy changes without modifying either tree.
  AiTaskTreeMerge? connectionMergeFor(String fromId, String toId) {
    _validateConnectionEndpoints(fromId, toId);
    if (_rootId(fromId) == _rootId(toId)) return null;
    final sourceRoot = _topTask(fromId);
    final targetRoot = _topTask(toId);
    if (!_canLink(sourceRoot) || !_canLink(targetRoot)) {
      throw StateError('Only active agent trees may be merged');
    }
    // An orphan child tree must not replace an existing actual root.
    final preserveTarget =
        sourceRoot.kind != AiWorkspaceKind.primary &&
        targetRoot.kind == AiWorkspaceKind.primary;
    final attached = preserveTarget ? sourceRoot : find(toId)!;
    final branch = <String>{};
    void collectBranch(String id) {
      if (!branch.add(id)) return;
      for (final child in childrenOf(id)) {
        collectBranch(child.id);
      }
    }

    collectBranch(attached.id);
    final detachedPeers =
        _supplementalConnections.values
            .where(
              (edge) =>
                  branch.contains(edge.fromId) != branch.contains(edge.toId),
            )
            .map((edge) => edge.id)
            .toList()
          ..sort();
    return AiTaskTreeMerge(
      fromId: fromId,
      toId: toId,
      sourceRootId: sourceRoot.id,
      targetRootId: targetRoot.id,
      rootId: attached.id,
      previousParentId: attached.parentId,
      detachedConnectionIds: List.unmodifiable(detachedPeers),
      parentId: preserveTarget ? toId : fromId,
      changesRole: attached.kind != AiWorkspaceKind.permanent,
      fromKind: find(fromId)!.kind,
      toKind: find(toId)!.kind,
      sourceRootKind: sourceRoot.kind,
      targetRootKind: targetRoot.kind,
    );
  }

  /// Same-tree links preserve roles; cross-tree joins require a current approval.
  AiTaskConnection connectTasks(
    String fromId,
    String toId, {
    AiTaskTreeMerge? confirmedMerge,
  }) {
    final plan = connectionMergeFor(fromId, toId);
    if (plan != null) {
      if (confirmedMerge == null || !plan.matches(confirmedMerge)) {
        throw StateError(
          'Confirm the current agent tree merge before connecting',
        );
      }
      // Approval is checked before changing any roles.
      for (final id in plan.detachedConnectionIds) {
        _supplementalConnections.remove(id);
      }
      reparent(plan.rootId, plan.parentId);
    } else if (confirmedMerge != null) {
      throw StateError('The agent tree merge approval is no longer current');
    }
    return _insertConnection(fromId, toId);
  }

  /// Restore/copy already-authorized snapshots without silently changing roles.
  AiTaskConnection _insertConnection(String fromId, String toId) {
    _validateConnectionEndpoints(fromId, toId);
    for (final connection in connections) {
      if ((connection.fromId == fromId && connection.toId == toId) ||
          (connection.fromId == toId && connection.toId == fromId)) {
        return connection;
      }
    }
    final endpoints = [fromId, toId]..sort();
    final connection = AiTaskConnection(
      id: _connectionId(fromId, toId),
      fromId: endpoints.first,
      toId: endpoints.last,
      isHierarchy: false,
    );
    _supplementalConnections[connection.id] = connection;
    _notify();
    return connection;
  }

  /// Preview only components touched by the requested cut; unrelated saved
  /// unrelated groups are not normalized as a side effect.
  Map<String, AiWorkspaceKind> disconnectionRoleChanges(
    Iterable<String> ids, {
    Iterable<String> deletingTaskIds = const [],
  }) {
    final deleting = deletingTaskIds.toSet();
    final plan = _disconnectionPlan(
      ids,
      graph: deleting.isEmpty ? null : _graphAfterDeletion(deleting),
    );
    return Map.unmodifiable({
      for (final entry in plan.parents.entries)
        if (find(entry.key)!.kind !=
            (entry.value == null
                ? AiWorkspaceKind.primary
                : AiWorkspaceKind.permanent))
          entry.key: entry.value == null
              ? AiWorkspaceKind.primary
              : AiWorkspaceKind.permanent,
    });
  }

  /// Side-effect-free counterpart of removeMany's retained-root-branch policy.
  List<AiTaskConnection> _graphAfterDeletion(Set<String> selected) {
    final parents = {for (final task in _sessions) task.id: task.parentId};
    final removed = <String>{};
    void removeBranch(String id) {
      if (!removed.add(id)) return;
      for (final child in childrenOf(id)) {
        removeBranch(child.id);
      }
    }

    for (final id in selected) {
      if (find(id)?.kind != AiWorkspaceKind.primary) removeBranch(id);
    }
    for (final id in selected) {
      if (find(id)?.kind != AiWorkspaceKind.primary) continue;
      final replacement = _replacementRootFor(id, removed);
      if (replacement != null) {
        parents[replacement.id] = null;
        for (final child in childrenOf(id)) {
          if (child.kind == AiWorkspaceKind.permanent &&
              !removed.contains(child.id) &&
              child.id != replacement.id) {
            parents[child.id] = replacement.id;
          }
        }
      }
      removed.add(id);
      for (final child in childrenOf(id)) {
        if (parents[child.id] == id) removeBranch(child.id);
      }
    }
    return [
      for (final task in _sessions)
        if (!removed.contains(task.id) && _canLink(task))
          if (parents[task.id] case final parent?)
            if (!removed.contains(parent) && _canLink(find(parent)))
              AiTaskConnection(
                id: task.id,
                fromId: parent,
                toId: task.id,
                isHierarchy: true,
              ),
      for (final edge in _supplementalConnections.values)
        if (!removed.contains(edge.fromId) &&
            !removed.contains(edge.toId) &&
            _canLink(find(edge.fromId)) &&
            _canLink(find(edge.toId)) &&
            parents[edge.fromId] != edge.toId &&
            parents[edge.toId] != edge.fromId)
          edge,
    ];
  }

  void disconnectConnection(String id) => disconnectConnections([id]);

  /// Remove a selection as one graph edit and publish its final roles once.
  void disconnectConnections(Iterable<String> ids) {
    if (_disposed) return;
    final plan = _disconnectionPlan(ids);
    if (plan.parents.isEmpty) return;
    final oldRoots = {for (final id in plan.parents.keys) id: _rootId(id)};
    for (final entry in plan.parents.entries) {
      final task = find(entry.key)!;
      task.parentId = entry.value;
      task.kind = entry.value == null
          ? AiWorkspaceKind.primary
          : AiWorkspaceKind.permanent;
    }
    _supplementalConnections
      ..clear()
      ..addAll(plan.peers);
    final budgetMoves = {
      for (final id in plan.parents.keys) (oldRoots[id]!, _rootId(id)),
    };
    for (final (oldRoot, newRoot) in budgetMoves) {
      if (oldRoot != newRoot) _mergeBudget(oldRoot, newRoot);
    }
    _notify();
  }

  ({Map<String, String?> parents, Map<String, AiTaskConnection> peers})
  _disconnectionPlan(Iterable<String> ids, {List<AiTaskConnection>? graph}) {
    final removed = ids.toSet();
    final before = graph ?? connections;
    final cut = before.where((edge) => removed.contains(edge.id)).toList();
    if (cut.isEmpty) return (parents: {}, peers: {});
    final remaining = before
        .where((edge) => !removed.contains(edge.id))
        .toList();
    final adjacency = <String, List<AiTaskConnection>>{};
    for (final edge in remaining) {
      adjacency.putIfAbsent(edge.fromId, () => []).add(edge);
      adjacency.putIfAbsent(edge.toId, () => []).add(edge);
    }
    String opposite(AiTaskConnection edge, String id) =>
        edge.fromId == id ? edge.toId : edge.fromId;
    final affected = <String>{};
    void visit(String id) {
      if (!affected.add(id)) return;
      for (final edge in adjacency[id] ?? const <AiTaskConnection>[]) {
        visit(opposite(edge, id));
      }
    }

    for (final edge in cut) {
      visit(edge.fromId);
      visit(edge.toId);
    }
    final parents = <String, String?>{};
    final selectedEdges = <String>{};
    final pending = affected.toSet();
    while (pending.isNotEmpty) {
      final component = <String>{};
      void collect(String id) {
        if (!component.add(id)) return;
        for (final edge in adjacency[id] ?? const <AiTaskConnection>[]) {
          collect(opposite(edge, id));
        }
      }

      collect(pending.first);
      pending.removeAll(component);
      final members = _sessions.where((task) => component.contains(task.id));
      final root =
          members
              .where((task) => task.kind == AiWorkspaceKind.primary)
              .firstOrNull ??
          members
              .where(
                (task) => !remaining.any(
                  (edge) => edge.isHierarchy && edge.toId == task.id,
                ),
              )
              .firstOrNull ??
          members.first;
      // Retain every surviving structural edge. Peer edges join those small
      // trees, reversing a structural path only if entered at a descendant.
      void attachTree(String id, String? parent) {
        if (parents.containsKey(id)) return;
        parents[id] = parent;
        for (final edge in adjacency[id] ?? const <AiTaskConnection>[]) {
          final other = opposite(edge, id);
          if (edge.isHierarchy && !parents.containsKey(other)) {
            selectedEdges.add(edge.id);
            attachTree(other, id);
          }
        }
      }

      attachTree(root.id, null);
      while (!component.every(parents.containsKey)) {
        final bridge = remaining.firstWhere(
          (edge) =>
              component.contains(edge.fromId) &&
              parents.containsKey(edge.fromId) !=
                  parents.containsKey(edge.toId),
        );
        final from = parents.containsKey(bridge.fromId)
            ? bridge.fromId
            : bridge.toId;
        selectedEdges.add(bridge.id);
        attachTree(opposite(bridge, from), from);
      }
    }
    final peers = <String, AiTaskConnection>{
      for (final entry in _supplementalConnections.entries)
        if (!removed.contains(entry.key) &&
            !affected.contains(entry.value.fromId) &&
            !affected.contains(entry.value.toId))
          entry.key: entry.value,
    };
    for (final edge in remaining) {
      if (!affected.contains(edge.fromId) || selectedEdges.contains(edge.id)) {
        continue;
      }
      final key = _connectionId(edge.fromId, edge.toId);
      peers[key] = AiTaskConnection(
        id: key,
        fromId: edge.fromId,
        toId: edge.toId,
        isHierarchy: false,
      );
    }
    return (parents: parents, peers: peers);
  }

  bool isConnected(String fromId, String toId) =>
      fromId != toId &&
      _canLink(find(fromId)) &&
      _canLink(find(toId)) &&
      (_isHierarchyPair(fromId, toId) ||
          _supplementalConnections.containsKey(_connectionId(fromId, toId)));

  List<AiAgentWorkspace> neighborsOf(String id) =>
      List.unmodifiable(_sessions.where((task) => isConnected(id, task.id)));

  void _pruneConnections() {
    _supplementalConnections.removeWhere(
      (_, connection) =>
          !_canLink(find(connection.fromId)) ||
          !_canLink(find(connection.toId)) ||
          _isHierarchyPair(connection.fromId, connection.toId),
    );
  }

  String _rootId(String id) {
    var node = find(id);
    final visited = <String>{};
    while (node != null && visited.add(node.id)) {
      final parentId = node.parentId;
      if (parentId == null) return node.id;
      if (parentId == 'main') return 'main';
      final parent = find(parentId);
      if (parent == null) return node.id;
      node = parent;
    }
    return id;
  }

  void select(String? id) {
    if (id != null && find(id) == null) return;
    if (_selectedId == id) return;
    _selectedId = id;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
    if (!_restoring) {
      _saveTimer ??= Timer(const Duration(milliseconds: 500), () {
        _saveTimer = null;
        _saveNow();
      });
    }
  }

  Future<void> _restore() async {
    await main.initialized;
    if (_disposed) return;
    try {
      final source = main.workspacePreferences.stringValue(storageKey, '');
      if (source.isEmpty) return;
      final decoded = jsonDecode(source);
      if (decoded is! Map ||
          decoded['version'] != 2 ||
          decoded['sessions'] is! List) {
        throw const FormatException('Invalid agent topology');
      }
      final rawRecords = decoded['sessions'] as List;
      final byId = <String, Map>{};
      for (final raw in rawRecords) {
        if (raw is! Map ||
            raw['id'] is! String ||
            !RegExp(r'^\d+-\d+$').hasMatch(raw['id'] as String) ||
            raw['id'] == 'main' ||
            byId.containsKey(raw['id']) ||
            raw['title'] is! String ||
            raw['task'] is! String ||
            raw['conversation'] is! Map<String, dynamic> ||
            !AiWorkspaceKind.values.any((k) => k.name == raw['kind']) ||
            (raw['parentId'] != null && raw['parentId'] is! String)) {
          throw const FormatException('Invalid saved agent record');
        }
        final conversation = raw['conversation'] as Map<String, dynamic>;
        if (conversation['serviceId'] is! String ||
            conversation['model'] is! String) {
          throw const FormatException('Invalid saved model selection');
        }
        final record = Map<String, dynamic>.from(raw);
        byId[record['id'] as String] = record;
      }
      final rawConnections = decoded.containsKey('connections')
          ? decoded['connections']
          : const [];
      if (rawConnections is! List) {
        throw const FormatException('Invalid saved agent connections');
      }
      final restoredConnections = <String, AiTaskConnection>{};
      for (final raw in rawConnections) {
        if (raw is! Map || raw['fromId'] is! String || raw['toId'] is! String) {
          throw const FormatException('Invalid saved agent connection');
        }
        final fromId = raw['fromId'] as String;
        final toId = raw['toId'] as String;
        final from = byId[fromId];
        final to = byId[toId];
        if (fromId == toId ||
            from == null ||
            to == null ||
            from['closed'] == true ||
            to['closed'] == true) {
          throw const FormatException('Invalid saved connection endpoints');
        }
        final id = _connectionId(fromId, toId);
        if (restoredConnections.containsKey(id)) {
          throw const FormatException('Duplicate saved agent connection');
        }
        final endpoints = [fromId, toId]..sort();
        restoredConnections[id] = AiTaskConnection(
          id: id,
          fromId: endpoints.first,
          toId: endpoints.last,
          isHierarchy: false,
        );
      }
      final records = <Map>[];
      final visiting = <String>{};
      final visited = <String>{};
      void visit(String id) {
        if (visited.contains(id)) return;
        if (!visiting.add(id)) {
          throw const FormatException('Agent topology contains a cycle');
        }
        final raw = byId[id]!;
        final parentId = raw['parentId'] as String?;
        if (raw['kind'] == 'primary' && parentId != null) {
          throw const FormatException('A main agent cannot have a parent');
        }
        if (parentId != null && parentId != 'main') {
          final parent = byId[parentId];
          if (parent == null) {
            throw const FormatException('Invalid saved parent agent');
          }
          visit(parentId);
        }
        visiting.remove(id);
        visited.add(id);
        records.add(raw);
      }

      for (final id in byId.keys) {
        visit(id);
      }
      for (final raw in records) {
        if (_disposed) return;
        try {
          if (raw['id'] is! String ||
              raw['title'] is! String ||
              raw['task'] is! String ||
              find(raw['id'] as String) != null ||
              raw['conversation'] is! Map<String, dynamic>) {
            continue;
          }
          final kind = AiWorkspaceKind.values
              .where((k) => k.name == raw['kind'])
              .firstOrNull;
          if (kind == null) continue;
          final parentId = raw['parentId'] as String?;
          if (parentId != null &&
              parentId != 'main' &&
              find(parentId) == null) {
            throw const FormatException('Saved parent could not be restored');
          }
          final conversation = raw['conversation'] as Map<String, dynamic>;
          final service = main.services
              .where((service) => service.id == conversation['serviceId'])
              .firstOrNull;
          final model = conversation['model'];
          if (conversation['serviceId'] is! String || model is! String) {
            throw const FormatException('Invalid saved model selection');
          }
          final assistant = main.forkForWorkspace();
          try {
            if (service == null ||
                !service.models.contains(model) ||
                !main.hasServiceKey(service.id)) {
              assistant.markWorkspaceSelectionUnavailable(
                serviceId: conversation['serviceId'] as String,
                model: model,
              );
            } else {
              await assistant.selectModel(service.id, model);
              final effort = AiReasoningEffort.values
                  .where((e) => e.name == conversation['effort'])
                  .firstOrNull;
              if (effort != null) await assistant.setReasoningEffort(effort);
            }
            if (_disposed) {
              assistant.dispose();
              return;
            }
            assistant.setPermissions(AiPermissions());
            assistant.restoreWorkspaceConversation(conversation);
            final session = AiAgentWorkspace(
              id: raw['id'] as String,
              title: raw['title'] as String,
              task: raw['task'] as String,
              kind: kind,
              parentId: parentId,
              assistant: assistant,
              createdAt:
                  DateTime.tryParse(raw['createdAt'] as String? ?? '') ??
                  DateTime.now(),
            );

            _register(session);
          } catch (_) {
            assistant.dispose();
            persistenceError = const FormatException(
              'A saved agent conversation could not be restored.',
            );
          }
        } catch (error) {
          persistenceError = error;
        }
      }
      _supplementalConnections.addAll(restoredConnections);
      _pruneConnections();
      final savedSelection = decoded['selectedId'];
      _selectedId = savedSelection is String && find(savedSelection) != null
          ? savedSelection
          : _sessions.firstOrNull?.id;
    } catch (error) {
      persistenceError = error;
    } finally {
      _restoring = false;
      _notify();
    }
  }

  void _saveNow() {
    if (_restoring || persistenceError != null) return;
    try {
      final source = jsonEncode({
        'version': 2,
        'selectedId': _selectedId,
        'connections': [
          for (final connection in connections.where((c) => !c.isHierarchy))
            {'fromId': connection.fromId, 'toId': connection.toId},
        ],
        'sessions': [
          for (final session in _sessions)
            {
              'id': session.id,
              'title': session.title,
              'task': session.task,
              'kind': session.kind.name,
              'closed': session.closed,
              'parentId': session.parentId,
              'createdAt': session.createdAt.toIso8601String(),
              'conversation': session.assistant.snapshotWorkspaceConversation(),
            },
        ],
      });
      main.workspacePreferences.setValue(storageKey, source);
    } catch (error) {
      persistenceError = error;
    }
  }

  Future<void> flush() async {
    await initialized;
    _saveTimer?.cancel();
    _saveTimer = null;
    _saveNow();
    await main.workspacePreferences.flush();
  }

  void _register(AiAgentWorkspace session) {
    final assistant = session.assistant;
    assistant.workspaceTurnAllowed = () => !_disposed && !session.closed;
    assistant.onWorkspaceHumanMessage = () {
      final group = _rootId(session.id);
      _deliveryCounts.remove(group);
      _deliveredMessages.remove(group);
    };
    assistant.workspaceToolDefinitions = _tools;
    assistant.workspaceToolHandler = (name, args) =>
        _executeTool(session.id, name, args);
    assistant.addListener(_notify);
    _sessions.add(session);
  }

  Future<AiAgentWorkspace> createPrimary({
    required String title,
    required String task,
    String? serviceId,
    String? model,
    AiPermissions? permissions,
    AiReasoningEffort? reasoningEffort,
  }) => create(
    title: title,
    task: task,
    kind: AiWorkspaceKind.primary,
    serviceId: serviceId,
    model: model,
    permissions: permissions,
    reasoningEffort: reasoningEffort,
  );

  Future<AiAgentWorkspace> create({
    required String title,
    required String task,
    String? parentId,
    AiWorkspaceKind kind = AiWorkspaceKind.permanent,
    String? serviceId,
    String? model,
    AiPermissions? permissions,
    AiReasoningEffort? reasoningEffort,
    bool modelInitiated = false,
    bool startImmediately = true,
  }) async {
    await initialized;
    if (_disposed) throw StateError('Workspace is closed');
    if (modelInitiated && permissions != null) {
      throw StateError('Model-created agents must inherit parent permissions');
    }
    if (task.trim().isEmpty || title.length > 200 || task.length > 100000) {
      throw const FormatException(
        'Agent content is required; title is optional',
      );
    }
    final parent = parentId == null || parentId == 'main'
        ? null
        : find(parentId);
    if (parentId != null &&
        parentId != 'main' &&
        (parent == null || parent.closed)) {
      throw StateError('A root or child agent is required');
    }
    if (kind == AiWorkspaceKind.primary && parentId != null) {
      throw StateError('A main agent cannot have a parent');
    }
    final template = parent?.assistant ?? main;
    if (!template.hasApiKey && serviceId == null) {
      throw StateError('Configure a model service first');
    }
    if (modelInitiated && (serviceId == null) != (model == null)) {
      throw const FormatException(
        'Specify both service_id and model from list_agent_models, or omit both to inherit',
      );
    }
    final worker = template.forkForWorkspace();
    if (serviceId != null || model != null) {
      try {
        final selectedId = serviceId ?? template.selectedService?.id;
        final service = template.services
            .where((s) => s.id == selectedId)
            .firstOrNull;
        if (service == null || !template.hasServiceKey(selectedId)) {
          throw StateError('Unknown model service');
        }
        if (service.models.isEmpty ||
            (model != null && !service.models.contains(model))) {
          throw StateError(
            'Unknown model for this service; query list_agent_models and use exact IDs',
          );
        }
        await worker.selectModel(service.id, model ?? service.models.first);
      } catch (_) {
        worker.dispose();
        rethrow;
      }
    }
    final requestedTitle = title.trim();
    final fallback = task.trim().replaceAll(RegExp(r'\s+'), ' ');
    final resolvedTitle = requestedTitle.isNotEmpty
        ? requestedTitle
        : String.fromCharCodes(fallback.runes.take(32));
    if (_disposed ||
        (parent != null && (find(parent.id) != parent || parent.closed))) {
      worker.dispose();
      throw StateError('Workspace or parent agent is closed');
    }
    if (reasoningEffort != null) {
      try {
        await worker.setReasoningEffort(reasoningEffort);
      } catch (_) {
        worker.dispose();
        rethrow;
      }
    }
    if (permissions != null) worker.setPermissions(permissions);
    final session = AiAgentWorkspace(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      title: resolvedTitle,
      task: task.trim(),
      assistant: worker,
      parentId: parentId,
      kind: kind,
      createdAt: DateTime.now(),
    );
    _register(session);
    _selectedId ??= session.id;
    if (requestedTitle.isEmpty) {
      unawaited(_nameTask(session));
    }
    if (startImmediately && modelInitiated && parentId != null) {
      _recordTransfer(parentId, session.id);
      unawaited(
        session.assistant
            .receiveAgentMessage(
              sourceId: parentId,
              sourceTitle: parent?.title ?? 'main',
              content: session.task,
            )
            .whenComplete(_notify),
      );
    } else if (startImmediately) {
      _run(session, session.task);
    }
    _notify();
    return session;
  }

  Future<void> _nameTask(AiAgentWorkspace session) async {
    final token = Object();
    _pendingNames[session.id] = token;
    final title = await session.assistant.suggestTaskTitle(session.task);
    if (_disposed || _pendingNames[session.id] != token) return;
    _pendingNames.remove(session.id);
    if (title == null || !identical(find(session.id), session)) return;
    session.title = title;
    _notify();
  }

  void _run(AiAgentWorkspace session, String message) {
    unawaited(session.assistant.sendMessage(message).whenComplete(_notify));
  }

  Future<void> _waitFor(
    List<AiAgentWorkspace> targets,
    int milliseconds,
  ) async {
    if (milliseconds <= 0 || _disposed) return;
    bool ready() => targets.every(
      (s) => !_sessions.contains(s) || !s.busy || s.needsAttention,
    );
    if (ready()) return;
    final completer = Completer<void>();
    void listener() {
      if (!completer.isCompleted && (_disposed || ready())) {
        completer.complete();
      }
    }

    addListener(listener);
    final timer = Timer(Duration(milliseconds: milliseconds), () {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      listener();
      await completer.future;
    } finally {
      timer.cancel();
      if (!_disposed) removeListener(listener);
    }
  }

  Future<void> send(String id, String message) async {
    final session = find(id);
    if (session == null || session.closed) {
      throw StateError('Unknown or closed agent');
    }
    if (message.trim().isEmpty) {
      throw const FormatException('A message is required');
    }
    _run(session, message.trim());
    _notify();
  }

  void stop(String id) {
    find(id)?.assistant.stopGeneration();
    _notify();
  }

  void stopAll() {
    for (final session in _sessions) {
      session.assistant.stopGeneration();
    }
    _notify();
  }

  /// Explicitly separate a hierarchy subtree as its own task group.
  /// Call only after confirmation: cross-boundary peer links are detached,
  /// while descendant roles, internal links and conversation state remain.
  void promoteToRoot(String id) {
    if (_disposed) throw StateError('Workspace is closed');
    final task = find(id);
    if (!_canLink(task)) {
      throw StateError('Only active root or child agents may be promoted');
    }
    // Do not reinterpret cross-tree links on an existing main agent.
    if (task!.kind == AiWorkspaceKind.primary) return;
    final subtree = <String>{};
    void include(String taskId) {
      if (!subtree.add(taskId)) return;
      for (final child in childrenOf(taskId)) {
        include(child.id);
      }
    }

    include(id);
    _supplementalConnections.removeWhere(
      (_, connection) =>
          subtree.contains(connection.fromId) !=
          subtree.contains(connection.toId),
    );
    // This retains the existing conservative automatic-message budget handling
    // and notifies after both the boundary cut and role change are complete.
    reparent(id, null);
  }

  /// 编辑可视化智能体的单上级归属。
  void reparent(String childId, String? parentId, {bool preserveKind = false}) {
    if (_disposed) throw StateError('Workspace is closed');
    final child = find(childId);
    final parent = find(parentId);
    if (child == null ||
        (parentId != null && (parent == null || parent.closed))) {
      throw StateError('Only active root or child agents may be connected');
    }
    if (preserveKind &&
        child.kind == AiWorkspaceKind.primary &&
        parentId != null) {
      throw StateError('A main agent cannot have a parent');
    }
    if (childId == parentId) throw StateError('A agent cannot parent itself');
    var ancestor = parent;
    while (ancestor != null) {
      if (ancestor.id == childId) {
        throw StateError('Agent connections cannot contain cycles');
      }
      ancestor = find(ancestor.parentId);
    }
    if (child.parentId == parentId &&
        (preserveKind ||
            parentId != null ||
            child.kind == AiWorkspaceKind.primary)) {
      return;
    }
    final oldRoot = _rootId(childId);
    final newRoot = parent == null ? childId : _rootId(parent.id);
    if (oldRoot != newRoot) {
      _mergeBudget(
        oldRoot,
        newRoot,
        removeSource: parent != null && oldRoot == child.id,
      );
    }
    child.parentId = parentId;
    _pruneConnections();
    if (!preserveKind) {
      child.kind = parentId == null
          ? AiWorkspaceKind.primary
          : AiWorkspaceKind.permanent;
    }
    _notify();
  }

  // 编辑分支保留来源额度，复制到新树；同树移动不调用，避免重复累计。
  void _mergeBudget(
    String sourceId,
    String targetId, {
    bool removeSource = false,
  }) {
    if (sourceId == targetId) return;
    final count = _deliveryCounts[sourceId];
    if (count != null) {
      _deliveryCounts[targetId] = ((_deliveryCounts[targetId] ?? 0) + count)
          .clamp(0, maximumAutomaticMessages);
    }
    final messages = _deliveredMessages[sourceId];
    if (messages != null) {
      (_deliveredMessages[targetId] ??= {}).addAll(messages);
    }
    if (removeSource) {
      _deliveryCounts.remove(sourceId);
      _deliveredMessages.remove(sourceId);
    }
  }

  /// 删除主智能体时接任的直属子智能体；用于界面说明将保留哪些智能体。
  AiAgentWorkspace? replacementRootFor(String id) =>
      _replacementRootFor(id, const {});

  /// Preview the same promotions as removeMany, excluding selected subtrees.
  Map<String, AiAgentWorkspace> rootReplacementsForDeletion(
    Iterable<String> ids,
  ) {
    final selected = ids
        .toSet()
        .map(find)
        .whereType<AiAgentWorkspace>()
        .toList();
    final forced = <String>{};
    void exclude(AiAgentWorkspace task) {
      if (!forced.add(task.id)) return;
      for (final child in childrenOf(task.id)) {
        exclude(child);
      }
    }

    for (final task in selected) {
      if (task.kind != AiWorkspaceKind.primary) exclude(task);
    }
    return Map.unmodifiable({
      for (final task in selected)
        if (task.kind == AiWorkspaceKind.primary)
          if (_replacementRootFor(task.id, forced) case final replacement?)
            task.id: replacement,
    });
  }

  AiAgentWorkspace? _replacementRootFor(String id, Set<String> excluded) {
    if (find(id)?.kind != AiWorkspaceKind.primary) return null;
    AiAgentWorkspace? replacement;
    for (final child in childrenOf(id)) {
      if (child.kind != AiWorkspaceKind.permanent ||
          excluded.contains(child.id)) {
        continue;
      }
      if (replacement == null ||
          !child.createdAt.isBefore(replacement.createdAt)) {
        replacement = child;
      }
    }
    return replacement;
  }

  /// 从当前会话创建独立分支，继承历史与配置，不复制下级或活动操作。
  Future<AiAgentWorkspace> duplicate(String id, {required String title}) async {
    final original = find(id);
    if (original == null || original.closed) {
      throw StateError('Only root and child agents may be duplicated');
    }
    final effort = original.assistant.reasoningEffort;
    final conversation = original.assistant.snapshotConversationFork();
    final copy = await create(
      title: title,
      task: original.task,
      parentId: original.parentId,
      kind: original.kind,
      serviceId: original.serviceId,
      model: original.model,
      permissions: original.assistant.permissions,
      startImmediately: false,
    );
    await copy.assistant.setReasoningEffort(effort);
    copy.assistant.restoreConversationFork(conversation);
    return copy;
  }

  List<AiTaskCardCopy> copyCards(Iterable<String> ids) => [
    for (final id in ids.toSet())
      if (find(id) case final session?)
        if (!session.closed)
          AiTaskCardCopy(
            session,
            connectedSourceIds: [
              for (final connection in _supplementalConnections.values)
                if (connection.fromId == session.id)
                  connection.toId
                else if (connection.toId == session.id)
                  connection.fromId,
            ],
          ),
  ];

  /// Number copied names without stacking suffixes or colliding with tasks.
  String nextCopyTitle(String original) {
    final suffixPattern = RegExp(r' \((\d+)\)$');
    var stem = original;
    var number = 2;
    while (true) {
      final match = suffixPattern.firstMatch(stem);
      final previous = match == null ? null : int.tryParse(match.group(1)!);
      if (previous == null || previous < 2) break;
      if (number <= previous) number = previous + 1;
      stem = stem.substring(0, match!.start);
    }
    final used = _sessions.map((task) => task.title).toSet();
    while (used.contains('$stem ($number)')) {
      number++;
    }
    final title = '$stem ($number)';
    // Retain the full original name when a suffix exceeds the name limit.
    return title.length <= 200 ? title : original;
  }

  Future<List<AiAgentWorkspace>> pasteCards(
    List<AiTaskCardCopy> cards, {
    required String Function(String) titleForCopy,
  }) async {
    final pending = [...cards];
    final copies = <String, AiAgentWorkspace>{};
    try {
      while (pending.isNotEmpty) {
        final card = pending.firstWhere(
          (card) =>
              card.parentId == null ||
              copies.containsKey(card.parentId) ||
              !pending.any((other) => other.sourceId == card.parentId),
        );
        final originalParent = find(card.parentId);
        final parentId =
            copies[card.parentId]?.id ??
            (originalParent != null && !originalParent.closed
                ? originalParent.id
                : null);
        final copy = await create(
          title: titleForCopy(card.title),
          task: card.task,
          parentId: parentId,
          kind: parentId == null ? card.kind : AiWorkspaceKind.permanent,
          serviceId: card.serviceId,
          model: card.model,
          permissions: card.permissions,
          startImmediately: false,
        );
        copies[card.sourceId] = copy;
        await copy.assistant.setReasoningEffort(card.effort);
        copy.assistant.restoreConversationFork(card.conversation);
        pending.remove(card);
      }
      for (final card in cards) {
        for (final neighbor in card.connectedSourceIds) {
          if (copies[neighbor] case final peer?) {
            _insertConnection(copies[card.sourceId]!.id, peer.id);
          }
        }
      }
      return [for (final card in cards) copies[card.sourceId]!];
    } catch (_) {
      removeMany(copies.values.map((copy) => copy.id));
      rethrow;
    }
  }

  /// 用户重命名只更新显示名称，保留会话身份、权限和智能体关系。
  void rename(String id, String title) {
    if (_disposed) throw StateError('Workspace is closed');
    final session = find(id);
    if (session == null) throw StateError('Unknown agent');
    final value = title.trim();
    if (value.isEmpty || value.length > 200) {
      throw const FormatException(
        'A agent name of 1 to 200 characters is required',
      );
    }
    _pendingNames.remove(id);
    if (session.title == value) return;
    session.title = value;
    _notify();
  }

  void remove(String id) => removeMany([id]);

  /// 主智能体保留未明确删除的长期分支；显式选择的非主智能体删除整棵子树。
  void removeMany(Iterable<String> ids) {
    if (_disposed) return;
    final selected = ids
        .toSet()
        .map(find)
        .whereType<AiAgentWorkspace>()
        .toList();
    if (selected.isEmpty) return;
    final forced = <String>{};
    void mark(AiAgentWorkspace node) {
      if (!forced.add(node.id)) return;
      for (final child in childrenOf(node.id)) {
        mark(child);
      }
    }

    for (final session in selected) {
      if (session.kind != AiWorkspaceKind.primary) mark(session);
    }
    AiAgentWorkspace? selectionFallback;
    final rootRemovals = <AiAgentWorkspace>[];
    for (final session in selected.where(
      (s) => s.kind == AiWorkspaceKind.primary,
    )) {
      final replacement = _replacementRootFor(session.id, forced);
      if (replacement != null) {
        final permanentChildren = childrenOf(session.id)
            .where(
              (child) =>
                  child.kind == AiWorkspaceKind.permanent &&
                  !forced.contains(child.id),
            )
            .toList();
        replacement.kind = AiWorkspaceKind.primary;
        replacement.parentId = null;
        for (final child in permanentChildren) {
          if (child != replacement) child.parentId = replacement.id;
        }
        _mergeBudget(session.id, replacement.id, removeSource: true);
        if (_selectedId == session.id) selectionFallback = replacement;
      }
      rootRemovals.add(session);
    }
    final removing = <AiAgentWorkspace>[];
    final visited = <String>{};
    void collect(AiAgentWorkspace node) {
      if (!visited.add(node.id)) return;
      for (final child in childrenOf(node.id)) {
        collect(child);
      }
      removing.add(node);
    }

    for (final session in rootRemovals) {
      collect(session);
    }
    for (final id in forced) {
      final session = find(id);
      if (session != null) collect(session);
    }
    for (final item in removing) {
      _sessions.remove(item);
      _detachForEdit(item);
      _deliveryCounts.remove(item.id);
      _deliveredMessages.remove(item.id);
    }
    _pruneConnections();
    if (visited.contains(_selectedId)) {
      _selectedId = selectionFallback?.id ?? _sessions.firstOrNull?.id;
    }
    _notify();
  }

  // 公共入口供界面与测试查询；模型始终使用绑定来源主智能体的私有闭包。
  Future<Map<String, Object?>> executeTool(
    String name,
    Map<String, Object?> args,
  ) => _executeTool(null, name, args);
  Future<Map<String, Object?>> _executeTool(
    String? sourceId,
    String name,
    Map<String, Object?> args,
  ) async {
    final source = sourceId == null || sourceId == 'main'
        ? null
        : find(sourceId);
    if (sourceId != null &&
        sourceId != 'main' &&
        (source == null || source.closed)) {
      throw StateError('Unknown source agent');
    }
    bool connected(AiAgentWorkspace target) =>
        sourceId == null ||
        target.parentId == sourceId ||
        source?.parentId == target.id ||
        isConnected(sourceId, target.id);
    AiAgentWorkspace checked(String id) {
      final session = find(id);
      if (session == null || !connected(session)) {
        throw StateError('Unknown agent connected to this agent');
      }
      return session;
    }

    switch (name) {
      case 'list_agent_models':
        final template = source?.assistant ?? main;
        return {
          'inherited_service_id': template.selectedService?.id,
          'inherited_model': template.selectedModel,
          'services': [
            for (final service in template.services)
              if (template.hasServiceKey(service.id) &&
                  service.models.isNotEmpty)
                {
                  'service_id': service.id,
                  'service_name': service.name,
                  'models': service.models,
                },
          ],
        };
      case 'spawn_agent':
        if (args.containsKey('kind')) {
          throw const FormatException('Agent kind is not a spawn parameter');
        }
        final session = await create(
          title: args['title'] as String? ?? '',
          task: args['task'] as String,
          parentId: sourceId ?? 'main',
          kind: AiWorkspaceKind.permanent,
          serviceId: args['service_id'] as String?,
          model: args['model'] as String?,
          modelInitiated: true,
        );
        return session.toToolResult();
      case 'list_agents':
        return {
          'agents': [
            for (final s in _sessions.where((s) => connected(s)))
              _observedResult(s, sourceId),
          ],
        };
      case 'open_agent':
        final target = checked(args['agent_id'] as String);
        if (target.closed) throw StateError('The target agent is closed');
        if (activeConversationId != sourceId || sourceId == null) {
          return {'navigation_requested': false, ...target.toToolResult()};
        }
        _navigationRequest = (
          revision: ++_navigationRevision,
          sourceId: sourceId,
          targetId: target.id,
        );
        _notify();
        return {'navigation_requested': true, ...target.toToolResult()};
      case 'send_agent_message':
        final target = checked(args['agent_id'] as String);
        if (target.closed) throw StateError('The target agent is closed');
        final text = (args['message'] as String).trim();
        if (text.isEmpty || text.length > 100000) {
          throw const FormatException('A bounded message is required');
        }
        final group = source == null
            ? sourceId ?? 'manual'
            : _rootId(source.id);
        final deliveryKey = jsonEncode([sourceId, target.id, text]);
        if (_deliveredMessages[group]?.contains(deliveryKey) == true) {
          return {
            'delivered': false,
            'duplicate': true,
            ...target.toToolResult(),
          };
        }
        if ((_deliveryCounts[group] ?? 0) >= maximumAutomaticMessages) {
          throw StateError(
            'Automatic message budget reached; wait for user input',
          );
        }
        _recordTransfer(sourceId, target.id);
        _deliveryCounts[group] = (_deliveryCounts[group] ?? 0) + 1;
        (_deliveredMessages[group] ??= {}).add(deliveryKey);
        unawaited(
          target.assistant
              .receiveAgentMessage(
                sourceId: sourceId ?? 'manual',
                sourceTitle: source?.title ?? 'main',
                content: text,
              )
              .whenComplete(_notify),
        );
        return {'delivered': true, ...target.toToolResult()};
      case 'stop_agent':
        final target = checked(args['agent_id'] as String);
        if (target.kind != AiWorkspaceKind.permanent ||
            target.parentId != (sourceId ?? 'main')) {
          throw StateError('Only an owned child agent may be stopped');
        }
        target.assistant.closeWorkspaceRuntime();
        _notify();
        return target.toToolResult();
      case 'delete_agent':
        final target = checked(args['agent_id'] as String);
        if (target.kind != AiWorkspaceKind.permanent ||
            target.parentId != (sourceId ?? 'main')) {
          throw StateError('Only an owned child agent may be deleted');
        }
        final deleting = <String>[];
        void collectDeleted(String id) {
          deleting.add(id);
          for (final child in childrenOf(id)) {
            collectDeleted(child.id);
          }
        }
        collectDeleted(target.id);
        remove(target.id);
        return {
          'agent_id': target.id,
          'status': 'deleted',
          'deleted_agent_ids': deleting,
        };
      case 'wait_agents':
        final ids = (args['agent_ids'] as List).cast<String>();
        if (ids.isEmpty || ids.length > 16) {
          throw StateError('Agent ids are required');
        }
        final targets = [for (final id in ids) checked(id)];
        final wait = ((args['wait_ms'] as num?)?.toInt() ?? 1000).clamp(
          0,
          5000,
        );
        await _waitFor(targets, wait);
        return {
          'agents': [
            for (final s in targets)
              _sessions.contains(s)
                  ? _observedResult(s, sourceId)
                  : {'agent_id': s.id, 'status': 'closed'},
          ],
        };
      default:
        throw StateError('Unknown workspace tool');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _saveNow();
    _disposed = true;
    for (final timer in _transferTimers.values) {
      timer.cancel();
    }
    _transferTimers.clear();
    _transfers.dispose();
    notifyListeners();
    main.workspaceToolDefinitions = const [];
    main.workspaceToolHandler = null;
    for (final session in _sessions) {
      session.assistant.removeListener(_notify);
      session.assistant.dispose();
    }
    for (final task in _detachedEditTasks.values) {
      task.assistant.dispose();
    }
    _detachedEditTasks.clear();
    _editSnapshots.clear();
    _sessions.clear();
    _supplementalConnections.clear();
    super.dispose();
  }
}

Map<String, Object?> _tool(
  String name,
  String description,
  Map<String, Object?> properties,
  List<String> required,
) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': {
      'type': 'object',
      'properties': properties,
      'required': required,
      'additionalProperties': false,
    },
  },
};
final _tools = [
  _tool(
    'list_agent_models',
    'List configured model services and exact model IDs available for child agents, without credentials. If a requested model or service is ambiguous, ask the user with request_user_input before spawning; do not guess or silently substitute.',
    {},
    [],
  ),
  _tool(
    'spawn_agent',
    'Create a visible child agent in the workflow. Users may open, continue, stop, or delete it. Children may delegate further. To use another configured model, query list_agent_models and pass both exact service_id and model; omit both to inherit, never silently substitute. Permissions inherit. Returns immediately; collect results with wait_agents/list_agents. The owning parent may stop or delete its direct children.',
    {
      'title': {
        'type': 'string',
        'description':
            'Optional agent name. When omitted or empty, the selected model generates a name from work instructions.',
      },
      'task': {'type': 'string'},
      'service_id': {
        'type': 'string',
        'description':
            'Exact service_id from list_agent_models; required together with model.',
      },
      'model': {
        'type': 'string',
        'description':
            'Exact model ID within the selected service; required together with service_id.',
      },
    },
    ['task'],
  ),
  _tool(
    'list_agents',
    'List directly connected agents with exact agent_id, title, URL and states/results. To offer a clickable agent reference in a reply, use its returned URL in a Markdown link; never invent IDs or URLs.',
    {},
    [],
  ),
  _tool(
    'open_agent',
    'Request opening a directly connected agent conversation in the user interface. Use only when the user asks to navigate; this does not send a message or execute the target agent. Use an exact agent_id returned by list_agents or spawn_agent. Resolve ambiguous names with request_user_input instead of guessing. Only requests from the conversation currently being viewed are followed; background agents do not move the user away.',
    {
      'agent_id': {'type': 'string'},
    },
    ['agent_id'],
  ),
  _tool(
    'send_agent_message',
    'Send a message to a directly connected agent in either direction. Source identity is attached; it is not user authorization. Returns immediately, queues if busy, and does not automatically reply. Duplicate messages are suppressed; a collaboration chain allows at most 12 deliveries until user input.',
    {
      'agent_id': {'type': 'string'},
      'message': {'type': 'string'},
    },
    ['agent_id', 'message'],
  ),
  _tool(
    'wait_agents',
    'Wait briefly for connected child agents and return current states/results. Approval requests appear in each agent conversation.',
    {
      'agent_ids': {
        'type': 'array',
        'items': {'type': 'string'},
        'minItems': 1,
        'maxItems': 16,
      },
      'wait_ms': {'type': 'integer', 'minimum': 0, 'maximum': 5000},
    },
    ['agent_ids'],
  ),
  _tool(
    'stop_agent',
    'Stop an owned direct child and its active operations without deleting its card or conversation. Other roots and unrelated agents cannot be stopped by this tool.',
    {
      'agent_id': {'type': 'string'},
    },
    ['agent_id'],
  ),
  _tool(
    'delete_agent',
    'Delete an owned direct child and its entire descendant branch from the workflow, stopping all active operations and removing their conversations. This is destructive; use only when no longer needed. Cannot delete the caller, a main agent, or an unrelated agent.',
    {
      'agent_id': {'type': 'string'},
    },
    ['agent_id'],
  ),
];
