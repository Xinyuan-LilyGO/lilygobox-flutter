import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'task_topology_connection.dart';

/// 选中动画仅重绘连线，网格和卡片保持缓存。
class TaskTopologyConnectionLayer extends StatefulWidget {
  const TaskTopologyConnectionLayer({
    super.key,
    required this.routes,
    required this.selectedEdges,
    required this.activeEdges,
    required this.lineColor,
    required this.accentColor,
    required this.scale,
  });

  final Map<String, TaskTopologyConnection> routes;
  final Set<String> selectedEdges;
  final Set<String> activeEdges;
  final Color lineColor;
  final Color accentColor;
  final double scale;

  @override
  State<TaskTopologyConnectionLayer> createState() =>
      _TaskTopologyConnectionLayerState();
}

class _TaskTopologyConnectionLayerState
    extends State<TaskTopologyConnectionLayer>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 167),
    value: 1,
  );
  Map<String, double> _starts = {};
  Map<String, double> _ends = {};

  double _selection(String id) {
    final end = _ends[id] ?? 0;
    final start = _starts[id] ?? end;
    return start + (end - start) * Curves.fastOutSlowIn.transform(_clock.value);
  }

  @override
  void initState() {
    super.initState();
    _ends = {for (final id in widget.selectedEdges) id: 1};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = 1;
    }
  }

  @override
  void didUpdateWidget(TaskTopologyConnectionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (setEquals(oldWidget.selectedEdges, widget.selectedEdges)) return;
    final ids = {..._starts.keys, ..._ends.keys, ...widget.selectedEdges}
      ..retainWhere(widget.routes.containsKey);
    final starts = {for (final id in ids) id: _selection(id)};
    _ends = {
      for (final id in ids) id: widget.selectedEdges.contains(id) ? 1 : 0,
    };
    _starts = starts;
    if (MediaQuery.disableAnimationsOf(context) ||
        starts.keys.every((id) => starts[id] == _ends[id])) {
      _clock.value = 1;
    } else {
      _clock.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('topology-connections-paint'),
        painter: TaskTopologyConnectionsPainter(
          routes: widget.routes,
          selectedEdges: widget.selectedEdges,
          activeEdges: widget.activeEdges,
          lineColor: widget.lineColor,
          accentColor: widget.accentColor,
          scale: widget.scale,
          selection: _selection,
          clock: _clock,
        ),
      ),
    ),
  );
}

class TaskTopologyConnectionsPainter extends CustomPainter {
  TaskTopologyConnectionsPainter({
    required this.routes,
    required this.selectedEdges,
    required this.activeEdges,
    required this.lineColor,
    required this.accentColor,
    required this.scale,
    required this.selection,
    required Listenable clock,
  }) : super(repaint: clock);

  final Map<String, TaskTopologyConnection> routes;
  final Set<String> selectedEdges;
  final Set<String> activeEdges;
  final Color lineColor;
  final Color accentColor;
  final double scale;
  final double Function(String id) selection;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..style = PaintingStyle.stroke;
    final socket = Paint();
    final selectedWidth = 2 / scale.clamp(.25, 1.8);
    for (final entry in routes.entries) {
      final amount = selection(entry.key);
      final color = Color.lerp(lineColor, accentColor, amount)!;
      line
        ..color = color
        ..strokeWidth = 1.5 + (selectedWidth - 1.5) * amount;
      socket.color = color;
      if (!activeEdges.contains(entry.key)) {
        canvas.drawPath(entry.value.path, line);
      }
      canvas.drawCircle(entry.value.start, 3.5, socket);
      canvas.drawCircle(entry.value.end, 3.5, socket);
    }
  }

  @override
  bool shouldRepaint(TaskTopologyConnectionsPainter oldDelegate) =>
      !identical(oldDelegate.routes, routes) ||
      !setEquals(oldDelegate.selectedEdges, selectedEdges) ||
      !setEquals(oldDelegate.activeEdges, activeEdges) ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.scale != scale;
}
