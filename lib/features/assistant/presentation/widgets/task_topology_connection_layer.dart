import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/task_canvas_style.dart';
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
    this.revision = 0,
    this.bounds,
  });

  final Map<String, TaskTopologyConnection> routes;
  final Set<String> selectedEdges;
  final Set<String> activeEdges;
  final Color lineColor;
  final Color accentColor;
  final double scale;
  final int revision;
  final Rect? bounds;

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
  Map<String, Path> _paths = {};
  Map<String, List<Offset>> _polylines = {};
  List<_ConnectionInk> _batches = [];
  double? _pixelRatio;

  bool get _useSegments =>
      widget.bounds != null &&
      widget.routes.length >= 64 &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      !ui.ImageFilter.isShaderFilterSupported;

  void _updatePaths() {
    final bounds = widget.bounds;
    if (_useSegments) {
      final tolerance = .3 / (_pixelRatio! * widget.scale);
      _polylines = {
        for (final entry in widget.routes.entries)
          entry.key: ?entry.value.clippedPolyline(bounds!, tolerance),
      };
      _paths = const {};
      return;
    }
    _polylines = const {};
    _paths = {
      for (final entry in widget.routes.entries)
        entry.key: ?(bounds == null
            ? entry.value.path
            : entry.value.clippedPath(bounds)),
    };
  }

  void _updateBatches() {
    final groups = <(double, double), List<String>>{};
    for (final id in _paths.isEmpty ? _polylines.keys : _paths.keys) {
      final end = _ends[id] ?? 0;
      (groups[(_starts[id] ?? end, end)] ??= []).add(id);
    }
    final ordered = groups.entries.toList()
      ..sort((lhs, rhs) {
        final byTarget = lhs.key.$2.compareTo(rhs.key.$2);
        return byTarget == 0 ? lhs.key.$1.compareTo(rhs.key.$1) : byTarget;
      });
    _batches = [
      for (final group in ordered)
        for (var start = 0; start < group.value.length; start += 32)
          _ConnectionInk(
            group.value.getRange(
              start,
              (start + 32).clamp(0, group.value.length),
            ),
            _paths,
            _polylines,
            widget,
          ),
    ];
  }

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
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (_pixelRatio != ratio) {
      _pixelRatio = ratio;
      _updatePaths();
      _updateBatches();
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = 1;
    }
  }

  @override
  void didUpdateWidget(TaskTopologyConnectionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final geometryChanged =
        !identical(oldWidget.routes, widget.routes) ||
        widget.bounds != oldWidget.bounds ||
        (_useSegments && widget.scale != oldWidget.scale) ||
        widget.revision != oldWidget.revision;
    if (geometryChanged) _updatePaths();
    if (setEquals(oldWidget.selectedEdges, widget.selectedEdges)) {
      if (geometryChanged ||
          !setEquals(oldWidget.activeEdges, widget.activeEdges)) {
        _updateBatches();
      }
      return;
    }
    final ids = {..._starts.keys, ..._ends.keys, ...widget.selectedEdges}
      ..retainWhere(widget.routes.containsKey);
    final starts = {for (final id in ids) id: _selection(id)};
    _ends = {
      for (final id in ids) id: widget.selectedEdges.contains(id) ? 1 : 0,
    };
    _starts = starts;
    _updateBatches();
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
  Widget build(BuildContext context) {
    final bounds = widget.bounds;
    final drawing = RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('topology-connections-paint'),
        isComplex: bounds != null,
        painter: TaskTopologyConnectionsPainter._(
          routes: widget.routes,
          bounds: bounds,
          batches: _batches,
          revision: widget.revision,
          selectedEdges: widget.selectedEdges,
          activeEdges: widget.activeEdges,
          lineColor: widget.lineColor,
          accentColor: widget.accentColor,
          scale: widget.scale,
          selection: _selection,
          clock: _clock,
        ),
      ),
    );
    return IgnorePointer(
      child: bounds == null
          ? drawing
          : Stack(
              clipBehavior: Clip.none,
              children: [Positioned.fromRect(rect: bounds, child: drawing)],
            ),
    );
  }
}

