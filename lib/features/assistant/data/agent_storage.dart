import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lilygobox_codecs/lilygobox_codecs.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/memory_conflict.dart';

/// 数据库工作在独立 isolate 中串行执行，界面线程不执行数据压缩。
class AgentStorage {
  AgentStorage({
    this.path,
    this.maintenanceIdleDelay = const Duration(seconds: 10),
    this.maintenanceMaxDelay = const Duration(minutes: 5),
    this.maintenanceInterval = const Duration(minutes: 1),
  });
  final String? path;
  final Duration maintenanceIdleDelay;
  final Duration maintenanceMaxDelay;
  final Duration maintenanceInterval;
  final _responses = ReceivePort();
  final _errors = ReceivePort();
  final _pending = <int, Completer<Object?>>{};
  SendPort? _worker;
  Isolate? _isolate;
  Future<void>? _opening;
  int _sequence = 0;
  bool _closed = false;
  int _memoryRevision = 0;
  int get memoryRevision => _memoryRevision;
  Future<Map<String, Object?>>? _statsRead;

  Future<Map<String, Object?>> readStats({bool force = false}) {
    if (force) _statsRead = null;
    if (_statsRead case final existing?) return existing;
    late final Future<Map<String, Object?>> read;
    read = request('stats')
        .then((value) => Map<String, Object?>.from(value as Map))
        .onError((Object error, StackTrace stack) {
          if (identical(_statsRead, read)) _statsRead = null;
          Error.throwWithStackTrace(error, stack);
        });
    return _statsRead = read;
  }

  String? databasePath;
  Future<void> get ready => _opening ??= _open();

  Future<void> _open() async {
    final root =
        path ??
        (Platform.isWindows
            ? '${Platform.environment['LOCALAPPDATA']}/LILYGO/LilygoBox/data/main.db'
            : '${(await getApplicationSupportDirectory()).path}/data/main.db');
    databasePath = root;
    if (root != ':memory:') await File(root).parent.create(recursive: true);
    final started = Completer<void>();
    void fail(Object error) {
      if (!started.isCompleted) started.completeError(error);
      for (final completer in _pending.values) {
        completer.completeError(error);
      }
      _pending.clear();
      _worker = null;
    }

    _responses.listen((dynamic data) {
      if (data == 'statsInvalidated') {
        _statsRead = null;
        return;
      }
      if (data is SendPort) {
        _worker = data;
        started.complete();
        return;
      }
      final m = data as List;
      final c = _pending.remove(m[0]);
      if (m[1] == true) {
        c?.complete(m[2]);
      } else {
        c?.completeError(StateError(m[2].toString()));
      }
    });
    _errors.listen(
      (dynamic error) => fail(StateError('Storage worker failed: $error')),
    );
    try {
      _isolate = await Isolate.spawn(
        _databaseWorker,
        [
          root,
          _responses.sendPort,
          maintenanceIdleDelay.inMicroseconds,
          maintenanceMaxDelay.inMicroseconds,
          maintenanceInterval.inMicroseconds,
        ],
        onError: _errors.sendPort,
        errorsAreFatal: true,
      );
      await started.future;
    } catch (_) {
      _responses.close();
      _errors.close();
      rethrow;
    }
  }

  Future<Object?> request(
    String operation, [
    Map<String, Object?> args = const {},
  ]) async {
    if (_closed && operation != 'close') throw StateError('Storage is closed');
    await ready;
    if (_closed && operation != 'close') throw StateError('Storage is closed');
    if (_worker == null) throw StateError('Storage worker is unavailable');
    final id = ++_sequence;
    final result = Completer<Object?>();
    _pending[id] = result;
    _worker!.send([id, operation, args]);
    final value = await result.future;
    if (const {
      'commitImport',
      'commitRecycle',
      'copyMemories',
      'putMemory',
      'saveAutoMemories',
      'deleteMemory',
    }.contains(operation)) {
      _memoryRevision++;
      _statsRead = null;
    } else if (operation == 'saveWorkflow' ||
        operation == 'saveCanvas' ||
        operation == 'clean') {
      _statsRead = null;
    }
    return value;
  }

  Future<String?> readWorkflow() async =>
      await request('readWorkflow') as String?;
  Future<void> saveWorkflow(Object value) async {
    await request('saveWorkflow', {'value': value});
  }

