import '../../../core/files/package_transfer.dart';

typedef AgentPackageStage = PackageStage;
typedef AgentPackageProgress = PackageProgress;
typedef AgentPackageCancelled = PackageCancelled;

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
