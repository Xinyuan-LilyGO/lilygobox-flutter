import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../core/files/zstd_tar.dart';
import '../../speech/domain/speech_model.dart';
import '../data/agent_package.dart';
import '../data/roleplay_card_exporter.dart';
import '../data/roleplay_card_importer.dart';
import '../domain/memory_conflict.dart';
import '../domain/roleplay_card.dart';
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
  int _readGeneration = 0;
  bool replacingMemories = false;
  bool appendingMemories = false;
  int? _speechBytes;
  int? get speechBytes => _speechBytes;

  Future<void> refreshStats({
    bool force = false,
    Future<int?> Function()? readSpeechBytes,
  }) async {
    final storage = workspaces.main.storage;
    if (storage == null) return;
    final (databaseStats, modelBytes) = await (
      storage.readStats(force: force),
      readSpeechBytes?.call() ?? Future<int?>.value(),
    ).wait;
    stats = databaseStats;
    if (readSpeechBytes != null) _speechBytes = modelBytes;
    notifyListeners();
  }

  void resolveOwner() {
    if (workspaces.find(owner) == null) {
      owner = workspaces.sessions.firstOrNull?.id ?? '';
    }
  }

  Future<void> refresh({String query = ''}) => _readMemories(query);

  Future<void> loadMore() => _readMemories(_query, append: true);

  Future<void> _readMemories(String query, {bool append = false}) async {
    if (_disposed ||
        (append && (!hasMore || replacingMemories || appendingMemories))) {
      return;
    }
    final generation = ++_readGeneration;
    _query = query;
    replacingMemories = !append;
    appendingMemories = append;
    if (!append) {
      memories = const [];
      hasMore = false;
    }
    error = null;
    notifyListeners();
    try {
      await workspaces.initialized;
      if (_disposed || generation != _readGeneration) return;
      if (!append) resolveOwner();
      final target = owner;
      final storage = workspaces.main.storage;
      if (target.isEmpty || storage == null) return;
      final rows = await storage.memories(
        target,
        query: query,
        limit: 51,
        offset: memories.length,
      );
      if (_disposed ||
          generation != _readGeneration ||
          owner != target ||
          workspaces.find(target) == null) {
        return;
      }
      memories = [...memories, ...rows.take(50)];
      hasMore = rows.length > 50;
    } catch (failure) {
      if (!_disposed && generation == _readGeneration) error = failure;
    } finally {
      if (!_disposed && generation == _readGeneration) {
        replacingMemories = false;
        appendingMemories = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveMemory(
    String content, {
    String? id,
    String? expectedOwner,
  }) async {
    if ((expectedOwner != null && expectedOwner != owner) ||
        workspaces.find(owner) == null) {
      throw StateError('Agent is unavailable');
    }
    await workspaces.main.storage!.putMemory(
      id: id ?? newMemoryId(),
      owner: owner,
      content: content.trim(),
    );
    unawaited(refresh(query: _query));
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
    unawaited(refresh(query: _query));
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
      return 'lilygobox-agent-workflow-package-$date${ZstdTar.suffix}';
    }
    if (owner.isEmpty) throw StateError('Agent is unavailable');
    if (type == 'agent' && children) {
      return 'lilygobox-agent-workflow-package-$date${ZstdTar.suffix}';
    }
    final content = switch (type) {
      'agent' => 'full',
      'chat' => 'chat',
      'memory' => 'memory',
      _ => throw ArgumentError.value(type, 'type', 'Unsupported export type'),
    };
    return 'lilygobox-agent-$owner-$content-package-$date${ZstdTar.suffix}';
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
    final storage = workspaces.main.storage!;
    if (type == 'memory') {
      final memories = await storage.memories(owner);
      _checkCancelled();
      await _writePackage(path, type, null, memories);
      return;
    }
    await workspaces.flush();
    _checkCancelled();
    final snapshot = Map<String, dynamic>.from(
      await storage.request('exportSnapshot', {'includeRoleplayLibrary': false})
          as Map,
    );
    _checkCancelled();
    final workflow = Map<String, Object?>.from(snapshot['workflow'] as Map);
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
          ..._copyPackageSession(r),
          'parentId': ids.contains(r['parentId']) ? r['parentId'] : null,
          'kind': ids.contains(r['parentId'])
              ? r['kind']
              : AiWorkspaceKind.primary.name,
        },
    ];
    _packRoleplayCards(workflow);
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
    final selected = type == 'chat'
        ? <Map>[]
        : all.where((m) => ids.contains(m['owner']));
    await _writePackage(path, type, workflow, selected);
  }

  Future<void> _writePackage(
    String path,
    String type,
    Map<String, Object?>? workflow,
    Iterable<Map> memories,
  ) => AgentPackage.write(
    path,
    {
      'type': type,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'workflow': workflow,
      'memories': [
        for (final memory in memories)
          {...memory, 'source': '{"imported":true}'},
      ],
    },
    onProgress: _reportProgress,
    cancellation: _transferCancellation,
  );

  Future<Map<String, dynamic>> inspect(String path) => runTransfer(
    () => AgentPackage.read(
      path,
      onProgress: _reportProgress,
      cancellation: _transferCancellation,
    ),
  );
  Future<List<MemoryImportItem>> plan(Map<String, dynamic> package) =>
      runTransfer(() => _plan(package));

  Map<String, Object?> _copyPackageSession(Map record) {
    final session = Map<String, Object?>.from(record);
    final conversation =
        Map<String, Object?>.from(record['conversation'] as Map)
          ..remove('workspaceRelationship')
          ..remove('pendingWorkspaceEvents');
    return session..['conversation'] = conversation;
  }

  void _packRoleplayCards(Map<String, Object?> workflow) {
    final originals = {
      for (final binding in workspaces.roleplayTemplates)
        if (binding.sourceCard.originalFile != null)
          binding.sourceCard.templateFingerprint: binding.sourceCard,
    };
    final cards = <String, String>{};
    final references = <String, String>{};
    for (final session in workflow['sessions'] as List) {
      final conversation = session['conversation'] as Map;
      if (conversation['roleplay'] case {'binding': final Map binding}) {
        final card = AiRoleplayCard.fromSnapshot(binding['card'] as Map);
        final fingerprint = card.templateFingerprint;
        final reference = references.putIfAbsent(fingerprint, () {
          final bytes = AiRoleplayCardExporter.encode(
            originals[fingerprint] ?? card,
          );
          final hash = sha256.convert(bytes).toString();
          cards.putIfAbsent(hash, () => base64Encode(bytes));
          return hash;
        });
        conversation['roleplay'] = {
          ...conversation['roleplay'] as Map,
          'binding': {
            ...(Map.of(binding)..remove('card')),
            'cardRef': reference,
          },
        };
      }
    }
    if (cards.isNotEmpty) workflow['roleplayCards'] = cards;
  }

  Future<void> _restorePackagedRoleplayCards(
    Map<String, dynamic> workflow,
  ) async {
    final cards = workflow.remove('roleplayCards') ?? const <String, String>{};
    if (cards is! Map) throw const FormatException('Invalid character cards');
    final restored = <String, AiRoleplayCard>{};
    workflow['sessions'] = [
      for (final record in workflow['sessions'] as List)
        await _restorePackagedRoleplaySession(record as Map, cards, restored),
    ];
    if (restored.length != cards.length) {
      throw const FormatException('Unreferenced packaged character card');
    }
  }

  Future<Map<String, Object?>> _restorePackagedRoleplaySession(
    Map record,
    Map cards,
    Map<String, AiRoleplayCard> restored,
  ) async {
    _checkCancelled();
    final session = _copyPackageSession(record);
    final conversation = session['conversation'] as Map;
    if (!conversation.containsKey('roleplay')) return session;
    if (conversation['roleplay'] case final Map roleplay
        when roleplay['binding'] is Map) {
      final binding = roleplay['binding'] as Map;
      final reference = binding['cardRef'];
      if (reference is String && !binding.containsKey('card')) {
        final previous = restored[reference];
        final card =
            previous ?? await _decodePackagedCard(reference, cards[reference]);
        restored[reference] = card;
        conversation['roleplay'] = {
          ...roleplay,
          'binding': {
            ...(Map.of(binding)..remove('cardRef')),
            'card': card.toSnapshot(includeOriginal: previous == null),
          },
        };
        return session;
      }
    }
    throw const FormatException('Missing packaged character card reference');
  }

  Future<AiRoleplayCard> _decodePackagedCard(
    String reference,
    Object? encoded,
  ) async {
    if (encoded is! String ||
        encoded.length > AiRoleplayCardImporter.maxFileBytes ~/ 3 * 4) {
      throw const FormatException('Invalid packaged character card');
    }
    final bytes = base64Decode(encoded);
    if (sha256.convert(bytes).toString() != reference) {
      throw const FormatException('Character card checksum mismatch');
    }
    return AiRoleplayCardImporter.parse(bytes, retainOriginal: true);
  }

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
    final memoryOnly = package['type'] == 'memory';
    final targetOwner = owner;
    if (memoryOnly && workspaces.find(targetOwner) == null) {
      throw StateError('Agent is unavailable');
    }
    final raw = package['memories'];
    if (raw is! List) throw const FormatException('Invalid memories');
    final incoming = raw
        .map((m) => Map<String, Object?>.from(m as Map))
        .toList();
    if (incoming.isEmpty) return [];
    final existing = memoryOnly
        ? await workspaces.main.storage!.memories(targetOwner)
        : const <Map<String, Object?>>[];
    _checkCancelled();
    return _planMemoryItems(
      incoming,
      existing,
      memoryOnly ? targetOwner : null,
    );
  }

  Future<List<MemoryImportItem>> _planMemoryItems(
    List<Map<String, Object?>> incoming,
    List<Map<String, Object?>> existing,
    String? targetOwner,
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
      final hash = memory['hash'] as String;
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
      final target = targetOwner ?? 'import:${memory['owner']}';
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
    SpeechLibrary? speechLibrary,
  }) => runTransfer(
    () => _import(package, plan: plan, speechLibrary: speechLibrary),
  );

  Future<void> _import(
    Map<String, dynamic> package, {
    List<MemoryImportItem>? plan,
    SpeechLibrary? speechLibrary,
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
      final operations = prepare(const {});
      if (operations.isEmpty) return;
      await workspaces.flush();
      _checkCancelled();
      // 越过此边界后不能取消，commitImport 会原子提交。
      _reportProgress(
        const AgentPackageProgress(
          AgentPackageStage.committing,
          canCancel: false,
        ),
      );
      await storage.commitMemoryImport(operations);
    } else {
      _checkCancelled();
      var checkpoints = 0;
      _reportProgress(const AgentPackageProgress(AgentPackageStage.analyzing));
      final workflow = Map<String, dynamic>.from(package['workflow'] as Map);
      final library = workflow.remove('roleplayLibrary');
      final recycleBin = workflow.remove('recycleBin');
      if (!(library == null || library is List && library.isEmpty) ||
          !(recycleBin == null || recycleBin is List && recycleBin.isEmpty)) {
        throw const FormatException('Invalid packaged workflow');
      }
      await _restorePackagedRoleplayCards(workflow);
      await workspaces.importData(
        workflow,
        memoriesFor: prepare,
        speechLibrary: speechLibrary,
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
    resolveOwner();
  }
}