  Future<void> commitImport(
    Object value,
    List<Map<String, Object?>> memories,
  ) async {
    await request('commitImport', {'value': value, 'memories': memories});
  }

  Future<List<Map<String, Object?>>> memories(
    String owner, {
    String query = '',
    int? limit,
    int offset = 0,
  }) async => (await request('memories', {
    'owner': owner,
    'query': query,
    'limit': limit,
    'offset': offset,
  }) as List).map((v) => Map<String, Object?>.from(v as Map)).toList();

  /// 新增模型提取的事实，不修改已有记忆。
  Future<Map<String, int>> saveAutoMemories({
    required String owner,
    required String turnId,
    required List<String> candidates,
  }) async {
    final result = await request('saveAutoMemories', {
      'owner': owner,
      'turnId': turnId,
      'candidates': candidates,
    }) as Map;
    return {
      'added': result['added'] as int,
      'skipped': result['skipped'] as int,
    };
  }

  Future<void> putMemory({
    required String id,
    required String owner,
    required String content,
    String source = '',
    String? lineage,
    String? baseHash,
  }) async {
    await request('putMemory', {
      'id': id,
      'owner': owner,
      'content': content,
      'source': source,
      'lineage': lineage,
      'baseHash': baseHash,
    });
  }

  Future<void> deleteMemory(String id) async {
    await request('deleteMemory', {'id': id});
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_opening != null) {
      try {
        await ready;
        if (_worker != null) await request('close');
      } finally {
        _isolate?.kill();
      }
    }
    _responses.close();
    _errors.close();
    _worker = null;
  }
}

class _PackedRecycleRecord {
  const _PackedRecycleRecord(this.value);

  final Object? value;
}

