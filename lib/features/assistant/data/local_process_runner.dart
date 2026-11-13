import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 管理 AI 启动的进程；不把命令参数检查当作操作系统沙箱。
class LocalProcessRunner {
  static const maxOutputCharacters = 65536;
  final Map<String, _LocalSession> _sessions = {};
  int _nextId = 0;
  int _generation = 0;
  bool _disposed = false;

  Future<Map<String, Object?>> start(
    Map<String, Object?> args, {
    bool Function()? isCancelled,
  }) async {
    if (_disposed || isCancelled?.call() == true) {
      throw StateError('Command cancelled before launch');
    }
    final generation = _generation;
    while (_sessions.length >= 32 &&
        _sessions.values.any((session) => session.finished)) {
      _sessions.remove(
        _sessions.entries.firstWhere((entry) => entry.value.finished).key,
      );
    }
    if (_sessions.values.where((session) => !session.finished).length >= 8) {
      throw StateError('Too many running processes');
    }
    final process = await Process.start(
      args['executable'] as String,
      (args['arguments'] as List).cast<String>(),
      workingDirectory: args['working_directory'] as String,
      runInShell: false,
    );
    final id = 'process-${_nextId++}';
    final session = _LocalSession(process, args['timeout_seconds'] as int);
    _sessions[id] = session;
    if (_disposed || generation != _generation || isCancelled?.call() == true) {
      await session.stop();
      _sessions.remove(id);
      throw StateError('Command cancelled during launch');
    }
    await session.wait(args['yield_ms'] as int);
    return session.snapshot(id, 0);
  }

  Future<Map<String, Object?>> read(Map<String, Object?> args) async {
    final id = args['process_id'] as String;
    final session = _find(id);
    await session.wait(args['wait_ms'] as int);
    return session.snapshot(id, args['cursor'] as int);
  }

  Future<Map<String, Object?>> input(Map<String, Object?> args) async {
    final id = args['process_id'] as String;
    final session = _find(id);
    if (session.exitCode != null) throw StateError('Process has exited');
    session.process.stdin.write(args['input'] as String);
    await session.process.stdin.flush().timeout(const Duration(seconds: 5));
    return {'ok': true, 'process_id': id};
  }

  Future<Map<String, Object?>> stop(String id) async {
    final session = _find(id);
    await session.stop();
    return {...session.snapshot(id, 0), 'ok': session.finished};
  }

  _LocalSession _find(String id) =>
      _sessions[id] ?? (throw StateError('Unknown or expired process id'));

  Future<void> cancelAll({bool forget = false}) async {
    _generation++;
    final sessions = _sessions.values.toList();
    if (forget) _sessions.clear();
    await Future.wait(sessions.map((session) => session.stop()));
  }

  Future<void> dispose() async {
    _disposed = true;
    await cancelAll(forget: true);
  }
}

class _LocalSession {
  _LocalSession(this.process, int timeoutSeconds) {
    final outputDone = Future.wait([
      _capture(process.stdout),
      _capture(process.stderr),
    ]);
    _exited = process.exitCode.then((code) {
      exitCode = code;
      return code;
    });
    _done = Future.wait<Object?>([_exited, outputDone]);
    // 后代进程可能持有输出管道，退出后仍需允许取消它们。
    unawaited(
      _done.then((_) {
        finished = true;
        _timeout.cancel();
      }),
    );
    _timeout = Timer(Duration(seconds: timeoutSeconds), () {
      timedOut = true;
      unawaited(stop());
    });
  }

  final Process process;
  late final Timer _timeout;
  late final Future<int> _exited;
  late final Future<List<Object?>> _done;
  Future<void>? _stopping;
  int? exitCode;
  bool timedOut = false;
  bool stopped = false;
  bool finished = false;
  String _output = '';
  int _start = 0;

  Future<void> _capture(Stream<List<int>> source) async {
    try {
      await for (final text in source.transform(
        const Utf8Decoder(allowMalformed: true),
      )) {
        _output += text;
        final overflow =
            _output.length - LocalProcessRunner.maxOutputCharacters;
        if (overflow > 0) {
          _output = _output.substring(overflow);
          _start += overflow;
        }
      }
    } catch (_) {
      // 结束进程时管道可能关闭；已收集的输出仍保留给模型。
    }
  }

  Future<void> wait(int milliseconds) async {
    if (milliseconds == 0 || finished) return;
    // 等待结束或指定时间，输出增长不会制造新的模型请求。
    await Future.any<void>([
      _done.then((_) {}),
      Future<void>.delayed(Duration(milliseconds: milliseconds)),
    ]);
  }

  Map<String, Object?> snapshot(String id, int cursor) {
    final end = _start + _output.length;
    final offset = cursor.clamp(_start, end) - _start;
    return {
      'ok': !timedOut && !stopped && (exitCode == null || exitCode == 0),
      'process_id': id,
      'running': !finished,
      'exit_code': exitCode,
      'timed_out': timedOut,
      'stopped': stopped,
      'output': _output.substring(offset),
      'output_cursor': end,
      'output_truncated': cursor < _start,
    };
  }

  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    if (finished) return;
    stopped = true;
    _timeout.cancel();
    if (exitCode == null) {
      if (Platform.isWindows) {
        // 参数分开传递，不经 shell 拼接；终止本次进程及其子进程。
        try {
          final killed = await Process.run('taskkill.exe', [
            '/PID',
            '${process.pid}',
            '/T',
            '/F',
          ]).timeout(const Duration(seconds: 5));
          if (killed.exitCode != 0) process.kill(ProcessSignal.sigkill);
        } on Object {
          process.kill(ProcessSignal.sigkill);
        }
      } else {
        process.kill(ProcessSignal.sigkill);
      }
    }
    await _done.timeout(
      const Duration(seconds: 3),
      onTimeout: () => <Object?>[],
    );
  }
}
