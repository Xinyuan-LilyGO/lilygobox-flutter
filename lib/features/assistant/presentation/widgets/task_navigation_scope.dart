import 'package:flutter/material.dart';

/// Opens an existing task inside the retained workflow conversation stack.
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
