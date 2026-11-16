import 'package:material_ui/material_ui.dart';

/// 在保留状态的工作流对话栈中打开已有任务。
class TaskNavigationScope extends InheritedWidget {
  const TaskNavigationScope({
    super.key,
    required this.openTask,
    required super.child,
  });
  final bool Function(String taskId) openTask;
  static TaskNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TaskNavigationScope>();
  @override
  bool updateShouldNotify(TaskNavigationScope oldWidget) =>
      openTask != oldWidget.openTask;
}
