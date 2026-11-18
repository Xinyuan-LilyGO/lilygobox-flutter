import 'package:flutter/foundation.dart';

import '../data/agent_package.dart';
import '../domain/memory_conflict.dart';
import 'agent_workspace_provider.dart';

class AgentStorageController extends ChangeNotifier {
  AgentStorageController(this.workspaces);
  final AiWorkspaceProvider workspaces;
  bool _disposed = false;
  AgentPackageCancellation? _transferCancellation;
  AgentPackageProgress? transferProgress;

  bool get transferActive => _transferCancellation != null;
  bool get canCancelTransfer =>
      transferActive &&
      (transferProgress?.canCancel ?? true) &&
      !_transferCancellation!.isCancelled;

  void cancelTransfer() {
    if (!canCancelTransfer) return;
    _transferCancellation!.cancel();
    notifyListeners();
  }

  /// 检查、分析与导入共用同一取消范围。
  Future<T> runTransfer<T>(Future<T> Function() operation) async {
    if (transferActive) return operation();
    _transferCancellation = AgentPackageCancellation();
    _reportProgress(const AgentPackageProgress(AgentPackageStage.preparing));
    try {
      return await operation();
    } finally {
      _transferCancellation = null;
      transferProgress = null;
      notifyListeners();
    }
  }

  void _reportProgress(AgentPackageProgress progress) {
    final previous = transferProgress;
    transferProgress = progress;
    if (previous?.stage == progress.stage &&
        previous?.canCancel == progress.canCancel &&
        previous?.fraction == null &&
        progress.fraction == null) {
      return;
    }
    if (previous?.stage == progress.stage &&
        previous?.canCancel == progress.canCancel &&
        previous?.fraction != null &&
        progress.fraction != null &&
        (previous!.fraction! * 100).floor() ==
            (progress.fraction! * 100).floor()) {
      return;
    }
    notifyListeners();
  }

