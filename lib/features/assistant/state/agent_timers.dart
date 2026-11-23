part of 'agent_workspace_provider.dart';

class _AiTimer {
  _AiTimer({
    required this.id,
    required this.ownerId,
    required this.objective,
    required this.startedAt,
    required this.deadline,
    this.status = 'running',
    this.recovered = false,
  });

  final String id;
  final String ownerId;
  final String objective;
  final DateTime startedAt;
  final DateTime deadline;
  String status;
  final bool recovered;
  final waiters = <Completer<void>>{};

  void finishWaits() {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Map<String, Object?> toJson() => {
    'timer_id': id,
    'owner_id': ownerId,
    'objective': objective,
    'started_at': startedAt.toUtc().toIso8601String(),
    'deadline': deadline.toUtc().toIso8601String(),
    'status': status,
  };
}

extension _AiTimers on AiWorkspaceProvider {
  static const _storageKey = 'ai.personalTimers.v1';

  void _saveTimers() {
    main.workspacePreferences.setValue(
      _storageKey,
      jsonEncode([for (final timer in _timers.values) timer.toJson()]),
    );
  }

  void _restoreTimers() {
    try {
      final records = jsonDecode(
        main.workspacePreferences.stringValue(_storageKey, '[]'),
      );
      if (records is! List) return;
      for (final raw in records.whereType<Map>()) {
        final started = DateTime.tryParse('${raw['started_at']}');
        final deadline = DateTime.tryParse('${raw['deadline']}');
        if (raw['timer_id'] is! String ||
            raw['owner_id'] is! String ||
            raw['objective'] is! String ||
            started == null ||
            deadline == null ||
            !deadline.isAfter(started) ||
            deadline.difference(started).inSeconds > 86400 ||
            !{'running', 'expired', 'cancelled'}.contains(raw['status'])) {
          continue;
        }
        final timer = _AiTimer(
          id: raw['timer_id'] as String,
          ownerId: raw['owner_id'] as String,
          objective: raw['objective'] as String,
          startedAt: started,
          deadline: deadline,
          status: raw['status'] as String,
          recovered: true,
        );
        if (find(timer.ownerId) != null) {
          _timers[timer.ownerId] = timer;
        }
      }
      _checkTimers();
      _armTimerTick();
    } on FormatException {
      return;
    }
  }

  void _armTimerTick() {
    if (_timerTick != null ||
        _disposed ||
        !_timers.values.any((timer) => timer.status == 'running')) {
      return;
    }
    _timerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkTimers();
    });
  }

  void _checkTimers() {
    if (_disposed) return;
    final now = _clock();
    var changed = false;
    for (final timer in _timers.values) {
      if (timer.status != 'running') continue;
      final owner = find(timer.ownerId);
      if (owner == null || owner.closed) {
        timer.status = 'cancelled';
      } else if (!now.isBefore(timer.deadline)) {
        timer.status = 'expired';
      } else {
        continue;
      }
      changed = true;
      timer.finishWaits();
    }
    if (changed) {
      _saveTimers();
      _notify();
    }
    if (!_timers.values.any((timer) => timer.status == 'running')) {
      _timerTick?.cancel();
      _timerTick = null;
    }
  }

  Map<String, Object?> _timerResult(_AiTimer timer) {
    final now = _clock();
    return {
      ...timer.toJson(),
      'remaining_seconds': timer.status == 'running'
          ? (timer.deadline.difference(now).inMilliseconds / 1000).ceil().clamp(
              0,
              86400,
            )
          : 0,
      'elapsed_seconds': now
          .difference(timer.startedAt)
          .inSeconds
          .clamp(0, 2147483647),
      'recovered_after_restart': timer.recovered,
    };
  }

  Map<String, Object?>? _timerContext(String agentId) {
    final timer = _timers[agentId];
    if (timer == null || timer.status != 'running') return null;
    return {
      'event': 'active_timers',
      'instruction':
          'For deadline actions, call wait_timer before ending this turn. '
          'Only expired means the deadline was reached.',
      'timers': [_timerResult(timer)],
    };
  }

  _AiTimer _checkedTimer(AiAgentWorkspace? source, Object? id) {
    if (source == null || source.closed) {
      throw StateError('A visible source agent is required');
    }
    final timer = _timers[source.id];
    if (timer == null || (id != null && timer.id != id)) {
      throw StateError('No matching personal timer');
    }
    return timer;
  }

  Map<String, Object?> _startTimer(
    AiAgentWorkspace? source,
    Map<String, Object?> args,
  ) {
    _checkTimers();
    if (source == null || source.closed) {
      throw StateError('A visible source agent is required');
    }
    final seconds = args['duration_seconds'];
    final objective = (args['objective'] as String? ?? '').trim();
    if (seconds is! int ||
        seconds < 1 ||
        seconds > 86400 ||
        objective.isEmpty ||
        objective.length > 4000) {
      throw const FormatException(
        'A duration of 1 to 86400 seconds and bounded objective are required',
      );
    }
    final previous = _timers[source.id];
    if (previous != null && previous.status == 'running') {
      return {..._timerResult(previous), 'already_running': true};
    }
    final now = _clock();
    _timers.removeWhere(
      (ownerId, timer) => timer.status != 'running' && find(ownerId) == null,
    );
    String id;
    do {
      id = '${now.microsecondsSinceEpoch}-${_sequence++}';
    } while (previous?.id == id ||
        _timers.values.any((timer) => timer.id == id));
    final timer = _AiTimer(
      id: id,
      ownerId: source.id,
      objective: objective,
      startedAt: now,
      deadline: now.add(Duration(seconds: seconds)),
    );
    _timers[source.id] = timer;
    _saveTimers();
    _armTimerTick();
    _notify();
    return {..._timerResult(timer), 'started': true};
  }

  Map<String, Object?> _getTimer(
    AiAgentWorkspace? source,
    Map<String, Object?> args,
  ) {
    _checkTimers();
    return _timerResult(_checkedTimer(source, args['timer_id']));
  }

  Future<Map<String, Object?>> _waitTimer(
    AiAgentWorkspace? source,
    Map<String, Object?> args,
  ) async {
    _checkTimers();
    final timer = _checkedTimer(source, args['timer_id']);
    if (timer.status != 'running') return _timerResult(timer);
    final waiter = Completer<void>();
    timer.waiters.add(waiter);
    try {
      final completed = await source!.assistant.waitForWorkspaceSignal(
        waiter.future,
      );
      if (!completed || _disposed) {
        return {'timer_id': timer.id, 'status': 'interrupted'};
      }
      return _timerResult(timer);
    } finally {
      timer.waiters.remove(waiter);
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Map<String, Object?> _cancelTimer(
    AiAgentWorkspace? source,
    Map<String, Object?> args,
  ) {
    _checkTimers();
    final timer = _checkedTimer(source, args['timer_id']);
    if (timer.status == 'running') {
      timer.status = 'cancelled';
      timer.finishWaits();
      _saveTimers();
      _checkTimers();
      _notify();
    }
    return _timerResult(timer);
  }

  void _stopTimers(String? ownerId) {
    var changed = false;
    for (final timer in _timers.values) {
      if (timer.status == 'running' &&
          (ownerId == null || timer.ownerId == ownerId)) {
        timer.status = 'cancelled';
        timer.finishWaits();
        changed = true;
      }
    }
    if (changed) {
      _saveTimers();
      _checkTimers();
    }
  }
}
