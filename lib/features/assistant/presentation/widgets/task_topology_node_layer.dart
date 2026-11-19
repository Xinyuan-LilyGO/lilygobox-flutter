import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

class TaskCanvasDragPreview extends ValueNotifier<Offset> {
  TaskCanvasDragPreview() : super(Offset.zero);

  Map<String, Offset> starts = const {};
  bool all = false;
  final partial = ValueNotifier(Offset.zero);

  void move(Offset delta) {
    if (!all) partial.value = delta;
    value = delta;
  }

  void reset() {
    final endedAtOrigin = starts.isNotEmpty && value == Offset.zero;
    starts = const {};
    all = false;
    partial.value = Offset.zero;
    value = Offset.zero;
    if (endedAtOrigin) notifyListeners();
  }

  @override
  void dispose() {
    partial.dispose();
    super.dispose();
  }
}

class TaskCanvasSpatialIndex {
  static const _tileSize = 512.0;
  final _bounds = <String, Rect>{};
  final _tiles = <(int, int), Set<String>>{};
  final _large = <String>{};

  Rect? operator [](String id) => _bounds[id];
  Iterable<String> get ids => _bounds.keys;

  Iterable<(int, int)> _cells(Rect rect) sync* {
    final left = (rect.left / _tileSize).floor();
    final right = (rect.right / _tileSize).floor();
    final top = (rect.top / _tileSize).floor();
    final bottom = (rect.bottom / _tileSize).floor();
    for (var row = top; row <= bottom; row++) {
      for (var column = left; column <= right; column++) {
        yield (column, row);
      }
    }
  }

  bool _isLarge(Rect rect) =>
      (rect.width / _tileSize + 2) * (rect.height / _tileSize + 2) > 256;

  bool remove(String id) {
    final previous = _bounds.remove(id);
    if (previous == null) return false;
    if (!_large.remove(id)) {
      for (final cell in _cells(previous)) {
        final items = _tiles[cell]!;
        items.remove(id);
        if (items.isEmpty) _tiles.remove(cell);
      }
    }
    return true;
  }

  bool update(String id, Rect rect) {
    if (_bounds[id] == rect) return false;
    remove(id);
    _bounds[id] = rect;
    if (_isLarge(rect)) {
      _large.add(id);
    } else {
      for (final cell in _cells(rect)) {
        (_tiles[cell] ??= {}).add(id);
      }
    }
    return true;
  }

  bool containsPoint(Offset point) {
    final cell = (
      (point.dx / _tileSize).floor(),
      (point.dy / _tileSize).floor(),
    );
    bool contains(String id) => _bounds[id]!.contains(point);
    return (_tiles[cell]?.any(contains) ?? false) || _large.any(contains);
  }

  Set<String> intersecting(Rect area) {
    final cellCount =
        (area.width / _tileSize + 2) * (area.height / _tileSize + 2);
    if (cellCount > 256 && cellCount > _bounds.length) {
      return {
        for (final entry in _bounds.entries)
          if (entry.value.overlaps(area)) entry.key,
      };
    }
    final result = <String>{};
    for (final cell in _cells(area)) {
      final items = _tiles[cell];
      if (items != null) result.addAll(items);
    }
    return result
      ..addAll(_large)
      ..removeWhere((id) => !_bounds[id]!.overlaps(area));
  }
}

class TaskTopologyNodeLayer extends StatefulWidget {
  const TaskTopologyNodeLayer({
    super.key,
    required this.index,
    required this.transform,
    required this.viewport,
    required this.geometry,
    required this.layers,
    required this.pinnedIds,
    required this.nodeBuilder,
    this.overviewNodeBuilder,
    this.drag,
  });

  final TaskCanvasSpatialIndex index;
  final TransformationController transform;
  final Size viewport;
  final Listenable geometry;
  final Map<String, int> layers;
  final Iterable<String> Function() pinnedIds;
  final Widget Function(String id) nodeBuilder;
  final Widget Function(String id)? overviewNodeBuilder;
  final TaskCanvasDragPreview? drag;

  @override
  State<TaskTopologyNodeLayer> createState() => _TaskTopologyNodeLayerState();
}

class _TaskTopologyNodeLayerState extends State<TaskTopologyNodeLayer> {
  final _nodes = <String, Widget>{};
  final _overviewIds = <String>{};
  bool _overview = false;
  List<String> _visible = const [];
  Rect _coverage = Rect.zero;
  Rect _movingCoverage = Rect.zero;
  bool _splitCoverage = false;
  double _coverageScale = 0;

  @override
  void initState() {
    super.initState();
    widget.transform.addListener(_viewChanged);
    widget.geometry.addListener(_geometryChanged);
    widget.drag?.addListener(_viewChanged);
    _refresh(force: true);
  }