  void _checkCancelled() => _transferCancellation?.throwIfCancelled();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    if (canCancelTransfer) _transferCancellation?.cancel();
    _disposed = true;
    super.dispose();
  }

  String owner = '';
  bool busy = false;
  Object? error;
  List<Map<String, Object?>> memories = const [];
  Map<String, Object?> stats = const {};
  bool hasMore = false;
  String _query = '';
  int _offset = 0;
  Future<void> refresh({String query = ''}) async {
    final storage = workspaces.main.storage;
    if (storage == null) return;
    stats = Map<String, Object?>.from(await storage.request('stats') as Map);
    final recycled = workspaces.recycledAgents.map((e) => e.id).toSet();
    stats['scopes'] = (stats['scopes'] as List? ?? [])
        .where((id) => !recycled.contains(id))
        .toList();
    final owners = {...workspaces.sessions.map((session) => session.id)};
    if (!owners.contains(owner)) owner = owners.firstOrNull ?? '';
    _query = query;
    _offset = 0;
    final rows = await storage.memories(owner, query: query, limit: 51);
    hasMore = rows.length > 50;
    memories = rows.take(50).toList();
    notifyListeners();
  }

  Future<void> loadMore() async {
    _offset += 50;
    final rows = await workspaces.main.storage!.memories(
      owner,
      query: _query,
      limit: 51,
      offset: _offset,
    );
    hasMore = rows.length > 50;
    memories = [...memories, ...rows.take(50)];
    notifyListeners();
  }

  Future<void> saveMemory(String content, {String? id}) async {
    if (workspaces.find(owner) == null) {
      throw StateError('Agent is unavailable');
    }
    await workspaces.main.storage!.putMemory(
      id: id ?? newMemoryId(),
      owner: owner,
      content: content.trim(),
    );
    await refresh();
  }

  Future<void> deleteMemory(String id) => deleteMemories({id});

  Future<void> deleteMemories(Iterable<String> ids) async {
    final targetOwner = owner;
    final targets = ids.toSet();
    final valid = await workspaces.main.storage!.request(
      'validateMemorySelection',
      {'owner': targetOwner, 'ids': targets.toList()},
    );
    if (owner != targetOwner ||
        workspaces.find(targetOwner) == null ||
        valid != true) {
      throw StateError('Memory is unavailable');
    }
    for (final id in targets) {
      if (owner != targetOwner || workspaces.find(targetOwner) == null) {
        throw StateError('Agent is unavailable');
      }
      await workspaces.main.storage!.deleteMemory(id);
    }
    await refresh(query: _query);
  }

  String suggestedExportName(
    String type, {
    DateTime? now,
    bool children = false,
  }) {
    final instant = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date =
        '${instant.year}${two(instant.month)}${two(instant.day)}${two(instant.hour)}${two(instant.minute)}';
    if (type == 'workflow') {
      return 'lilygobox-agent-workflow-package-$date.7z';
    }
    if (owner.isEmpty) throw StateError('Agent is unavailable');
    if (type == 'agent' && children) {
      return 'lilygobox-agent-workflow-package-$date.7z';
    }
    final content = switch (type) {
      'agent' => 'full',
      'chat' => 'chat',
      'memory' => 'memory',
      _ => throw ArgumentError.value(type, 'type', 'Unsupported export type'),
    };
    return 'lilygobox-agent-$owner-$content-package-$date.7z';
  }

  Future<void> export(
    String path,
    String type, {
    bool children = false,
    Set<String>? selectedIds,
  }) {
    final selection = selectedIds == null ? null : Set<String>.of(selectedIds);
    return runTransfer(
      () => _export(path, type, children: children, selectedIds: selection),
    );
  }

  Future<void> _export(
    String path,
    String type, {
    bool children = false,
    Set<String>? selectedIds,
  }) async {
    if (!{'memory', 'chat', 'agent', 'workflow'}.contains(type)) {
      throw ArgumentError.value(type, 'type', 'Unsupported export type');
    }
    if (selectedIds != null) {
      if (type != 'workflow') {
        throw ArgumentError('Selected agents require a workflow package');
      }
      if (selectedIds.isEmpty ||
          selectedIds.any((id) => workspaces.find(id) == null)) {
        throw StateError('Selected agents are unavailable');
      }
    }
    if (type != 'workflow' && workspaces.find(owner) == null) {
      throw StateError('Agent is unavailable');
    }
    _checkCancelled();
    await workspaces.flush();
    _checkCancelled();
    final storage = workspaces.main.storage!;
    final snapshot = Map<String, dynamic>.from(
      await storage.request('exportSnapshot') as Map,
    );
    _checkCancelled();
    final workflow = Map<String, Object?>.from(snapshot['workflow'] as Map);
    workflow.remove('recycleBin');
    final records = (workflow['sessions'] as List).cast<Map>();
    final ids = <String>{};
    if (selectedIds != null) {
      final available = records.map((r) => r['id'] as String).toSet();
      if (!available.containsAll(selectedIds)) {
        throw StateError('Selected agents are unavailable');
      }
      ids.addAll(selectedIds);
    } else if (type == 'agent' || type == 'chat') {
      if (!records.any((r) => r['id'] == owner)) {
        throw StateError('Agent is unavailable');
      }
      ids.add(owner);
      if (children) {
        var changed = true;
        while (changed) {
          final count = ids.length;
          ids.addAll(
            records
                .where((r) => ids.contains(r['parentId']))
                .map((r) => r['id'] as String),
          );
          changed = count != ids.length;
        }
      }
    } else {
      ids.addAll(records.map((r) => r['id'] as String));
    }
    workflow['sessions'] = [
      for (final r in records.where((r) => ids.contains(r['id'])))
        {
          ...r,
          'parentId': ids.contains(r['parentId']) ? r['parentId'] : null,
          'kind': ids.contains(r['parentId'])
              ? r['kind']
              : AiWorkspaceKind.primary.name,
          'conversation': Map<String, Object?>.from(r['conversation'] as Map)
            ..remove('workspaceRelationship')
            ..remove('pendingWorkspaceEvents'),
        },
    ];
    workflow['connections'] = [
      for (final e in workflow['connections'] as List)
        if (ids.contains(e['fromId']) && ids.contains(e['toId'])) e,
    ];
    workspaces.normalizeWorkflowData(workflow);
    workflow['canvas'] = {
      for (final e in (workflow['canvas'] as Map).entries)
        if (ids.contains(e.key)) e.key: e.value,
    };
    if (!ids.contains(workflow['selectedId'])) workflow['selectedId'] = null;
    final all = (snapshot['memories'] as List).cast<Map>();
    final selected = type == 'memory'
        ? all.where((m) => m['owner'] == owner)
        : type == 'chat'
        ? <Map>[]
        : all.where((m) => ids.contains(m['owner']));
    final selectedMemories = [
      for (final memory in selected) {...memory, 'source': '{"imported":true}'},
    ];
    await AgentPackage.write(
      path,
      {
        'type': type,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'workflow': type == 'memory' ? null : workflow,
        'memories': selectedMemories,
      },
      onProgress: _reportProgress,
      cancellation: _transferCancellation,
    );
  }

  Future<Map<String, dynamic>> inspect(String path) => runTransfer(
    () => AgentPackage.read(
      path,
      onProgress: _reportProgress,
      cancellation: _transferCancellation,
    ),
  );
  Future<List<MemoryImportItem>> plan(Map<String, dynamic> package) =>
      runTransfer(() => _plan(package));

  /// 将画布上的独立记忆导入暂存为一个新的空闲主智能体。
  /// 复用工作流导入事务，同时提交智能体及其记忆。
  Map<String, dynamic> memoryPackageForNewAgent(
    Map<String, dynamic> package, {
    required String title,
  }) {
    if (package['type'] != 'memory' || package['memories'] is! List) {
      throw const FormatException('Invalid memory package');
    }
    const sourceId = 'imported-memory-agent';
    return {
      ...package,
      'type': 'agent',
      'workflow': {
        'version': 1,
        'sessions': [
          {
            'id': sourceId,
            'title': title,
            'task': '',
            'kind': 'primary',
            'conversation': {
              'serviceId': '',
              'model': '',
              'messages': <Object?>[],
              'history': <Object?>[],
              'useMemory': true,
            },
          },
        ],
        'connections': <Object?>[],
      },
      'memories': [
        for (final memory in package['memories'] as List)
          {...Map<String, Object?>.from(memory as Map), 'owner': sourceId},
      ],
    };
  }

  Future<List<MemoryImportItem>> _plan(Map<String, dynamic> package) async {
    _reportProgress(const AgentPackageProgress(AgentPackageStage.analyzing));
    _checkCancelled();
    if (package['type'] == 'memory' && workspaces.find(owner) == null) {
      throw StateError('Agent is unavailable');
    }
    final raw = package['memories'];
    if (raw is! List) throw const FormatException('Invalid memories');
    final incoming = raw
        .map((m) => Map<String, Object?>.from(m as Map))
        .toList();
    final existing = (await workspaces.main.storage!.request(
      'allMemories',
    ) as List).map((m) => Map<String, Object?>.from(m as Map)).toList();
    _checkCancelled();
    return _planMemoryItems(incoming, existing, package['type'] == 'memory');
  }

  Future<List<MemoryImportItem>> _planMemoryItems(
    List<Map<String, Object?>> incoming,
    List<Map<String, Object?>> existing,
    bool memoryOnly,
  ) async {
    final hashes = <String, Map<String, Map<String, Object?>>>{};
    final lineages = <String, Map<Object?, Map<String, Object?>>>{};
    final incomingHashes = <String, Set<String>>{};
    final incomingLineages = <String, Map<Object?, Map<String, Object?>>>{};
    final result = <MemoryImportItem>[];
    final total = existing.length + incoming.length;
    var completed = 0;
    Future<void> checkpoint() async {
      _checkCancelled();
      if (completed % 32 == 0 || completed == total) {
        _reportProgress(
          AgentPackageProgress(
            AgentPackageStage.analyzing,
            completed: completed,
            total: total,
          ),
        );
        // 让取消按钮和进度动画有机会处理事件。
        await Future<void>.delayed(Duration.zero);
        _checkCancelled();
      }
    }

    for (final memory in existing) {
      await checkpoint();
      final target = memory['owner'] as String;
      final hash = memoryContentHash(memory['content'] as String);
      (hashes[target] ??= {}).putIfAbsent(hash, () => memory);
      (lineages[target] ??= {}).putIfAbsent(
        memory['lineage'] ?? memory['id'],
        () => memory,
      );
      completed++;
    }
    for (final memory in incoming) {
      await checkpoint();
      final content = memory['content'];
      if (content is! String || content.trim().isEmpty) {
        throw const FormatException('Invalid memory content');
      }
      final hash = memoryContentHash(content);
      if (memory['hash'] != null && memory['hash'] != hash) {
        throw const FormatException('Memory hash mismatch');
      }
      final target = memoryOnly ? owner : 'import:${memory['owner']}';
      final lineage = memory['lineage'] ?? memory['id'];
      final duplicate = hashes[target]?[hash];
      final previous = lineages[target]?[lineage];
      final seenHashes = incomingHashes[target] ??= {};
      final seenLineages = incomingLineages[target] ??= {};
      result.add(
        MemoryImportItem(
          incoming: memory,
          target: target,
          existing: duplicate ?? previous,
          incomingPrevious: seenLineages[lineage],
          duplicate: duplicate != null || seenHashes.contains(hash),
        ),
      );
      seenHashes.add(hash);
      seenLineages.putIfAbsent(lineage, () => memory);
      completed++;
    }
    await checkpoint();
    return result;
  }

  Future<void> import(
    Map<String, dynamic> package, {
    List<MemoryImportItem>? plan,
  }) => runTransfer(() => _import(package, plan: plan));

  Future<void> _import(
    Map<String, dynamic> package, {
    List<MemoryImportItem>? plan,
  }) async {
    _checkCancelled();
    if (workspaces.sessions.any((s) => s.busy)) {
      throw StateError('Agents are running');
    }
    final items = plan ?? await this.plan(package);
    _checkCancelled();
    final memoryOnly = package['type'] == 'memory';
    if (memoryOnly && workspaces.find(owner) == null) {
      throw StateError('Agent is unavailable');
    }
    final storage = workspaces.main.storage!;
    List<Map<String, Object?>> prepare(Map<String, String> mapping) {
      final operations = <Map<String, Object?>>[];
      for (final item in items) {
        if (item.resolution == MemoryResolution.skip) continue;
        final target = memoryOnly ? owner : mapping[item.incoming['owner']];
        if (target == null) {
          throw const FormatException('Memory owner is missing');
        }
        final replace =
            item.resolution == MemoryResolution.replace &&
            item.existing != null &&
            target == item.existing!['owner'];
        final id = replace ? item.existing!['id'] as String : newMemoryId();
        operations.add({
          'id': id,
          'owner': target,
          'content': item.content,
          if (replace) 'expectedHash': item.existing!['hash'],
          'lineage': replace
              ? item.existing!['lineage']
              : item.incoming['lineage'] ?? item.incoming['id'],
          'baseHash': item.incoming['hash'],
          'source': '{"imported":true}',
        });
      }
      return operations;
    }

    if (memoryOnly) {
      await workspaces.flush();
      _checkCancelled();
      // 越过此边界后不能取消，commitImport 会原子提交。
      _reportProgress(
        const AgentPackageProgress(
          AgentPackageStage.committing,
          canCancel: false,
        ),
      );
      final workflow = workspaces.exportData()
        ..['selectedId'] = workspaces.selectedId;
      await storage.commitImport(workflow, prepare(const {}));
    } else {
      _checkCancelled();
      var checkpoints = 0;
      _reportProgress(const AgentPackageProgress(AgentPackageStage.analyzing));
      await workspaces.importData(
        Map<String, dynamic>.from(package['workflow'] as Map),
        memoriesFor: prepare,
        checkpoint: () async {
          _checkCancelled();
          if (checkpoints++ % 32 == 0) {
            await Future<void>.delayed(Duration.zero);
            _checkCancelled();
          }
        },
        onStaging: (completed, total) => _reportProgress(
          AgentPackageProgress(
            AgentPackageStage.analyzing,
            completed: completed,
            total: total,
          ),
        ),
        onBeforeCommit: () {
          _checkCancelled();
          _reportProgress(
            const AgentPackageProgress(
              AgentPackageStage.committing,
              canCancel: false,
            ),
          );
        },
      );
    }
    await refresh();
  }
}