class _ConnectionInk {
  _ConnectionInk(
    Iterable<String> ids,
    Map<String, Path> paths,
    Map<String, List<Offset>> polylines,
    TaskTopologyConnectionLayer layer,
  ) : sample = ids.first {
    final coordinates = <double>[];
    final segmentCoordinates = <double>[];
    final bounds = layer.bounds;
    final origin = bounds?.topLeft ?? Offset.zero;
    for (final id in ids) {
      if (!layer.activeEdges.contains(id)) {
        if (paths[id] case final path?) {
          (strokes ??= Path()).addPath(path, -origin);
        } else {
          final points = polylines[id]!;
          var from = points.first - origin;
          for (var index = 1; index < points.length; index++) {
            final to = points[index] - origin;
            segmentCoordinates.addAll([from.dx, from.dy, to.dx, to.dy]);
            from = to;
          }
        }
      }
      final route = layer.routes[id]!;
      for (final point in [route.start, route.end]) {
        if (bounds == null || bounds.contains(point)) {
          coordinates.add(point.dx - origin.dx);
          coordinates.add(point.dy - origin.dy);
        }
      }
    }
    sockets = Float32List.fromList(coordinates);
    if (segmentCoordinates.isNotEmpty) {
      segments = Float32List.fromList(segmentCoordinates);
    }
  }

  final String sample;
  Path? strokes;
  Float32List? segments;
  late final Float32List sockets;
}

class TaskTopologyConnectionsPainter extends CustomPainter {
  TaskTopologyConnectionsPainter._({
    required this.routes,
    this.revision = 0,
    this.bounds,
    required this._batches,
    required this.selectedEdges,
    required this.activeEdges,
    required this.lineColor,
    required this.accentColor,
    required this.scale,
    required this.selection,
    required Listenable clock,
  }) : super(repaint: clock);

  final Map<String, TaskTopologyConnection> routes;
  final int revision;
  final Rect? bounds;
  final List<_ConnectionInk> _batches;
  final Set<String> selectedEdges;
  final Set<String> activeEdges;
  final Color lineColor;
  final Color accentColor;
  final double scale;
  final double Function(String id) selection;

  @override
  void paint(Canvas canvas, Size size) {
    final region = bounds;
    if (region != null) {
      canvas.save();
      canvas.clipRect(Offset.zero & size);
    }
    final line = Paint()..style = PaintingStyle.stroke;
    final socket = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7;
    final selectedWidth =
        2 / scale.clamp(taskCanvasMinScale, taskCanvasMaxScale);
    for (final batch in _batches) {
      final amount = selection(batch.sample);
      final color = Color.lerp(lineColor, accentColor, amount)!;
      line
        ..color = color
        ..strokeWidth = 1.5 + (selectedWidth - 1.5) * amount;
      socket.color = color;
      if (batch.strokes case final path?) canvas.drawPath(path, line);
      if (batch.segments case final points?) {
        canvas.drawRawPoints(ui.PointMode.lines, points, line);
      }
      if (batch.sockets.isNotEmpty) {
        canvas.drawRawPoints(ui.PointMode.points, batch.sockets, socket);
      }
    }
    if (region != null) canvas.restore();
  }

  @override
  bool shouldRepaint(TaskTopologyConnectionsPainter oldDelegate) =>
      !identical(oldDelegate._batches, _batches) ||
      !identical(oldDelegate.routes, routes) ||
      oldDelegate.bounds != bounds ||
      oldDelegate.revision != revision ||
      !setEquals(oldDelegate.selectedEdges, selectedEdges) ||
      !setEquals(oldDelegate.activeEdges, activeEdges) ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.scale != scale;
}