  @override
  void didUpdateWidget(TaskTopologyNodeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transform != widget.transform) {
      oldWidget.transform.removeListener(_viewChanged);
      widget.transform.addListener(_viewChanged);
    }
    if (oldWidget.geometry != widget.geometry) {
      oldWidget.geometry.removeListener(_geometryChanged);
      widget.geometry.addListener(_geometryChanged);
    }
    if (oldWidget.drag != widget.drag) {
      oldWidget.drag?.removeListener(_viewChanged);
      widget.drag?.addListener(_viewChanged);
    }
    _nodes.clear();
    _refresh(force: true);
  }

  void _viewChanged() {
    if (_refresh(force: false)) setState(() {});
  }

  void _geometryChanged() {
    if (_refresh(force: true)) setState(() {});
  }

  bool _refresh({required bool force}) {
    final scale = widget.transform.value.entry(0, 0).abs();
    if (!scale.isFinite || scale == 0 || widget.viewport.isEmpty) return false;
    final viewport = Rect.fromPoints(
      widget.transform.toScene(Offset.zero),
      widget.transform.toScene(widget.viewport.bottomRight(Offset.zero)),
    );
    final overview =
        widget.overviewNodeBuilder != null && scale <= (_overview ? .55 : .45);
    final drag = widget.drag;
    final offset = drag?.value ?? Offset.zero;
    final movingView = viewport.shift(-offset);
    final allMoving = drag?.all ?? false;
    final splitCoverage = !allMoving && (drag?.starts.isNotEmpty ?? false);
    if (!force &&
        splitCoverage == _splitCoverage &&
        overview == _overview &&
        scale < _coverageScale * 1.5 &&
        (allMoving ||
            (_coverage.contains(viewport.topLeft) &&
                _coverage.contains(viewport.bottomRight))) &&
        _movingCoverage.contains(movingView.topLeft) &&
        _movingCoverage.contains(movingView.bottomRight)) {
      return false;
    }
    _coverage = viewport.inflate(96 / scale);
    _movingCoverage = movingView.inflate(96 / scale);
    _splitCoverage = splitCoverage;
    _coverageScale = scale;
    _overview = overview;
    final candidates = allMoving
        ? widget.index.intersecting(_movingCoverage)
        : widget.index.intersecting(_coverage);
    if (splitCoverage && drag != null) {
      candidates.removeWhere(drag.starts.containsKey);
      candidates.addAll(
        widget.index
            .intersecting(_movingCoverage)
            .where(drag.starts.containsKey),
      );
    }
    final exposed = <(Rect, bool), (String, String?)>{};
    for (final id in candidates) {
      final rank = widget.layers[id];
      if (rank == null) continue;
      final bounds = (
        widget.index[id]!,
        splitCoverage && drag!.starts.containsKey(id),
      );
      final previous = exposed[bounds];
      if (previous == null || rank > widget.layers[previous.$1]!) {
        exposed[bounds] = (id, previous?.$1);
      } else if (previous.$2 == null || rank > widget.layers[previous.$2]!) {
        exposed[bounds] = (previous.$1, id);
      }
    }
    final pinned = widget.pinnedIds().where(widget.layers.containsKey).toSet();
    final visible = <String>{
      ...pinned,
      for (final (front, behind) in exposed.values) ...[front, ?behind],
    };
    final sorted = visible.toList()
      ..sort(
        (first, second) =>
            widget.layers[first]!.compareTo(widget.layers[second]!),
      );
    final nextOverview = <String>{
      for (final id in visible)
        if (pinned.contains(id) && _visible.contains(id)
            ? _overviewIds.contains(id)
            : overview)
          id,
    };
    if (listEquals(sorted, _visible) && setEquals(nextOverview, _overviewIds)) {
      return false;
    }
    _visible = sorted;
    _nodes.removeWhere(
      (id, _) =>
          !visible.contains(id) ||
          nextOverview.contains(id) != _overviewIds.contains(id),
    );
    _overviewIds
      ..clear()
      ..addAll(nextOverview);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cards = RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final id in _visible)
            _nodes.putIfAbsent(
              id,
              () => _overviewIds.contains(id)
                  ? widget.overviewNodeBuilder!(id)
                  : widget.nodeBuilder(id),
            ),
        ],
      ),
    );
    final drag = widget.drag;
    if (drag == null) return cards;
    return ValueListenableBuilder<Offset>(
      valueListenable: drag,
      child: cards,
      builder: (context, offset, child) => Transform.translate(
        offset: drag.all ? offset : Offset.zero,
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    widget.transform.removeListener(_viewChanged);
    widget.geometry.removeListener(_geometryChanged);
    widget.drag?.removeListener(_viewChanged);
    super.dispose();
  }
}
