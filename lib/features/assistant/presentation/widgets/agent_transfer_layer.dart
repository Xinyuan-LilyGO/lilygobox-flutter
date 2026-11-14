import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../state/agent_workspace_provider.dart';
import 'task_topology_connection.dart';

/// Only this overlay ticks; cards, routes and grid stay outside its repaint.
class AgentTransferLayer extends StatefulWidget {
  const AgentTransferLayer({
    super.key,
    required this.transfers,
    required this.connections,
    required this.routes,
    required this.transform,
    required this.color,
  });
  final ValueListenable<List<AiAgentTransfer>> transfers;
  final List<AiTaskConnection> connections;
  final Map<String, TaskTopologyConnection> routes;
  final TransformationController transform;
  final Color color;
  @override
  State<AgentTransferLayer> createState() => _AgentTransferLayerState();
}

class _AgentTransferLayerState extends State<AgentTransferLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: AiAgentTransfer.duration,
  );
  @override
  void initState() {
    super.initState();
    widget.transfers.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AgentTransferLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transfers != widget.transfers) {
      oldWidget.transfers.removeListener(_sync);
      widget.transfers.addListener(_sync);
    }
    _sync();
  }

  int? _lastTransfer;

  void _sync() {
    if (widget.transfers.value.isNotEmpty &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.of(context)) {
      final latest = widget.transfers.value.last.id;
      if (latest != _lastTransfer) {
        _lastTransfer = latest;
        _clock.forward(from: 0);
      } else if (!_clock.isAnimating && _clock.value < 1) {
        _clock.forward();
      }
    } else {
      _clock.stop();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.transfers.removeListener(_sync);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('topology-transfer-paint'),
        painter: AgentTransferPainter(
          transfers: widget.transfers.value,
          connections: widget.connections,
          routes: widget.routes,
          transform: widget.transform,
          color: widget.color,
          clock: _clock,
          reducedMotion: MediaQuery.disableAnimationsOf(context),
        ),
      ),
    ),
  );
}

class AgentTransferPainter extends CustomPainter {
  AgentTransferPainter({
    required this.transfers,
    required this.connections,
    required this.routes,
    required this.transform,
    required this.color,
    required this.clock,
    required this.reducedMotion,
  }) : super(repaint: Listenable.merge([clock, transform]));
  final List<AiAgentTransfer> transfers;
  final List<AiTaskConnection> connections;
  final Map<String, TaskTopologyConnection> routes;
  final TransformationController transform;
  final Color color;
  final Animation<double> clock;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = transform.value.entry(0, 0).abs().clamp(.25, 1.8);
    final now = DateTime.now();
    final dashed = <String>{};
    for (final transfer in transfers) {
      AiTaskConnection? edge;
      for (final item in connections) {
        if ((item.fromId == transfer.fromId && item.toId == transfer.toId) ||
            (item.toId == transfer.fromId && item.fromId == transfer.toId)) {
          edge = item;
          break;
        }
      }
      if (edge == null) continue;
      final route = routes[edge.id];
      if (route == null) continue;
      final metrics = route.path.computeMetrics().toList();
      if (metrics.isEmpty) continue;
      final metric = metrics.single;
      final forward = edge.fromId == transfer.fromId;
      final progress = reducedMotion
          ? .5
          : (now.difference(transfer.startedAt).inMicroseconds /
                    AiAgentTransfer.duration.inMicroseconds)
                .clamp(0.0, 1.0);
      if (dashed.add(edge.id)) {
        final period = 10 / scale;
        final phase = reducedMotion
            ? 0.0
            : clock.value * period * 2 * (forward ? 1 : -1);
        final paint = Paint()
          ..color = color.withValues(alpha: .7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale
          ..strokeCap = StrokeCap.round;
        for (double d = -period + phase; d < metric.length; d += period) {
          final start = math.max(0.0, d);
          final end = math.min(metric.length, d + 4 / scale);
          if (end > start) {
            canvas.drawPath(metric.extractPath(start, end), paint);
          }
        }
      }
      final position = metric
          .getTangentForOffset(
            metric.length * (forward ? progress : 1 - progress),
          )
          ?.position;
      if (position == null) continue;
      canvas.drawCircle(
        position,
        7 / scale,
        Paint()..color = color.withValues(alpha: .15),
      );
      canvas.drawCircle(position, 3.5 / scale, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(AgentTransferPainter oldDelegate) => true;
}