void _databaseWorker(List<dynamic> initialization) {
  final db = sqlite3.open(initialization[0] as String);
  final replies = initialization[1] as SendPort;
  final requests = ReceivePort();
  db.execute('PRAGMA journal_mode=WAL');
  db.execute('PRAGMA synchronous=FULL');
  db.execute('PRAGMA foreign_keys=ON');
  db.execute(
    'CREATE TABLE IF NOT EXISTS objects(hash TEXT PRIMARY KEY,body BLOB NOT NULL)',
  );
  db.execute(
    'CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
  );
  db.execute(
    'CREATE TABLE IF NOT EXISTS memories(id TEXT PRIMARY KEY,owner TEXT NOT NULL,content TEXT NOT NULL,source TEXT NOT NULL,updated TEXT NOT NULL,lineage TEXT NOT NULL,hash TEXT NOT NULL,revision INTEGER NOT NULL,base_hash TEXT,UNIQUE(owner,content))',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS memories_owner_hash ON memories(owner,hash)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS memories_owner_updated_id ON memories(owner,updated DESC,id)',
  );
  db.execute(
    'CREATE VIRTUAL TABLE IF NOT EXISTS memory_search USING fts5(id UNINDEXED,content,tokenize="trigram")',
  );
  replies.send(requests.sendPort);

  T transaction<T>(T Function() work) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = work();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  var packedRecycleRecords = <String, Object?>{};

  Map<String, Object?> saveWorkflow(Object source) {
    final known = <String>{};
    Object? pack(Object? value) {
      if (value is _PackedRecycleRecord) return value.value;
      if (value is String && value.length > 256) {
        final bytes = utf8.encode(value);
        final hash = sha256.convert(bytes).toString();
        if (known.add(hash) &&
            db.select('SELECT 1 FROM objects WHERE hash=?', [hash]).isEmpty) {
          db.execute('INSERT INTO objects VALUES(?,?)', [
            hash,
            LilygoBoxCodecs.zstd(Uint8List.fromList(bytes)),
          ]);
        }
        return {'@object': hash};
      }
      if (value is Map) return value.map((k, v) => MapEntry(k, pack(v)));
      if (value is List) return value.map(pack).toList();
      return value;
    }

    var data = source is String ? jsonDecode(source) : source;
    final nextRecycleRecords = <String, Object?>{};
    if (data is Map && data['recycleBin'] is List) {
      final recycled = <Object?>[];
      for (final entry in data['recycleBin'] as List) {
        if (entry is Map && entry['record'] is String) {
          final record = entry['record'] as String;
          final packedRecord = nextRecycleRecords.putIfAbsent(
            record,
            () => packedRecycleRecords.containsKey(record)
                ? packedRecycleRecords[record]
                : pack(jsonDecode(record)),
          );
          recycled.add({
            ...entry,
            'record': _PackedRecycleRecord(packedRecord),
          });
        } else {
          recycled.add(entry);
        }
      }
      data = {...data, 'recycleBin': recycled};
    }
    if (data is Map && data['sessions'] is List) {
      final ids = <String>{};
      for (final session in data['sessions'] as List) {
        final id = session['id'] as String;
        ids.add('conversation:$id');
        final conversation = session['conversation'] as Map;
        if (conversation['@conversation'] != id) {
          db.execute(
            'INSERT INTO state VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
            ['conversation:$id', jsonEncode(pack(conversation))],
          );
          session['conversation'] = {'@conversation': id};
        } else if (db.select('SELECT 1 FROM state WHERE key=?', [
          'conversation:$id',
        ]).isEmpty) {
          throw StateError('Missing conversation snapshot');
        }
      }
      for (final row in db.select(
        "SELECT key FROM state WHERE key LIKE 'conversation:%'",
      )) {
        if (!ids.contains(row['key'])) {
          db.execute('DELETE FROM state WHERE key=?', [row['key']]);
        }
      }
    }
    final packed = pack(data);
    db.execute(
      "INSERT INTO state VALUES('workflow',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
      [jsonEncode(packed)],
    );
    return nextRecycleRecords;
  }

  Object? expand(Object? value) {
    if (value is Map && value.length == 1 && value['@conversation'] is String) {
      final row = db.select('SELECT value FROM state WHERE key=?', [
        'conversation:${value['@conversation']}',
      ]).first;
      return expand(jsonDecode(row['value'] as String));
    }
    if (value is Map && value.length == 1 && value['@object'] is String) {
      final row = db.select('SELECT body FROM objects WHERE hash=?', [
        value['@object'],
      ]).first;
      final bytes = LilygoBoxCodecs.unzstd(row['body'] as Uint8List);
      if (sha256.convert(bytes).toString() != value['@object']) {
        throw const FormatException('Stored object checksum mismatch');
      }
      return utf8.decode(bytes);
    }
    if (value is Map) {
      return Map<String, Object?>.from(
        value.map((k, v) => MapEntry(k, expand(v))),
      );
    }
    if (value is List) return value.map(expand).toList();
    return value;
  }

  void putMemory(Map a) {
    final id = a['id'] as String;
    final owner = a['owner'] as String;
    final content = (a['content'] as String).replaceAll('\r\n', '\n').trim();
    if (id.isEmpty || owner.isEmpty || owner == 'global' || content.isEmpty) {
      throw const FormatException('Invalid memory');
    }
    final hash = sha256.convert(utf8.encode(content)).toString();
    final previous = db.select('SELECT * FROM memories WHERE id=?', [
      id,
    ]).firstOrNull;
    if (previous != null && previous['owner'] != owner) {
      throw StateError('Memory scope cannot be changed');
    }
    if (a['expectedHash'] != null && previous?['hash'] != a['expectedHash']) {
      throw StateError('Memory changed after import preview');
    }
    if (previous?['hash'] == hash) return;
    final duplicate = db.select(
      'SELECT id FROM memories WHERE owner=? AND hash=?',
      [owner, hash],
    ).firstOrNull;
    if (duplicate != null && duplicate['id'] != id) return;
    final revision = (previous?['revision'] as int? ?? 0) + 1;
    final updated = DateTime.now().toUtc().toIso8601String();
    final lineage = previous?['lineage'] ?? a['lineage'] ?? id;
    final source = a['source'] as String? ?? '';
    db.execute(
      'INSERT INTO memories VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET content=excluded.content,source=excluded.source,updated=excluded.updated,hash=excluded.hash,revision=excluded.revision,base_hash=excluded.base_hash',
      [
        id,
        owner,
        content,
        source,
        updated,
        lineage,
        hash,
        revision,
        a['baseHash'] ?? previous?['hash'],
      ],
    );
    if (previous != null) {
      db.execute('DELETE FROM memory_search WHERE id=?', [id]);
    }
    db.execute('INSERT INTO memory_search(id,content) VALUES(?,?)', [
      id,
      content,
    ]);
  }

  void collectObjectHashes(Object? value, Set<String> hashes) {
    if (value is Map) {
      if (value['@object'] case final String hash) hashes.add(hash);
      for (final child in value.values) {
        collectObjectHashes(child, hashes);
      }
    } else if (value is List) {
      for (final child in value) {
        collectObjectHashes(child, hashes);
      }
    }
  }

  int collectObjects() {
    var removed = 0;
    final live = <String>{};
    for (final row in db.select('SELECT value FROM state')) {
      collectObjectHashes(jsonDecode(row['value'] as String), live);
    }
    for (final row in db.select('SELECT hash FROM objects')) {
      if (!live.contains(row['hash'])) {
        db.execute('DELETE FROM objects WHERE hash=?', [row['hash']]);
        removed++;
      }
    }
    return removed;
  }

  int physicalBytes() {
    final path = initialization[0] as String;
    if (path == ':memory:') return 0;
    var bytes = 0;
    for (final name in [path, '$path-wal']) {
      final file = File(name);
      if (file.existsSync()) bytes += file.lengthSync();
    }
    return bytes;
  }

  // 在工作线程合并维护请求，普通编辑不扫描全部已存状态，也不同步执行 VACUUM。
  // 设置最长延迟，避免持续的流式写入无限推迟无引用对象回收。
  final idleDelay = Duration(microseconds: initialization[2] as int);
  final maxDelay = Duration(microseconds: initialization[3] as int);
  final minimumInterval = Duration(microseconds: initialization[4] as int);
  Timer? maintenanceTimer;
  var objectsDirty = true; // Also reclaim leftovers from a previous shutdown.
  var databaseDirty = true;
  var closing = false;
  var lastActivity = DateTime.now();
  DateTime? pendingSince = lastActivity;
  DateTime? lastMaintenance;
  DateTime? lastVacuum;
  late void Function() maintain;

  DateTime maintenanceDue() {
    final idle = lastActivity.add(idleDelay);
    final deadline = pendingSince!.add(maxDelay);
    var due = idle.isBefore(deadline) ? idle : deadline;
    if (lastMaintenance case final previous?) {
      final earliest = previous.add(minimumInterval);
      if (due.isBefore(earliest)) due = earliest;
    }
    return due;
  }

  void scheduleMaintenance() {
    maintenanceTimer?.cancel();
    if (closing || (!objectsDirty && !databaseDirty)) return;
    pendingSince ??= DateTime.now();
    final delay = maintenanceDue().difference(DateTime.now());
    maintenanceTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      maintain,
    );
  }

  maintain = () {
    maintenanceTimer = null;
    if (closing) return;
    final now = DateTime.now();
    if (now.isBefore(maintenanceDue())) {
      scheduleMaintenance();
      return;
    }
    final idle = now.difference(lastActivity) >= idleDelay;
    try {
      if (objectsDirty) {
        if (transaction(collectObjects) > 0) replies.send('statsInvalidated');
        objectsDirty = false;
      }
      // PASSIVE 检查点不等待其他连接；仅在空闲且可回收页不少于 8 MiB、
      // 占数据库页数至少 20% 时，才完整整理数据库。
      if (idle) {
        final free =
            db.select('PRAGMA freelist_count').first.values.first as int;
        final pages = db.select('PRAGMA page_count').first.values.first as int;
        final pageSize =
            db.select('PRAGMA page_size').first.values.first as int;
        final vacuumAllowed =
            lastVacuum == null ||
            now.difference(lastVacuum!) >= const Duration(minutes: 30);
        if (free * pageSize >= 8 * 1024 * 1024 &&
            free * 5 >= pages &&
            vacuumAllowed) {
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
          db.execute('VACUUM');
          replies.send('statsInvalidated');
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
          lastVacuum = DateTime.now();
        } else {
          db.execute('PRAGMA wal_checkpoint(PASSIVE)');
        }
        databaseDirty = false;
      } else {
        db.execute('PRAGMA wal_checkpoint(PASSIVE)');
      }
    } catch (error, stack) {
      // 稍后重试；快照损坏或磁盘忙碌不能终止工作线程，
      // 也不能将已经提交的用户写入报告为请求失败。
      developer.log(
        'Automatic storage maintenance failed',
        name: 'AgentStorage',
        error: error,
        stackTrace: stack,
      );
    } finally {
      lastMaintenance = DateTime.now();
      pendingSince = objectsDirty || databaseDirty ? lastMaintenance : null;
      scheduleMaintenance();
    }
  };

  scheduleMaintenance();
  requests.listen((dynamic raw) {
    final m = raw as List;
    final id = m[0];
    final op = m[1];
    final a = m[2] as Map;
    lastActivity = DateTime.now();
    try {
      Object? result;
      switch (op) {
        case 'readWorkflow':
        case 'readWorkflowData':
          final value =
              db
                      .select("SELECT value FROM state WHERE key='workflow'")
                      .firstOrNull?['value']
                  as String?;
          if (value != null) {
            final data = expand(jsonDecode(value));
            result = op == 'readWorkflowData' ? data : jsonEncode(data);
          }
        case 'saveCanvas':
          final updated = db.select(
            r"UPDATE state SET value=json_set(value, '$.canvas', json(?), '$.canvasOrigin', json(?), '$.selectedId', ?) WHERE key='workflow' RETURNING 1",
            [
              jsonEncode(a['canvas']),
              jsonEncode(a['canvasOrigin']),
              a['selectedId'],
            ],
          );
          if (updated.isEmpty) throw StateError('Missing workflow snapshot');
        case 'saveWorkflow':
        case 'commitImport':
        case 'commitRecycle':
          packedRecycleRecords = transaction(() {
            final nextRecycleRecords = saveWorkflow(a['value'] as Object);
            if (op == 'commitRecycle') {
              final owners = jsonEncode(a['owners'] as List);
              db.execute(
                'DELETE FROM memory_search WHERE id IN (SELECT id FROM memories WHERE owner IN (SELECT value FROM json_each(?)))',
                [owners],
              );
              db.execute(
                'DELETE FROM memories WHERE owner IN (SELECT value FROM json_each(?))',
                [owners],
              );
            }
            if (op == 'commitImport') {
              for (final memory in a['memories'] as List) {
                putMemory(memory as Map);
              }
            }
            return nextRecycleRecords;
          });
        case 'copyMemories':
          transaction(() {
            for (final entry in (a['mapping'] as Map).entries) {
              for (final memory in db.select(
                'SELECT * FROM memories WHERE owner=?',
                [entry.key],
              )) {
                final copyId = newMemoryId();
                db.execute(
                  'INSERT INTO memories SELECT ?,?,content,source,updated,lineage,hash,revision,base_hash FROM memories WHERE id=?',
                  [copyId, entry.value, memory['id']],
                );
                db.execute(
                  'INSERT INTO memory_search(id,content) VALUES(?,?)',
                  [copyId, memory['content']],
                );
              }
            }
          });
        case 'validateMemorySelection':
          final ids = (a['ids'] as List).cast<String>().toSet();
          final owned = db
              .select('SELECT id FROM memories WHERE owner=?', [a['owner']])
              .map((row) => row['id'] as String)
              .toSet();
          result = owned.containsAll(ids);
        case 'memories':
          final query = (a['query'] as String).trim();
          final limit = a['limit'] as int?;
          if (limit != null && limit < 1) {
            throw const FormatException('Invalid page size');
          }
          final offset = a['offset'] as int? ?? 0;
          if (query.isNotEmpty) {
            final exact = db.select(
              'SELECT * FROM memories WHERE owner=? AND id=?',
              [a['owner'], query],
            ).firstOrNull;
            if (exact != null || RegExp(r'^[0-9a-f]{32}$').hasMatch(query)) {
              result = <Map<String, Object?>>[
                if (exact != null && offset <= 0)
                  Map<String, Object?>.from(exact),
              ];
              break;
            }
          }
          final words = RegExp(r'[A-Za-z0-9_]+|[一-鿿]+')
              .allMatches(query)
              .map((m) => m.group(0)!)
              .toList();
          final terms = <String>{};
          for (final word in words) {
            if (RegExp(r'^[一-鿿]+$').hasMatch(word) && word.length > 3) {
              for (var i = 0; i <= word.length - 3; i++) {
                terms.add(word.substring(i, i + 3));
              }
            } else {
              terms.add(word);
            }
          }
          final longTerms = terms.where((t) => t.runes.length >= 3).toList();
          final shortTerms = terms.where((t) => t.runes.length < 3).toList();
          final conditions = <String>[];
          final args = <Object?>[a['owner']];
          if (longTerms.isNotEmpty) {
            conditions.add(
              'id IN (SELECT id FROM memory_search WHERE memory_search MATCH ?)',
            );
            args.add(
              longTerms.map((t) => '"${t.replaceAll('"', '""')}"').join(' OR '),
            );
          }
          for (final term in shortTerms) {
            conditions.add('instr(lower(content),lower(?))>0');
            args.add(term);
          }
          final filter = conditions.isEmpty
              ? ''
              : ' AND (${conditions.join(' OR ')})';
          result = db
              .select(
                'SELECT * FROM memories WHERE owner=?$filter ORDER BY updated DESC,id LIMIT ? OFFSET ?',
                [...args, limit ?? -1, offset],
              )
              .map((r) => Map<String, Object?>.from(r))
              .toList();
        case 'saveAutoMemories':
          result = transaction(() {
            final owner = a['owner'];
            final turnId = a['turnId'];
            final candidates = a['candidates'];
            // 这些限制只针对单次不可信的提取响应，
            // 不限制智能体累计保留的记忆数量。
            if (owner is! String ||
                owner.isEmpty ||
                owner == 'global' ||
                turnId is! String ||
                turnId.isEmpty ||
                candidates is! List ||
                candidates.length > 32) {
              throw const FormatException('Invalid automatic memory batch');
            }
            var added = 0;
            var skipped = 0;
            for (final candidate in candidates) {
              if (candidate is! String || candidate.length > 16384) {
                throw const FormatException(
                  'Invalid automatic memory candidate',
                );
              }
              final content = candidate.replaceAll('\r\n', '\n').trim();
              if (content.isEmpty) {
                skipped++;
                continue;
              }
              final hash = memoryContentHash(content);
              if (db.select('SELECT 1 FROM memories WHERE owner=? AND hash=?', [
                owner,
                hash,
              ]).isNotEmpty) {
                skipped++;
                continue;
              }
              var id = newMemoryId();
              while (db.select('SELECT 1 FROM memories WHERE id=?', [
                id,
              ]).isNotEmpty) {
                id = newMemoryId();
              }
              putMemory({
                'id': id,
                'owner': owner,
                'content': content,
                'source': jsonEncode({'automatic': true, 'turnId': turnId}),
              });
              added++;
            }
            return {'added': added, 'skipped': skipped};
          });
        case 'putMemory':
          transaction(() => putMemory(a));
        case 'deleteMemory':
          transaction(() {
            db.execute('DELETE FROM memories WHERE id=?', [a['id']]);
            db.execute('DELETE FROM memory_search WHERE id=?', [a['id']]);
          });
        case 'exportSnapshot':
          result = transaction(() {
            final saved =
                db
                        .select("SELECT value FROM state WHERE key='workflow'")
                        .firstOrNull?['value']
                    as String?;
            final workflow = saved == null ? null : jsonDecode(saved);
            if (workflow is Map && a['includeRoleplayLibrary'] == false) {
              workflow.remove('roleplayLibrary');
            }
            return {
              'workflow': workflow == null ? null : expand(workflow),
              'memories': db
                  .select('SELECT * FROM memories ORDER BY updated DESC')
                  .map((r) => Map<String, Object?>.from(r))
                  .toList(),
            };
          });
        case 'allMemories':
          result = db
              .select('SELECT * FROM memories ORDER BY updated DESC')
              .map((r) => Map<String, Object?>.from(r))
              .toList();
        case 'stats':
          // 按已保存的状态 JSON 拆分占用，不解压共享正文对象。
          // 上下文字段包含键、分隔符和打包后的值；
          // 其余括号和会话字段计入聊天记录。
          var conversationBytes = 0;
          var contextBytes = 0;
          var workflowBytes = 0;
          var recycleBinBytes = 0;
          var roleplayLibraryBytes = 0;
          final roleplayHashes = <String>{};
          for (final row in db.select('SELECT key,value FROM state')) {
            final text = row['value'] as String;
            final bytes = utf8.encode(text).length;
            if ((row['key'] as String).startsWith('conversation:')) {
              final snapshot = jsonDecode(text) as Map;
              var context = 0;
              for (final key in [
                'history',
                'summary',
                'contextBudgetTokens',
                'contextCompactionPercent',
              ]) {
                if (snapshot.containsKey(key)) {
                  context +=
                      utf8.encode(jsonEncode({key: snapshot[key]})).length - 1;
                }
              }
              contextBytes += context;
              conversationBytes += bytes - context;
            } else {
              var recycled = 0;
              if (row['key'] == 'workflow') {
                final snapshot = jsonDecode(text) as Map;
                final entries = snapshot['recycleBin'];
                if (entries is List && entries.isNotEmpty) {
                  // 键和空列表结构仍计入工作流元数据。
                  recycled = utf8.encode(jsonEncode(entries)).length - 2;
                }
                final cards = snapshot['roleplayLibrary'];
                if (cards is List && cards.isNotEmpty) {
                  roleplayLibraryBytes =
                      utf8.encode(jsonEncode(cards)).length - 2;
                  collectObjectHashes(cards, roleplayHashes);
                }
              }
              recycleBinBytes += recycled;
              workflowBytes += bytes - recycled;
            }
          }
          final objectBytes =
              db
                      .select(
                        'SELECT COALESCE(SUM(length(body)),0) AS n FROM objects',
                      )
                      .first['n']
                  as int;
          final roleplayObjectBytes = roleplayHashes.isEmpty
              ? 0
              : db.select(
                      'SELECT COALESCE(SUM(length(body)),0) AS n FROM objects '
                      'WHERE hash IN (SELECT value FROM json_each(?))',
                      [jsonEncode(roleplayHashes.toList())],
                    ).first['n']
                    as int;
          result = {
            'memories': db
                .select('SELECT COUNT(*) AS n FROM memories')
                .first['n'],
            'objects': db
                .select('SELECT COUNT(*) AS n FROM objects')
                .first['n'],
            'bytes':
                (db.select('PRAGMA page_count').first.values.first as int) *
                (db.select('PRAGMA page_size').first.values.first as int),
            // 字节长度对应实际保存的载荷；剩余数据库页
            // 包含索引、记录开销和可复用空间。
            'breakdown': {
              'objects': objectBytes - roleplayObjectBytes,
              'roleplayObjects': roleplayObjectBytes,
              'state': db
                  .select(
                    'SELECT COALESCE(SUM(length(CAST(value AS BLOB))),0) AS n FROM state',
                  )
                  .first['n'],
              'memories': db
                  .select(
                    'SELECT COALESCE(SUM(length(CAST(content AS BLOB))),0) AS n FROM memories',
                  )
                  .first['n'],
            },
            'stateBreakdown': {
              'conversations': conversationBytes,
              'context': contextBytes,
              'workflow': workflowBytes - roleplayLibraryBytes,
              'recycleBin': recycleBinBytes,
              'roleplayLibrary': roleplayLibraryBytes,
            },
          };
        case 'clean':
          final before = physicalBytes();
          final removed = transaction(collectObjects);
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
          db.execute('VACUUM');
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
          objectsDirty = false;
          databaseDirty = false;
          pendingSince = null;
          maintenanceTimer?.cancel();
          lastMaintenance = DateTime.now();
          lastVacuum = lastMaintenance;
          final freed = before - physicalBytes();
          result = {
            'objectsRemoved': removed,
            'bytesFreed': freed > 0 ? freed : 0,
          };
        case 'close':
          closing = true;
          maintenanceTimer?.cancel();
          db.close();
          requests.close();
        default:
          throw StateError('Unknown storage operation');
      }
      if (const {
        'saveWorkflow',
        'saveCanvas',
        'commitImport',
        'commitRecycle',
        'copyMemories',
        'putMemory',
        'saveAutoMemories',
        'deleteMemory',
      }.contains(op)) {
        objectsDirty =
            objectsDirty ||
            op == 'saveWorkflow' ||
            op == 'commitImport' ||
            op == 'commitRecycle';
        databaseDirty = true;
        scheduleMaintenance();
      }
      replies.send([id, true, result]);
    } catch (e) {
      replies.send([id, false, e.toString()]);
    }
  });
}
