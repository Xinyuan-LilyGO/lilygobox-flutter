/// 数据包操作当前可测量的处理阶段。
enum AgentPackageStage {
  preparing,
  reading,
  compressing,
  decompressing,
  verifying,
  checksumming,
  analyzing,
  writing,
  committing,
}

class AgentPackageProgress {
  const AgentPackageProgress(
    this.stage, {
    this.completed,
    this.total,
    this.canCancel = true,
  });

  final AgentPackageStage stage;
  final int? completed;
  final int? total;
  final bool canCancel;
  double? get fraction => completed != null && total != null && total! > 0
      ? (completed! / total!).clamp(0, 1)
      : null;
}

class AgentPackageCancelled implements Exception {
  const AgentPackageCancelled();
}

/// 通知后台任务和文件读写流程取消当前操作。
class AgentPackageCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  void throwIfCancelled() {
    if (_cancelled) throw const AgentPackageCancelled();
  }

  void addListener(void Function() listener) {
    _listeners.add(listener);
    if (_cancelled) listener();
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);
}
