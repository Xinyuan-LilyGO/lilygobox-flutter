/*
 * @Description: 在可平移缩放的多层智能体树中组织主智能体和可见子智能体，并保留独立对话。
 * @Author: LILYGO_L
 * @Date: 2026-11-13 22:04:31
 * @LastEditTime: 2026-11-13 23:16:03
 */
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/provider.dart';
import '../../../../core/context_menu/right_click_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/card_shadow.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/retained_page_stack.dart';
import '../../../../core/widgets/settings/fields.dart';
import '../../../../core/widgets/settings/select.dart';
import '../../../../core/widgets/tilt_card.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../domain/task_canvas_style.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/provider.dart';
import '../widgets/agent_transfer_layer.dart';
import '../widgets/error_text.dart';
import '../widgets/model_selector.dart';
import '../widgets/permissions_button.dart';
import '../widgets/process_event_view.dart';
import '../widgets/task_canvas_background.dart';
import '../widgets/task_navigation_scope.dart';
import '../widgets/task_topology_connection.dart';
import '../widgets/task_topology_layout.dart';
import '../widgets/task_topology_routes.dart';
import 'page.dart';

const _nodeSize = Size(252, 144);
const _taskNodeTitleStyle = TextStyle(
  fontSize: 13,
  height: 1.3,
  fontWeight: FontWeight.w500,
);
const _taskKindTitleStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
);
const _taskKindIconSize = 18.0;
const _sceneSize = Size(1060, 700);

class TaskTopologyPage extends StatefulWidget {
  const TaskTopologyPage({super.key});
  @override
  State<TaskTopologyPage> createState() => _TaskTopologyPageState();
}

class _TaskTopologyPageState extends State<TaskTopologyPage>
    with SingleTickerProviderStateMixin {
  static const _graphKey = 'topology-graph';
  final _transform = TransformationController();
  late final AnimationController _viewMotion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(_animateView);
  Animation<Matrix4>? _viewFrames;
  double? _wheelZoomTargetScale;
  int _wheelZoomDirection = 0;
  Offset? _wheelPanTarget;
  Offset _wheelPanDirection = Offset.zero;

  void _animateView() {
    if (_viewFrames case final frames?) _transform.value = frames.value;
  }

  final _movedNodes = <String, Offset>{};
  final _nodeMenus = <String, RightClickMenuController>{};
  final _backgroundMenu = RightClickMenuController();
  final _canvasMenu = RightClickMenuController();
  final _canvasFocus = FocusNode(debugLabel: 'task topology canvas');
  final _sceneKey = GlobalKey();
  final _selectedIds = <String>{};
  final _frontOrder = <String>[];
  List<AiTaskCardCopy> _copiedCards = const [];
  Map<String, Offset> _copiedPositions = const {};
  String? _cardClipboardToken;
  int _pasteCount = 0;
  bool _pastingCards = false;
  bool _connectingTasks = false;
  bool _disconnectingTasks = false;
  final _selectedEdges = <String>{};
  Set<String> _boxEdgeBase = {};
  String? _rightEdge;
  String? _hoveredNode;
  String? _connectingSource;
  Offset? _connectingStart;
  Offset? _connectingEnd;
  final _connectionPointer = ValueNotifier<Offset?>(null);
  int? _canvasPanPointer;
  int? _menuPanPointer;
  Offset? _menuPanDown;
  bool _menuPanStarted = false;
  bool _boxDragging = false;
  int? _secondaryPointer;
  Offset? _secondaryDown;
  int? _boxPointer;
  Offset? _boxStart;
  Rect? _boxRect;
  final _selectionRect = ValueNotifier<Rect?>(null);
  Set<String> _boxBase = {};
  Map<String, Offset> _dragStarts = {};
  Offset _dragDelta = Offset.zero;
  String? _lastTapId;
  Duration? _lastTapTime;
  Offset? _lastTapPosition;
  Offset? _nodePointerDown;
  bool _nodePrimaryDown = false;
  String? _openId;
  int _lastWorkflowHomeRevision = 0;
  final List<String?> _conversationHistory = [];
  int _lastNavigationRevision = 0;
  AiWorkspaceProvider? _navigationWorkspace;
  Size _viewport = Size.zero;
  Map<String, Offset> _positions = const {};
  Map<String, Size> _nodeSizes = const {};
  Map<String, TaskTopologyConnection> _connectionRoutes = const {};
  Map<String, Rect> _routedNodes = const {};
  List<(String, String, String)> _routedEdges = const [];

  final _undoEdits = <(_TopologyEditFrame, _TopologyEditFrame)>[];
  final _redoEdits = <(_TopologyEditFrame, _TopologyEditFrame)>[];
  AiWorkspaceProvider? _historyWorkspace;
  _TopologyEditFrame? _dragEdit;
  bool _restoringHistory = false;

  _TopologyEditFrame _captureEdit(AiWorkspaceProvider workspaces) {
    _historyWorkspace = workspaces;
    final visible = workspaces.sessions.toList();
    final fallback = _layout(visible);
    return _TopologyEditFrame(
      workspaces.captureTopologyEdit(),
      {
        for (final task in visible)
          task.id:
              _movedNodes[task.id] ??
              _positions[task.id] ??
              fallback[task.id] ??
              Offset.zero,
      },
      List.of(_frontOrder),
      Set.of(_selectedIds),
      Set.of(_selectedEdges),
      _transform.value.clone(),
    );
  }

  void _releaseFrame(_TopologyEditFrame frame) =>
      _historyWorkspace?.releaseTopologyEdit(frame.snapshot);

  void _clearEdits(List<(_TopologyEditFrame, _TopologyEditFrame)> edits) {
    for (final (before, after) in edits) {
      _releaseFrame(before);
      _releaseFrame(after);
    }
    edits.clear();
  }

  void _finishEdit(AiWorkspaceProvider workspaces, _TopologyEditFrame before) {
    if (!mounted) {
      _releaseFrame(before);
      return;
    }
    final after = _captureEdit(workspaces);
    if (before.snapshot.matches(after.snapshot) &&
        mapEquals(before.positions, after.positions) &&
        listEquals(before.frontOrder, after.frontOrder)) {
      _releaseFrame(before);
      _releaseFrame(after);
      return;
    }
    _clearEdits(_redoEdits);
    _undoEdits.add((before, after));
    if (_undoEdits.length > 30) {
      final (oldBefore, oldAfter) = _undoEdits.removeAt(0);
      _releaseFrame(oldBefore);
      _releaseFrame(oldAfter);
    }
  }

  void _edit(AiWorkspaceProvider workspaces, VoidCallback action) {
    final before = _captureEdit(workspaces);
    try {
      action();
      _finishEdit(workspaces, before);
    } catch (_) {
      _releaseFrame(before);
      rethrow;
    }
  }

  Future<T> _editAsync<T>(
    AiWorkspaceProvider workspaces,
    Future<T> Function() action,
  ) async {
    final before = _captureEdit(workspaces);
    try {
      final result = await action();
      _finishEdit(workspaces, before);
      return result;
    } catch (_) {
      _releaseFrame(before);
      rethrow;
    }
  }

  Future<void> _historyStep(
    AiWorkspaceProvider workspaces, {
    required bool redo,
  }) async {
    if (_restoringHistory ||
        _pastingCards ||
        _connectingTasks ||
        _disconnectingTasks ||
        _dragEdit != null) {
      return;
    }
    final source = redo ? _redoEdits : _undoEdits;
    final destination = redo ? _undoEdits : _redoEdits;
    if (source.isEmpty) return;
    _restoringHistory = true;
    final entry = source.last;
    final frame = redo ? entry.$2 : entry.$1;
    try {
      _closeCanvasMenus();
      _viewMotion.stop();
      await workspaces.restoreTopologyEdit(
        frame.snapshot,
        previous: (redo ? entry.$1 : entry.$2).snapshot,
      );
      if (!mounted) return;
      setState(() {
        _movedNodes
          ..clear()
          ..addAll(frame.positions);
        _positions = Map.of(frame.positions);
        _frontOrder
          ..clear()
          ..addAll(frame.frontOrder);
        _selectedIds
          ..clear()
          ..addAll(
            frame.selectedIds.where((id) => workspaces.find(id) != null),
          );
        final edges = workspaces.connections.map((edge) => edge.id).toSet();
        _selectedEdges
          ..clear()
          ..addAll(frame.selectedEdges.where(edges.contains));
        _lastCount = workspaces.sessions.length;
        _lastTapId = null;
        _rightEdge = null;
        _transform.value = frame.transform.clone();
      });
      workspaces.select(_selectedIds.lastOrNull);
      source.removeLast();
      destination.add(entry);
    } catch (error) {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          aiErrorText(context.l10n, error),
        );
      }
    } finally {
      _restoringHistory = false;
    }
  }

  Size _size(String? id) => _nodeSizes[id] ?? _nodeSize;

  Size _measureNode(AiAgentWorkspace session) {
    final scaler = MediaQuery.textScalerOf(context);
    double height(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        locale: Localizations.maybeLocaleOf(context),
      )..layout(maxWidth: _nodeSize.width - 28);
      final result = painter.height;
      painter.dispose();
      return result;
    }

    final title = height(session.title, _taskNodeTitleStyle);
    final twoLines = height('M\nM', _taskNodeTitleStyle);
    final small = height('M', const TextStyle(fontSize: 10));
    final kind = height('M', _taskKindTitleStyle);
    final status = height('M', const TextStyle(fontSize: 11));
    final taskId = height(
      context.l10n.aiAgentIdValue(session.id),
      const TextStyle(fontSize: 10),
    );
    final minimum = _nodeSize.height * math.max(1, scaler.scale(13) / 13);
    final content =
        22 +
        math.max(_taskKindIconSize, kind) +
        10 +
        title +
        small +
        taskId +
        4 +
        7 +
        math.max(22, status) +
        6;
    return Size(
      _nodeSize.width,
      math.max(minimum + math.max(0, title - twoLines), content).ceilToDouble(),
    );
  }

  int _lastCount = -1;

  @override
  void dispose() {
    _clearEdits(_undoEdits);
    _clearEdits(_redoEdits);
    if (_dragEdit case final frame?) _releaseFrame(frame);
    _navigationWorkspace?.activeConversationId = null;
    _selectionRect.dispose();
    _connectionPointer.dispose();
    _canvasFocus.dispose();
    _viewMotion.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _open(AiWorkspaceProvider workspaces, AiAgentWorkspace session) {
    if (_openId == session.id) return;
    _conversationHistory.add(_openId);
    workspaces.activeConversationId = session.id;
    workspaces.select(session.id);
    setState(() {
      _selectedIds
        ..clear()
        ..add(session.id);
      _openId = session.id;
    });
  }

  bool _openLinkedTask(AiWorkspaceProvider workspaces, String id) {
    final task = workspaces.find(id);
    if (task == null) {
      showAppNotice(
        ScaffoldMessenger.of(context),
        context.l10n.aiTaskLinkUnavailable,
      );
      return false;
    }
    _open(workspaces, task);
    return true;
  }

  void _backToConversation(AiWorkspaceProvider workspaces) {
    String? target;
    while (_conversationHistory.isNotEmpty) {
      final previous = _conversationHistory.removeLast();
      if (previous == null || workspaces.find(previous) != null) {
        target = previous;
        break;
      }
    }
    workspaces.activeConversationId = target;
    if (target != null) workspaces.select(target);
    setState(() => _openId = target);
  }

  bool get _extendSelection =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isShiftPressed;

  void _selectNode(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session, {
    bool contextMenu = false,
  }) {
    _canvasFocus.requestFocus();
    _viewMotion.stop();
    setState(() {
      if (contextMenu && _selectedIds.contains(session.id)) return;
      if (contextMenu || !_extendSelection) _selectedEdges.clear();
      if (!contextMenu && _extendSelection) {
        if (!_selectedIds.add(session.id)) _selectedIds.remove(session.id);
      } else {
        _selectedIds
          ..clear()
          ..add(session.id);
      }
    });
    workspaces.select(
      _selectedIds.contains(session.id) ? session.id : _selectedIds.lastOrNull,
    );
  }

  void _closeCanvasMenus() {
    for (final menu in _nodeMenus.values) {
      menu.close();
    }
    _canvasMenu.close();
    _backgroundMenu.close();
  }

  void _menuPointerEvent(PointerEvent event) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        final scene = _scenePoint(event.position);
        final anchor = MatrixUtils.transformPoint(_transform.value, scene);
        _closeCanvasMenus();
        _zoomAt(
          math.exp(-event.scrollDelta.dy / 200),
          anchor,
          animate: true,
          accumulateWheel: true,
        );
      });
      return;
    }
    if (event is PointerDownEvent &&
        event.buttons & kSecondaryMouseButton != 0) {
      _closeCanvasMenus();
      _canvasFocus.requestFocus();
      _viewMotion.stop();
      _menuPanPointer = event.pointer;
      _menuPanDown = event.position;
      _menuPanStarted = false;
    } else if (event.pointer == _menuPanPointer) {
      if (event is PointerMoveEvent && _menuPanDown != null) {
        final fromDown = event.position - _menuPanDown!;
        if (!_menuPanStarted && fromDown.distance <= kTouchSlop) return;
        final delta = _menuPanStarted ? event.delta : fromDown;
        _menuPanStarted = true;
        _transform.value = _transform.value.clone()
          ..setEntry(0, 3, _transform.value.entry(0, 3) + delta.dx)
          ..setEntry(1, 3, _transform.value.entry(1, 3) + delta.dy);
      } else if (event is PointerUpEvent || event is PointerCancelEvent) {
        _menuPanPointer = null;
        _menuPanDown = null;
        _menuPanStarted = false;
      }
    }
  }

  void _clearSelection(AiWorkspaceProvider workspaces) {
    _canvasFocus.requestFocus();
    _lastTapId = null;
    _closeCanvasMenus();
    setState(() {
      _selectedIds.clear();
      _selectedEdges.clear();
    });
    workspaces.select(null);
  }

  void _nodePointerUp(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
    PointerUpEvent event,
  ) {
    if (_extendSelection ||
        HardwareKeyboard.instance.isLogicalKeyPressed(
          LogicalKeyboardKey.space,
        )) {
      _lastTapId = null;
      return;
    }
    if (!_nodePrimaryDown ||
        _nodePointerDown == null ||
        (event.position - _nodePointerDown!).distance > 8) {
      return;
    }
    if (!_extendSelection &&
        _lastTapId == session.id &&
        _lastTapTime != null &&
        event.timeStamp - _lastTapTime! < const Duration(milliseconds: 300) &&
        _lastTapPosition != null &&
        (event.position - _lastTapPosition!).distance < 18) {
      _lastTapId = null;
      _open(workspaces, session);
    } else {
      _lastTapId = session.id;
      _lastTapTime = event.timeStamp;
      _lastTapPosition = event.position;
    }
  }

  void _startNodeDrag(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) {
    _lastTapId = null;
    if (_canvasPanPointer != null) return;
    _canvasFocus.requestFocus();
    _viewMotion.stop();
    if (!_selectedIds.contains(session.id)) {
      setState(() {
        _selectedIds
          ..clear()
          ..add(session.id);
        _selectedEdges.clear();
      });
      workspaces.select(session.id);
    }
    _dragStarts = {
      for (final id in _selectedIds)
        if (_positions[id] != null) id: _positions[id]!,
    };
    _dragDelta = Offset.zero;
    _dragEdit = _captureEdit(workspaces);
  }

  void _dragNodes(DragUpdateDetails details) {
    if (_dragStarts.isEmpty) return;
    _dragDelta += details.delta;
    setState(() {
      for (final entry in _dragStarts.entries) {
        _movedNodes[entry.key] = entry.value + _dragDelta;
      }
      final next = {
        for (final entry in _positions.entries)
          entry.key: _movedNodes[entry.key] ?? entry.value,
      };
      final left = next.values.map((offset) => offset.dx).reduce(math.min);
      final top = next.values.map((offset) => offset.dy).reduce(math.min);
      // Rebase before cards reach the finite render box. Whole grid cells keep
      // the background stable while the inverse view translation preserves the
      // pointer/card position. This is coordinate bookkeeping, not a drag limit.
      final shift = Offset(
        left < 24 ? ((240 - left) / 24).ceil() * 24.0 : 0,
        top < 24 ? ((240 - top) / 24).ceil() * 24.0 : 0,
      );
      if (shift != Offset.zero) {
        _movedNodes.addAll({
          for (final entry in next.entries) entry.key: entry.value + shift,
        });
        _dragStarts = {
          for (final entry in _dragStarts.entries)
            entry.key: entry.value + shift,
        };
        _positions = {
          for (final entry in next.entries) entry.key: entry.value + shift,
        };
        _transform.value = _transform.value.clone()
          ..translateByDouble(-shift.dx, -shift.dy, 0, 1);
      }
    });
  }

  void _autoLayout(List<AiAgentWorkspace> sessions) {
    final workspaces = context.read<AiWorkspaceProvider>();
    _edit(workspaces, () {
      _viewMotion.stop();
      setState(() {
        _movedNodes.clear();
        _positions = _layout(sessions);
      });
      _fit(animate: true);
    });
  }

  TaskTopologyConnection? _route(AiTaskConnection connection) =>
      _connectionRoutes[connection.id];

  void _updateConnectionRoutes(AiWorkspaceProvider workspaces) {
    final nodes = {
      for (final entry in _positions.entries)
        entry.key: entry.value & _size(entry.key),
    };
    final connections = workspaces.connections;
    final edges = [
      for (final edge in connections) (edge.id, edge.fromId, edge.toId),
    ];
    if (mapEquals(nodes, _routedNodes) && listEquals(edges, _routedEdges)) {
      return;
    }
    _routedNodes = nodes;
    _routedEdges = edges;
    _connectionRoutes = buildTaskTopologyRoutes(
      nodes: nodes,
      connections: connections,
    );
  }

  String? _edgeAt(AiWorkspaceProvider workspaces, Offset point) {
    final tolerance = 8 / _transform.value.entry(0, 0).abs().clamp(.25, 1.8);
    for (final connection in workspaces.connections.reversed) {
      if (_route(connection)?.hitTest(point, tolerance: tolerance) ?? false) {
        return connection.id;
      }
    }
    return null;
  }

  void _backgroundTap(AiWorkspaceProvider workspaces, Offset point) {
    final edge = _edgeAt(workspaces, point);
    if (edge == null) {
      if (!_extendSelection) _clearSelection(workspaces);
      return;
    }
    _canvasFocus.requestFocus();
    setState(() {
      if (_extendSelection) {
        if (!_selectedEdges.add(edge)) _selectedEdges.remove(edge);
      } else {
        _selectedIds.clear();
        _selectedEdges
          ..clear()
          ..add(edge);
      }
    });
    workspaces.select(_selectedIds.lastOrNull);
  }

  Future<void> _disconnectEdges(
    AiWorkspaceProvider workspaces,
    Iterable<String> ids,
  ) async {
    if (_disconnectingTasks) return;
    final targets = ids.toSet();
    if (!workspaces.connections.any((edge) => targets.contains(edge.id))) {
      return;
    }
    _disconnectingTasks = true;
    try {
      while (mounted) {
        final changes = workspaces.disconnectionRoleChanges(targets);
        if (changes.isEmpty) {
          _movedNodes.addAll(_positions);
          _edit(workspaces, () => workspaces.disconnectConnections(targets));
          setState(() => _selectedEdges.clear());
          return;
        }
        final snapshot = workspaces.connections
            .map((edge) => (edge.id, edge.fromId, edge.toId))
            .toList();
        final l10n = context.l10n;
        final confirmed = await showAppConfirmation(
          context: context,
          theme: context.read<ThemeProvider>().themeData,
          actionKey: 'topology-disconnect',
          title: l10n.aiTopologyDisconnectTitle,
          description: [
            l10n.aiTopologyDisconnectHelp,
            for (final entry in changes.entries)
              l10n.aiTopologyRoleChangeNotice(
                workspaces.find(entry.key)!.title,
                entry.value == AiWorkspaceKind.primary
                    ? l10n.aiTopologyPrimary
                    : l10n.aiTopologyPermanent,
              ),
          ].join('\n\n'),
          confirmLabel: l10n.aiTopologyDisconnect,
        );
        if (!confirmed || !mounted) return;
        final latest = workspaces.connections
            .map((edge) => (edge.id, edge.fromId, edge.toId))
            .toList();
        if (!listEquals(snapshot, latest) ||
            !mapEquals(changes, workspaces.disconnectionRoleChanges(targets))) {
          continue;
        }
        _movedNodes.addAll(_positions);
        _edit(workspaces, () => workspaces.disconnectConnections(targets));
        setState(() => _selectedEdges.clear());
        return;
      }
    } catch (_) {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          context.l10n.aiTopologyInvalidConnection,
        );
      }
    } finally {
      _disconnectingTasks = false;
    }
  }

  void _disconnectNodes(AiWorkspaceProvider workspaces, Set<String> ids) {
    _disconnectEdges(
      workspaces,
      workspaces.connections
          .where(
            (connection) =>
                ids.contains(connection.fromId) ||
                ids.contains(connection.toId),
          )
          .map((connection) => connection.id)
          .toList(),
    );
  }

  KeyEventResult _canvasKey(AiWorkspaceProvider workspaces, KeyEvent event) {
    final shortcut =
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        {
          LogicalKeyboardKey.keyA,
          LogicalKeyboardKey.keyC,
          LogicalKeyboardKey.keyV,
          LogicalKeyboardKey.keyZ,
          LogicalKeyboardKey.keyY,
        }.contains(event.logicalKey);
    if (_openId == null &&
        event is KeyDownEvent &&
        (shortcut ||
            event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      _closeCanvasMenus();
    }
    if (_openId != null || !_canvasFocus.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if ((HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
      setState(() {
        _selectedEdges
          ..clear()
          ..addAll(workspaces.connections.map((connection) => connection.id));
        _selectedIds
          ..clear()
          ..addAll(workspaces.sessions.map((item) => item.id));
      });
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyZ ||
          event.logicalKey == LogicalKeyboardKey.keyY) {
        if (event is KeyDownEvent) {
          _historyStep(
            workspaces,
            redo:
                event.logicalKey == LogicalKeyboardKey.keyY ||
                HardwareKeyboard.instance.isShiftPressed,
          );
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        if (event is KeyDownEvent) _copySelectedCards(workspaces);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        if (event is KeyDownEvent) _pasteSelectedCards(workspaces);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_selectedIds.isNotEmpty) {
        _delete(
          workspaces,
          targets: Set.of(_selectedIds),
          edgeTargets: Set.of(_selectedEdges),
        );
      } else if (_selectedEdges.isNotEmpty) {
        _disconnectEdges(workspaces, Set.of(_selectedEdges));
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clearSelection(workspaces);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _beginBox(Offset point) {
    _viewMotion.stop();
    _canvasFocus.requestFocus();
    _boxBase = _extendSelection ? Set.of(_selectedIds) : {};
    _boxEdgeBase = _extendSelection ? Set.of(_selectedEdges) : {};
    _boxDragging = false;
    _selectionRect.value = null;
    setState(() {
      _boxStart = point;
      _hoveredNode = null;
      _boxRect = null;
    });
  }

  void _updateBox(Offset point) {
    if (_boxStart == null) return;
    final distance =
        (point - _boxStart!).distance * _transform.value.entry(0, 0).abs();
    if (!_boxDragging && distance <= 4) return;
    _boxDragging = true;
    _boxRect = Rect.fromPoints(_boxStart!, point);
    _selectionRect.value = _boxRect;
  }

  void _endBox(AiWorkspaceProvider workspaces, {bool cancel = false}) {
    final start = _boxStart;
    final rect = _boxRect;
    final dragged = _boxDragging && rect != null;
    setState(() {
      if (!cancel && dragged) {
        _selectedIds
          ..clear()
          ..addAll(_boxBase)
          ..addAll(
            _positions.entries
                .where(
                  (entry) => (entry.value & _size(entry.key)).overlaps(rect),
                )
                .map((entry) => entry.key),
          );
      }
      if (!cancel && dragged) {
        _selectedEdges
          ..clear()
          ..addAll(_boxEdgeBase)
          ..addAll(
            workspaces.connections
                .where(
                  (connection) =>
                      _route(connection)?.intersectsRect(rect) ?? false,
                )
                .map((connection) => connection.id),
          );
      }
      _boxStart = null;
      _boxDragging = false;
      _boxRect = null;
      _boxBase = {};
      _boxEdgeBase = {};
    });
    _selectionRect.value = null;
    if (!cancel && dragged) {
      workspaces.select(_selectedIds.lastOrNull);
    } else if (!cancel && start != null) {
      // A blank click is finalized by the same pointer path as marquee selection.
      // It must not depend on a tap recognizer surviving the box overlay rebuild.
      _backgroundTap(workspaces, start);
    }
  }

  Offset _scenePoint(Offset global) =>
      (_sceneKey.currentContext!.findRenderObject()! as RenderBox)
          .globalToLocal(global);

  void _finishConnection(AiWorkspaceProvider workspaces) {
    final source = _connectingSource;
    final end = _connectingEnd;
    setState(() {
      _connectingSource = null;
      _connectingStart = null;
      _connectingEnd = null;
      _connectionPointer.value = null;
    });
    if (source == null || end == null) return;
    final target = workspaces.sessions.reversed
        .where(
          (item) => ((_positions[item.id]! & _size(item.id))
              .inflate(18)
              .contains(end)),
        )
        .firstOrNull;
    if (target == null) return;
    _connectTasks(workspaces, source, target.id);
  }

  Future<void> _connectTasks(
    AiWorkspaceProvider workspaces,
    String fromId,
    String toId,
  ) async {
    if (_connectingTasks) return;
    _connectingTasks = true;
    try {
      while (mounted) {
        final plan = workspaces.connectionMergeFor(fromId, toId);
        if (plan != null) {
          final task = workspaces.find(plan.rootId)!;
          final parent = workspaces.find(plan.parentId)!;
          final taskLabel = '${task.title} (${task.id})';
          final parentLabel = '${parent.title} (${parent.id})';
          final confirmed = await showAppConfirmation(
            context: context,
            theme: context.read<ThemeProvider>().themeData,
            actionKey: 'topology-merge',
            title: context.l10n.aiTopologyMergeTitle,
            description: plan.changesRole
                ? context.l10n.aiTopologyMergeRootHelp(taskLabel, parentLabel)
                : context.l10n.aiTopologyMergeChildHelp(taskLabel, parentLabel),
            confirmLabel: context.l10n.aiTopologyMergeConfirm,
          );
          if (!confirmed || !mounted) return;
          final latest = workspaces.connectionMergeFor(fromId, toId);
          if (latest == null || !plan.matches(latest)) continue;
        }
        _movedNodes.addAll(_positions);
        _edit(
          workspaces,
          () => workspaces.connectTasks(fromId, toId, confirmedMerge: plan),
        );
        return;
      }
    } catch (_) {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          context.l10n.aiTopologyInvalidConnection,
        );
      }
    } finally {
      _connectingTasks = false;
    }
  }

  Widget _port(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
    AppTheme theme,
    String side,
  ) {
    final visible =
        _hoveredNode == session.id ||
        _selectedIds.contains(session.id) ||
        _connectingSource != null;
    final size = _size(session.id);
    final at = switch (side) {
      'in' => Offset(1, size.height / 2),
      'out' => Offset(size.width - 1, size.height / 2),
      'top' => Offset(size.width / 2, 1),
      _ => Offset(size.width / 2, size.height - 1),
    };
    return Positioned(
      left: at.dx - 12,
      top: at.dy - 12,
      width: 24,
      height: 24,
      child: AppTooltip(
        message: context.l10n.aiTopologyConnectHint,
        child: GestureDetector(
          key: ValueKey('topology-port-$side-${session.id}'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (_) {
            _viewMotion.stop();
            _canvasFocus.requestFocus();
            setState(() {
              _connectingSource = session.id;
              _connectingStart = _positions[session.id]! + at;
              _connectingEnd = _connectingStart;
              _connectionPointer.value = _connectingEnd;
            });
          },
          onPanUpdate: (details) {
            _connectingEnd = _scenePoint(details.globalPosition);
            _connectionPointer.value = _connectingEnd;
          },
          onPanEnd: (_) => _finishConnection(workspaces),
          onPanCancel: () => setState(() {
            _connectingSource = null;
            _connectingStart = null;
            _connectingEnd = null;
            _connectionPointer.value = null;
          }),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: visible ? 1 : .16,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.primary,
                  border: Border.all(color: theme.basePrimary, width: 1.5),
                ),
                child: const SizedBox(width: 9, height: 9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  AiAgentWorkspace? _parentFor(AiWorkspaceProvider workspaces) {
    var selected = workspaces.selected;
    final seen = <String>{};
    while (selected != null && seen.add(selected.id)) {
      if (!selected.closed) {
        return selected;
      }
      selected = workspaces.find(selected.parentId);
    }
    return workspaces.sessions
        .where((item) => item.kind == AiWorkspaceKind.primary && !item.closed)
        .firstOrNull;
  }

  Future<void> _create(
    AiWorkspaceProvider workspaces, {
    AiAgentWorkspace? parent,
  }) async {
    await workspaces.main.initialized;
    if (!mounted) return;
    if (!workspaces.main.services.any(
      (service) =>
          workspaces.main.hasServiceKey(service.id) &&
          service.models.isNotEmpty,
    )) {
      context.read<AppNavigationProvider>().openAiSettings();
      return;
    }
    final id = await _editAsync(
      workspaces,
      () => showDialog<String>(
        context: context,
        builder: (_) =>
            _TopologyCreateDialog(workspaces: workspaces, parent: parent),
      ),
    );
    if (!mounted || id == null) return;
    final session = workspaces.find(id);
    if (session != null) _open(workspaces, session);
  }

  Future<void> _delete(
    AiWorkspaceProvider workspaces, {
    AiAgentWorkspace? target,
    Set<String>? targets,
    Set<String>? edgeTargets,
  }) async {
    final ids =
        targets ??
        (target == null
            ? Set<String>.of(_selectedIds)
            : _selectedIds.contains(target.id)
            ? Set<String>.of(_selectedIds)
            : {target.id});
    if (ids.isEmpty) return;
    final edges = edgeTargets ?? Set<String>.of(_selectedEdges);
    final selected = workspaces.find(ids.first);
    if (selected == null) return;
    final l10n = context.l10n;
    final replacements = workspaces.rootReplacementsForDeletion(ids);
    final roleChanges = workspaces.disconnectionRoleChanges(
      edges,
      deletingTaskIds: ids,
    );
    final description = ids.length > 1
        ? l10n.aiTopologyDeleteSelectedHelp
        : replacements.isNotEmpty
        ? l10n.aiTopologyDeleteRootHelp
        : l10n.aiTopologyDeleteHelp;
    final confirmed = await showAppConfirmation(
      context: context,
      theme: context.read<ThemeProvider>().themeData,
      actionKey: 'topology-delete',
      title: ids.length > 1
          ? l10n.aiTopologyDeleteSelectedTitle
          : l10n.aiTopologyDeleteTitle,
      description: [
        description,
        if (edges.isNotEmpty) l10n.aiTopologyDisconnectHelp,
        for (final replacement in replacements.values)
          l10n.aiTopologyRootPromotionNotice(replacement.title),
        for (final entry in roleChanges.entries)
          if (!replacements.values.any((task) => task.id == entry.key))
            l10n.aiTopologyRoleChangeNotice(
              workspaces.find(entry.key)!.title,
              entry.value == AiWorkspaceKind.primary
                  ? l10n.aiTopologyPrimary
                  : l10n.aiTopologyPermanent,
            ),
      ].join('\n\n'),
      confirmLabel: l10n.aiTopologyDelete,
    );
    if (confirmed && mounted) {
      final latest = workspaces.rootReplacementsForDeletion(ids);
      if (!mapEquals(
            replacements.map((id, task) => MapEntry(id, task.id)),
            latest.map((id, task) => MapEntry(id, task.id)),
          ) ||
          !mapEquals(
            roleChanges,
            workspaces.disconnectionRoleChanges(edges, deletingTaskIds: ids),
          )) {
        await _delete(workspaces, targets: ids, edgeTargets: edges);
        return;
      }
      _edit(workspaces, () {
        workspaces.removeMany(ids);
        workspaces.disconnectConnections(edges);
      });
      setState(() {
        _selectedIds.removeAll(ids);
        _selectedEdges.clear();
      });
    }
  }

  Future<void> _makeRoot(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) async {
    final confirmed = await showAppConfirmation(
      context: context,
      theme: context.read<ThemeProvider>().themeData,
      actionKey: 'topology-make-root',
      title: context.l10n.aiTopologyMakeRootTitle,
      description: context.l10n.aiTopologyMakeRootHelp(session.title),
      confirmLabel: context.l10n.aiTopologyMakeRoot,
    );
    if (!confirmed || !mounted || workspaces.find(session.id) != session) {
      return;
    }
    _movedNodes.addAll(_positions);
    _edit(workspaces, () => workspaces.promoteToRoot(session.id));
  }

  List<AiAgentWorkspace> _parentCandidates(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) => workspaces.sessions.where((candidate) {
    if (candidate.closed) {
      return false;
    }
    AiAgentWorkspace? ancestor = candidate;
    final seen = <String>{};
    while (ancestor != null && seen.add(ancestor.id)) {
      if (ancestor.id == session.id) return false;
      ancestor = workspaces.find(ancestor.parentId);
    }
    return true;
  }).toList();

  Future<void> _makeChild(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) async {
    final candidates = _parentCandidates(workspaces, session);
    if (candidates.isEmpty) return;
    var parentId = candidates.first.id;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = context.watch<ThemeProvider>().themeData;
          final l10n = context.l10n;
          return AppDialog(
            theme: theme,
            title: l10n.aiTopologyChooseParent,
            titleFontSize: 18,
            titleFontWeight: FontWeight.w500,
            constraints: const BoxConstraints(maxWidth: 480),
            content: SizedBox(
              width: 432,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.aiTopologyParentLabel,
                    style: AppDialogStyle.fieldTitleStyle(theme),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.aiTopologyChooseParentHelp,
                    style: AppDialogStyle.descriptionStyle(theme),
                  ),
                  const SizedBox(height: 8),
                  SettingSelect<String>(
                    key: const ValueKey('topology-parent-select'),
                    theme: theme,
                    surfaceColor: AppDialogStyle.backgroundColor(theme),
                    value: parentId,
                    items: [
                      for (final candidate in candidates)
                        DropdownMenuItem(
                          value: candidate.id,
                          child: Text(
                            candidate.title,
                            key: ValueKey(
                              'topology-parent-option-${candidate.id}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => parentId = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              AppActionButton.dialog(
                theme: theme,
                label: l10n.settingsCancel,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              AppActionButton.dialog(
                key: const ValueKey('topology-parent-confirm'),
                theme: theme,
                label: l10n.aiTopologyMakeChild,
                primary: true,
                onPressed: () => Navigator.pop(dialogContext, parentId),
              ),
            ],
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    try {
      _movedNodes.addAll(_positions);
      _edit(workspaces, () => workspaces.reparent(session.id, selected));
    } catch (_) {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          context.l10n.aiTopologyInvalidConnection,
        );
      }
    }
  }

  Future<void> _rename(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _TopologyRenameDialog(title: session.title),
    );
    if (title == null || !mounted) return;
    _edit(workspaces, () => workspaces.rename(session.id, title));
  }

  String _copyTitle(String original) =>
      context.read<AiWorkspaceProvider>().nextCopyTitle(original);

  Future<void> _copySelectedCards(AiWorkspaceProvider workspaces) async {
    final cards = workspaces.copyCards(_selectedIds);
    if (cards.isEmpty) return;
    final token =
        'lilygobox-task-cards:${DateTime.now().microsecondsSinceEpoch}';
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    _copiedCards = cards;
    _copiedPositions = {
      for (final card in cards)
        card.sourceId: _positions[card.sourceId] ?? Offset.zero,
    };
    _cardClipboardToken = token;
    _pasteCount = 0;
  }

  Future<void> _pasteSelectedCards(AiWorkspaceProvider workspaces) async {
    if (_pastingCards || _copiedCards.isEmpty) return;
    _pastingCards = true;
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted ||
          !_canvasFocus.hasPrimaryFocus ||
          _openId != null ||
          clipboard?.text != _cardClipboardToken) {
        return;
      }
      final cards = _copiedCards;
      final positions = _copiedPositions;
      final before = _captureEdit(workspaces);
      late final List<AiAgentWorkspace> copies;
      try {
        copies = await workspaces.pasteCards(cards, titleForCopy: _copyTitle);
        if (!mounted) {
          _releaseFrame(before);
          return;
        }
        _pasteCount++;
        _movedNodes.addAll(_positions);
        setState(() {
          for (var index = 0; index < copies.length; index++) {
            _movedNodes[copies[index].id] =
                positions[cards[index].sourceId]! +
                Offset(40.0 * _pasteCount, 40.0 * _pasteCount);
          }
          _selectedIds
            ..clear()
            ..addAll(copies.map((copy) => copy.id));
          _selectedEdges.clear();
          _lastTapId = null;
        });
        workspaces.select(copies.lastOrNull?.id);
        _finishEdit(workspaces, before);
      } catch (_) {
        _releaseFrame(before);
        rethrow;
      }
    } catch (error) {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          aiErrorText(context.l10n, error),
        );
      }
    } finally {
      _pastingCards = false;
    }
  }

  Future<void> _duplicate(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) async {
    _movedNodes.addAll(_positions);
    final position = _positions[session.id] ?? Offset.zero;
    final title = _copyTitle(session.title);
    try {
      final before = _captureEdit(workspaces);
      try {
        final copy = await workspaces.duplicate(session.id, title: title);
        if (!mounted) {
          _releaseFrame(before);
          return;
        }
        _canvasFocus.requestFocus();
        _lastTapId = null;
        setState(() {
          _movedNodes[copy.id] = position + const Offset(40, 40);
          _selectedIds
            ..clear()
            ..add(copy.id);
          _selectedEdges.clear();
        });
        workspaces.select(copy.id);
        _finishEdit(workspaces, before);
      } catch (_) {
        _releaseFrame(before);
        rethrow;
      }
    } catch (error) {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          aiErrorText(context.l10n, error),
        );
      }
    }
  }

  Widget _nodeContextMenu(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
    AppTheme theme,
    Widget child,
  ) {
    final l10n = context.l10n;
    final targetIds = _selectedIds.contains(session.id)
        ? _selectedIds
        : {session.id};
    final hasStop = targetIds.any((id) => workspaces.find(id)?.busy ?? false);
    final hasDisconnect = workspaces.connections.any(
      (connection) =>
          targetIds.contains(connection.fromId) ||
          targetIds.contains(connection.toId),
    );
    final connectTarget = targetIds.length == 2
        ? targetIds.where((id) => id != session.id).firstOrNull
        : null;
    final canConnect =
        connectTarget != null &&
        !workspaces.isConnected(session.id, connectTarget);
    final hasRole =
        session.kind != AiWorkspaceKind.primary ||
        _parentCandidates(workspaces, session).isNotEmpty;
    void closeMenu() => _nodeMenus[session.id]?.close();
    return RightClickMenuBuilder.buildMenuAnchor(
      context: context,
      onMenuPointerEvent: _menuPointerEvent,
      controller: _nodeMenus.putIfAbsent(
        session.id,
        RightClickMenuController.new,
      ),
      theme: theme,
      onSecondaryTap: () {
        _viewMotion.stop();
        _selectNode(workspaces, session, contextMenu: true);
      },
      menuItems: [
        RightClickMenuItem(
          key: const ValueKey('topology-context-open'),
          label: l10n.aiTopologyOpen,
          icon: Symbols.chat_rounded,
          onTap: () {
            closeMenu();
            _open(workspaces, session);
          },
        ),
        RightClickMenuItem(
          key: const ValueKey('topology-context-duplicate'),
          label: l10n.aiTopologyDuplicate,
          icon: Symbols.content_copy_rounded,
          onTap: () {
            closeMenu();
            _duplicate(workspaces, session);
          },
        ),
        RightClickMenuItem(
          key: const ValueKey('topology-context-copy-id'),
          label: l10n.aiTopologyCopyId,
          icon: Symbols.content_copy_rounded,
          onTap: () async {
            closeMenu();
            await Clipboard.setData(ClipboardData(text: session.id));
          },
        ),
        RightClickMenuItem(
          key: const ValueKey('topology-context-rename'),
          label: l10n.aiTopologyRename,
          icon: Symbols.edit_rounded,
          onTap: () {
            closeMenu();
            _rename(workspaces, session);
          },
        ),
        RightClickMenuItem(
          key: const ValueKey('topology-context-bring-front'),
          label: l10n.aiTopologyBringToFront,
          icon: Symbols.flip_to_front_rounded,
          onTap: () {
            closeMenu();
            _edit(
              workspaces,
              () => setState(() {
                _frontOrder.remove(session.id);
                _frontOrder.add(session.id);
              }),
            );
          },
        ),
        if (canConnect)
          RightClickMenuItem(
            key: const ValueKey('topology-context-connect'),
            label: l10n.aiTopologyConnectSelected,
            icon: Symbols.add_link_rounded,
            onTap: () {
              closeMenu();
              _connectTasks(workspaces, session.id, connectTarget);
            },
          ),
        RightClickMenuItem(
          key: const ValueKey('topology-context-create'),
          showDivider: !hasRole && !hasStop && !hasDisconnect,
          label: l10n.aiTopologyCreateChild,
          icon: Symbols.account_tree_rounded,
          onTap: () {
            closeMenu();
            _create(workspaces, parent: session);
          },
        ),
        if (session.kind != AiWorkspaceKind.primary)
          RightClickMenuItem(
            key: const ValueKey('topology-context-make-root'),
            showDivider: !hasStop && !hasDisconnect,
            label: l10n.aiTopologyMakeRoot,
            icon: Symbols.hub_rounded,
            onTap: () {
              closeMenu();
              _makeRoot(workspaces, session);
            },
          )
        else if (_parentCandidates(workspaces, session).isNotEmpty)
          RightClickMenuItem(
            key: const ValueKey('topology-context-make-child'),
            showDivider: !hasStop && !hasDisconnect,
            label: l10n.aiTopologyMakeChild,
            icon: Symbols.subdirectory_arrow_right_rounded,
            onTap: () {
              closeMenu();
              _makeChild(workspaces, session);
            },
          ),
        if (hasStop)
          RightClickMenuItem(
            key: const ValueKey('topology-context-stop'),
            showDivider: !hasDisconnect,
            label: _selectedIds.length > 1
                ? l10n.aiTopologyStopSelected
                : l10n.aiWorkspaceStopAction,
            icon: Symbols.stop_circle_rounded,
            onTap: () {
              closeMenu();
              for (final id in _selectedIds.toList()) {
                if (workspaces.find(id)?.busy ?? false) workspaces.stop(id);
              }
            },
          ),
        if (hasDisconnect)
          RightClickMenuItem(
            key: const ValueKey('topology-context-disconnect'),
            showDivider: true,
            label: _selectedIds.length > 1
                ? l10n.aiTopologyDisconnectSelected
                : l10n.aiTopologyDisconnect,
            icon: Symbols.link_off_rounded,
            onTap: () {
              closeMenu();
              _disconnectNodes(workspaces, Set.of(_selectedIds));
            },
          ),
        RightClickMenuItem(
          key: const ValueKey('topology-context-delete'),
          label: _selectedIds.length > 1
              ? l10n.aiTopologyDeleteSelected
              : l10n.aiTopologyDelete,
          icon: Symbols.delete_outline_rounded,
          onTap: () {
            closeMenu();
            _delete(workspaces, target: session);
          },
        ),
      ],
      child: child,
    );
  }

  Widget _backgroundControl(AppTheme theme, AiWorkspaceProvider workspaces) {
    final l10n = context.l10n;
    String label(AiTaskCanvasStyle style) => switch (style) {
      AiTaskCanvasStyle.dots => l10n.aiTopologyCanvasDots,
      AiTaskCanvasStyle.grid => l10n.aiTopologyCanvasGrid,
      AiTaskCanvasStyle.plain => l10n.aiTopologyCanvasPlain,
    };
    IconData icon(AiTaskCanvasStyle style) => switch (style) {
      AiTaskCanvasStyle.dots => Symbols.grain_rounded,
      AiTaskCanvasStyle.grid => Symbols.grid_on_rounded,
      AiTaskCanvasStyle.plain => Symbols.crop_square_rounded,
    };
    return RightClickMenuBuilder.buildMenuAnchor(
      context: context,
      onMenuPointerEvent: _menuPointerEvent,
      controller: _backgroundMenu,
      theme: theme,
      openAbove: true,
      onSecondaryTap: () {},
      menuItems: [
        for (final style in AiTaskCanvasStyle.values)
          RightClickMenuItem(
            key: ValueKey('topology-canvas-style-${style.name}'),
            label: label(style),
            icon: icon(style),
            isSelected: workspaces.canvasStyle == style,
            onTap: () {
              _backgroundMenu.close();
              workspaces.setCanvasStyle(style);
            },
          ),
      ],
      child: KeyedSubtree(
        key: const ValueKey('topology-canvas-background'),
        child: _viewButton(
          theme,
          l10n.aiTopologyCanvasBackground,
          icon(workspaces.canvasStyle),
          () {
            _backgroundMenu.close();
            final styles = AiTaskCanvasStyle.values;
            workspaces.setCanvasStyle(
              styles[(workspaces.canvasStyle.index + 1) % styles.length],
            );
          },
        ),
      ),
    );
  }

  Map<String, Offset> _layout(List<AiAgentWorkspace> sessions) {
    final result = layoutTaskTopology(
      sessions: sessions,
      nodeSizes: {
        for (final session in sessions) session.id: _size(session.id),
      },
      connections: context.read<AiWorkspaceProvider>().connections,
    );
    return {
      for (final item in result.entries)
        item.key: _movedNodes[item.key] ?? item.value,
    };
  }

  void _fit({bool animate = false}) {
    if (_viewport.isEmpty) return;
    _wheelZoomTargetScale = null;
    _wheelPanTarget = null;
    _viewMotion.stop();
    Rect bounds;
    if (_positions.isEmpty) {
      bounds = Rect.fromCenter(
        center: const Offset(530, 350),
        width: _nodeSize.width,
        height: _nodeSize.height,
      );
    } else {
      bounds = _positions.entries
          .map((entry) => entry.value & _size(entry.key))
          .reduce((a, b) => a.expandToInclude(b));
    }
    final scale = math
        .min(
          _viewport.width / (bounds.width + 140),
          _viewport.height / (bounds.height + 140),
        )
        .clamp(.3, 1.0);
    final target =
        Matrix4.translationValues(
          _viewport.width / 2 - bounds.center.dx * scale,
          _viewport.height / 2 - bounds.center.dy * scale,
          0,
        ) *
        Matrix4.diagonal3Values(scale, scale, 1);
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _transform.value = target;
      return;
    }
    _viewFrames = _viewMotion
        .drive(CurveTween(curve: Curves.easeInOut))
        .drive(Matrix4Tween(begin: _transform.value.clone(), end: target));
    _viewMotion.forward(from: 0);
  }

  void _zoom(double factor) => _zoomAt(
    factor,
    Offset(_viewport.width / 2, _viewport.height / 2),
    animate: true,
  );

  void _zoomAt(
    double factor,
    Offset center, {
    bool animate = false,
    bool accumulateWheel = false,
  }) {
    if (_viewport.isEmpty || factor == 1) return;
    final currentScale = _transform.value.entry(0, 0).abs();
    final direction = factor.compareTo(1);
    final baseScale =
        accumulateWheel &&
            _viewMotion.isAnimating &&
            _wheelZoomDirection == direction
        ? _wheelZoomTargetScale ?? currentScale
        : currentScale;
    final scale = (baseScale * factor).clamp(.25, 1.8);
    _viewMotion.stop();
    _wheelPanTarget = null;
    _wheelZoomTargetScale = accumulateWheel ? scale : null;
    _wheelZoomDirection = direction;
    final scene = _transform.toScene(center);
    final target =
        Matrix4.translationValues(
          center.dx - scene.dx * scale,
          center.dy - scene.dy * scale,
          0,
        ) *
        Matrix4.diagonal3Values(scale, scale, 1);
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      _viewFrames = _viewMotion
          .drive(
            CurveTween(
              curve: accumulateWheel ? Curves.easeOut : Curves.easeInOut,
            ),
          )
          .drive(Matrix4Tween(begin: _transform.value.clone(), end: target));
      _viewMotion.forward(from: 0);
    } else {
      _transform.value = target;
    }
    setState(() {});
  }

  void _panByWheel(Offset delta) {
    if (_viewport.isEmpty || delta == Offset.zero) return;
    final current = Offset(
      _transform.value.entry(0, 3),
      _transform.value.entry(1, 3),
    );
    final sameDirection =
        delta.dx * _wheelPanDirection.dx + delta.dy * _wheelPanDirection.dy > 0;
    final base = _viewMotion.isAnimating && sameDirection
        ? _wheelPanTarget ?? current
        : current;
    final destination = base + delta;
    _viewMotion.stop();
    _wheelZoomTargetScale = null;
    _wheelPanTarget = destination;
    _wheelPanDirection = delta;
    final target = _transform.value.clone()
      ..setEntry(0, 3, destination.dx)
      ..setEntry(1, 3, destination.dy);
    if (MediaQuery.disableAnimationsOf(context)) {
      _transform.value = target;
    } else {
      _viewFrames = _viewMotion
          .drive(CurveTween(curve: Curves.easeOut))
          .drive(Matrix4Tween(begin: _transform.value.clone(), end: target));
      _viewMotion.forward(from: 0);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final workspaces = context.watch<AiWorkspaceProvider>();
    final homeRevision = context
        .watch<AppNavigationProvider>()
        .workflowHomeRevision;
    if (_lastWorkflowHomeRevision != homeRevision) {
      _lastWorkflowHomeRevision = homeRevision;
      _openId = null;
      _conversationHistory.clear();
      workspaces.activeConversationId = null;
    }
    if (!identical(_navigationWorkspace, workspaces)) {
      _navigationWorkspace = workspaces;
      _lastNavigationRevision = workspaces.navigationRequest?.revision ?? 0;
    }
    final active =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    workspaces.activeConversationId = active ? _openId : null;
    final request = workspaces.navigationRequest;
    if (request != null && request.revision > _lastNavigationRevision) {
      _lastNavigationRevision = request.revision;
      if (active && _openId != null && request.sourceId == _openId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              TickerMode.of(context) &&
              _openId == request.sourceId) {
            _openLinkedTask(workspaces, request.targetId);
          }
        });
      }
    }
    final sessions = workspaces.sessions;
    _selectedIds.removeWhere((id) => workspaces.find(id) == null);
    final connectionIds = workspaces.connections
        .map((connection) => connection.id)
        .toSet();
    _selectedEdges.removeWhere((id) => !connectionIds.contains(id));
    final visibleSessions = sessions.toList();
    final sizes = {
      for (final session in visibleSessions) session.id: _measureNode(session),
    };
    if (_nodeSizes.entries.any(
      (entry) =>
          sizes.containsKey(entry.key) && sizes[entry.key] != entry.value,
    )) {
      // Renaming resizes cards in place; rearranging remains an explicit action.
      _movedNodes.addAll(_positions);
    }
    _nodeSizes = sizes;
    _positions = _layout(visibleSessions);
    _updateConnectionRoutes(workspaces);
    if (visibleSessions.length != _lastCount) {
      final firstTasks = _lastCount <= 0 && visibleSessions.isNotEmpty;
      _lastCount = visibleSessions.length;
      if (firstTasks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit();
        });
      }
    }
    if (_openId != null && workspaces.find(_openId) == null) _openId = null;
    return ColoredBox(
      color: theme.secondary,
      child: RetainedPageStack(
        activeKey: _openId ?? _graphKey,
        pages: {
          _graphKey: _graph(theme, workspaces),
          for (final session in sessions)
            session.id: ChangeNotifierProvider<AiAssistantProvider>.value(
              // 主智能体移除或节点提升会改变 IndexedStack 的索引，按会话身份保留草稿。
              key: GlobalObjectKey(session.assistant),
              value: session.assistant,
              child: TaskNavigationScope(
                openTask: (id) => _openLinkedTask(workspaces, id),
                child: _TopologyConversation(
                  key: ValueKey('topology-chat-${session.id}'),
                  session: session,
                  onBack: () => _backToConversation(workspaces),
                ),
              ),
            ),
        },
      ),
    );
  }

  Widget _sceneBackground(
    AppTheme theme,
    AiWorkspaceProvider workspaces,
    List<AiAgentWorkspace> sessions,
  ) => ListenableBuilder(
    listenable: Listenable.merge([_transform, workspaces.transfers]),
    builder: (context, _) => CustomPaint(
      painter: _TopologyPainter(
        positions: _positions,
        nodeSizes: _nodeSizes,
        sessions: sessions,
        connections: workspaces.connections,
        routes: _connectionRoutes,
        canvasStyle: workspaces.canvasStyle,
        scale: _transform.value.entry(0, 0).abs(),
        backgroundBounds: Rect.fromPoints(
          _transform.toScene(Offset.zero),
          _transform.toScene(Offset(_viewport.width, _viewport.height)),
        ).inflate(24),
        gridColor: theme.textColorTertiary.withValues(alpha: .28),
        lineColor: theme.textColorTertiary.withValues(alpha: .48),
        accentColor: theme.basePrimary,
        selectedEdges: Set.of(_selectedEdges),
        activeEdges: {
          for (final edge in workspaces.connections)
            if (workspaces.transfers.value.any(
              (item) =>
                  (item.fromId == edge.fromId && item.toId == edge.toId) ||
                  (item.fromId == edge.toId && item.toId == edge.fromId),
            ))
              edge.id,
        },
      ),
    ),
  );

  Widget _canvasInteractions(
    AppTheme theme,
    AiWorkspaceProvider workspaces,
    Widget child,
  ) {
    final l10n = context.l10n;
    final sessions = workspaces.sessions.toList();
    RightClickMenuItem action(
      String key,
      String label,
      IconData icon,
      VoidCallback callback, {
      bool divider = false,
    }) => RightClickMenuItem(
      key: ValueKey(key),
      label: label,
      icon: icon,
      showDivider: divider,
      onTap: () {
        _canvasMenu.close();
        callback();
      },
    );
    return RightClickMenuBuilder.buildMenuAnchor(
      context: context,
      onMenuPointerEvent: _menuPointerEvent,
      controller: _canvasMenu,
      theme: theme,
      onSecondaryTap: () {
        if (_rightEdge == null) {
          _clearSelection(workspaces);
        } else {
          _canvasFocus.requestFocus();
          for (final menu in _nodeMenus.values) {
            menu.close();
          }
          setState(() {
            if (!_selectedEdges.contains(_rightEdge)) {
              _selectedIds.clear();
              _selectedEdges
                ..clear()
                ..add(_rightEdge!);
            }
          });
          workspaces.select(null);
        }
      },
      menuItems: [
        if (_rightEdge != null)
          action(
            'topology-edge-disconnect',
            l10n.aiTopologyDisconnect,
            Symbols.link_off_rounded,
            () {
              if (_selectedEdges.isNotEmpty) {
                _disconnectEdges(workspaces, Set.of(_selectedEdges));
              }
            },
          )
        else ...[
          action(
            'topology-canvas-zoom-out',
            l10n.aiTopologyZoomOut,
            Symbols.remove_rounded,
            () => _zoom(1 / 1.2),
          ),
          action(
            'topology-canvas-zoom-in',
            l10n.aiTopologyZoomIn,
            Symbols.add_rounded,
            () => _zoom(1.2),
            divider: true,
          ),
          for (final style in AiTaskCanvasStyle.values)
            RightClickMenuItem(
              key: ValueKey('topology-canvas-background-${style.name}'),
              label: switch (style) {
                AiTaskCanvasStyle.dots => l10n.aiTopologyCanvasDots,
                AiTaskCanvasStyle.grid => l10n.aiTopologyCanvasGrid,
                AiTaskCanvasStyle.plain => l10n.aiTopologyCanvasPlain,
              },
              icon: switch (style) {
                AiTaskCanvasStyle.dots => Symbols.grain_rounded,
                AiTaskCanvasStyle.grid => Symbols.grid_on_rounded,
                AiTaskCanvasStyle.plain => Symbols.crop_square_rounded,
              },
              isSelected: workspaces.canvasStyle == style,
              showDivider: style == AiTaskCanvasStyle.values.last,
              onTap: () {
                _canvasMenu.close();
                workspaces.setCanvasStyle(style);
              },
            ),
          action(
            'topology-canvas-auto-layout',
            l10n.aiTopologyAutoLayout,
            Symbols.auto_awesome_mosaic_rounded,
            () => _autoLayout(sessions),
          ),
          action(
            'topology-canvas-reset',
            l10n.aiTopologyReset,
            Symbols.fit_screen_rounded,
            () {
              _fit(animate: true);
              setState(() {});
            },
          ),
        ],
      ],
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            GestureBinding.instance.pointerSignalResolver.register(event, (_) {
              final keyboard = HardwareKeyboard.instance;
              _closeCanvasMenus();
              if (keyboard.isControlPressed) {
                _zoomAt(
                  math.exp(-event.scrollDelta.dy / 200),
                  event.localPosition,
                  animate: true,
                  accumulateWheel: true,
                );
              } else {
                _panByWheel(
                  keyboard.isShiftPressed
                      ? Offset(-event.scrollDelta.dy - event.scrollDelta.dx, 0)
                      : -event.scrollDelta,
                );
              }
            });
          }
        },
        onPointerDown: (event) {
          _closeCanvasMenus();
          _canvasFocus.requestFocus();
          _viewMotion.stop();
          final pan =
              event.buttons & kMiddleMouseButton != 0 ||
              (event.buttons & kPrimaryMouseButton != 0 &&
                  HardwareKeyboard.instance.isLogicalKeyPressed(
                    LogicalKeyboardKey.space,
                  ));
          if (pan) {
            _canvasPanPointer = event.pointer;
            return;
          }
          final point = _transform.toScene(event.localPosition);
          final onNode = _positions.entries.any(
            (entry) => (entry.value & _size(entry.key)).contains(point),
          );
          if (event.buttons & kSecondaryMouseButton != 0) {
            _secondaryPointer = event.pointer;
            _secondaryDown = event.localPosition;
            setState(() {
              _rightEdge = onNode ? null : _edgeAt(workspaces, point);
            });
            if (onNode) {
              _canvasMenu.disable();
            } else {
              _canvasMenu.enable();
            }
          } else if (event.buttons & kPrimaryMouseButton != 0 && !onNode) {
            _boxPointer = event.pointer;
            _beginBox(point);
          }
        },
        onPointerMove: (event) {
          var delta = event.localDelta;
          if (_secondaryPointer == event.pointer &&
              _canvasPanPointer != event.pointer &&
              _secondaryDown != null) {
            final fromDown = event.localPosition - _secondaryDown!;
            if (fromDown.distance > kTouchSlop) {
              _closeCanvasMenus();
              _canvasPanPointer = event.pointer;
              delta = fromDown;
            }
          }
          if (_canvasPanPointer == event.pointer) {
            final matrix = _transform.value.clone();
            matrix.setEntry(0, 3, matrix.entry(0, 3) + delta.dx);
            matrix.setEntry(1, 3, matrix.entry(1, 3) + delta.dy);
            _transform.value = matrix;
          } else if (_boxPointer == event.pointer && _boxStart != null) {
            _updateBox(_transform.toScene(event.localPosition));
          }
        },
        onPointerUp: (event) {
          if (_secondaryPointer == event.pointer) {
            _secondaryPointer = null;
            _secondaryDown = null;
          }
          if (_canvasPanPointer == event.pointer) _canvasPanPointer = null;
          if (_boxPointer == event.pointer) {
            _boxPointer = null;
            _endBox(workspaces);
          }
        },
        onPointerCancel: (event) {
          if (_secondaryPointer == event.pointer) {
            _secondaryPointer = null;
            _secondaryDown = null;
          }
          if (_canvasPanPointer == event.pointer) _canvasPanPointer = null;
          if (_boxPointer == event.pointer) {
            _boxPointer = null;
            _endBox(workspaces, cancel: true);
          }
        },
        child: Listener(
          key: const ValueKey('topology-background'),
          behavior: HitTestBehavior.opaque,
          child: child,
        ),
      ),
    );
  }

  Widget _nodeView(
    AppTheme theme,
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) => _nodeContextMenu(
    workspaces,
    session,
    theme,
    MouseRegion(
      onEnter: (_) => setState(() => _hoveredNode = session.id),
      onExit: (_) {
        if (_hoveredNode == session.id) setState(() => _hoveredNode = null);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: (event) {
                _nodePointerDown = event.position;
                _nodePrimaryDown = event.buttons & kPrimaryMouseButton != 0;
              },
              onPointerUp: (event) =>
                  _nodePointerUp(workspaces, session, event),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTap: () {
                  if (!HardwareKeyboard.instance.isLogicalKeyPressed(
                    LogicalKeyboardKey.space,
                  )) {
                    _selectNode(workspaces, session);
                  }
                },
                onPanDown: (_) => _viewMotion.stop(),
                onPanStart: (_) => _startNodeDrag(workspaces, session),
                onPanUpdate: _dragNodes,
                onPanEnd: (_) {
                  final before = _dragEdit;
                  _dragEdit = null;
                  _dragStarts.clear();
                  if (before != null) _finishEdit(workspaces, before);
                },
                onPanCancel: () {
                  final before = _dragEdit;
                  _dragEdit = null;
                  _dragStarts.clear();
                  if (before != null) _finishEdit(workspaces, before);
                },
                child: _TaskNode(
                  session: session,
                  selected: _selectedIds.contains(session.id),
                  onOpen: () => _open(workspaces, session),
                  theme: theme,
                ),
              ),
            ),
          ),
          for (final side in ['in', 'out', 'top', 'bottom'])
            _port(workspaces, session, theme, side),
        ],
      ),
    ),
  );

  Widget _graph(AppTheme theme, AiWorkspaceProvider workspaces) {
    final l10n = context.l10n;
    final parent = _selectedIds.length == 1 ? _parentFor(workspaces) : null;
    final visibleSessions = workspaces.sessions.toList()
      ..sort((a, b) {
        int layer(AiAgentWorkspace task) {
          final front = _frontOrder.indexOf(task.id);
          return front < 0
              ? workspaces.sessions.indexOf(task)
              : workspaces.sessions.length + front;
        }

        return layer(a).compareTo(layer(b));
      });
    final sceneSize = Size(
      _positions.entries.fold(
        _sceneSize.width,
        (value, entry) =>
            math.max(value, entry.value.dx + _size(entry.key).width + 200),
      ),
      _positions.entries.fold(
        _sceneSize.height,
        (value, entry) =>
            math.max(value, entry.value.dy + _size(entry.key).height + 200),
      ),
    );
    return Focus(
      focusNode: _canvasFocus,
      onKeyEvent: (_, event) => _canvasKey(workspaces, event),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_viewport != constraints.biggest) {
                  final initialViewport = _viewport.isEmpty;
                  _viewport = constraints.biggest;
                  if (initialViewport || visibleSessions.isEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _fit();
                    });
                  }
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: _canvasInteractions(
                        theme,
                        workspaces,
                        ClipRect(
                          child: InteractiveViewer(
                            key: const ValueKey('task-topology-canvas'),
                            transformationController: _transform,
                            panEnabled: false,
                            // Wheel zoom is handled once by the canvas listener,
                            // requiring Ctrl even before the canvas has focus.
                            scaleEnabled: false,
                            constrained: false,
                            boundaryMargin: const EdgeInsets.all(
                              double.infinity,
                            ),
                            minScale: .25,
                            maxScale: 1.8,
                            child: SizedBox.fromSize(
                              key: _sceneKey,
                              size: sceneSize,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: _sceneBackground(
                                      theme,
                                      workspaces,
                                      visibleSessions,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: AgentTransferLayer(
                                      transfers: workspaces.transfers,
                                      connections: workspaces.connections,
                                      routes: _connectionRoutes,
                                      transform: _transform,
                                      color: theme.basePrimary,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: RepaintBoundary(
                                        child: CustomPaint(
                                          key: const ValueKey(
                                            'topology-connection-preview',
                                          ),
                                          painter: _ConnectionPreviewPainter(
                                            start: _connectingStart,
                                            pointer: _connectionPointer,
                                            transform: _transform,
                                            color: theme.basePrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (workspaces.sessions.isEmpty)
                                    Positioned(
                                      left: 530 - _nodeSize.width / 2,
                                      top: 350 - _nodeSize.height / 2,
                                      width: _nodeSize.width,
                                      child: IgnorePointer(
                                        ignoring: _boxStart != null,
                                        child: _CreatePrimaryTile(
                                          theme: theme,
                                          onPressed: () => _create(workspaces),
                                        ),
                                      ),
                                    ),
                                  for (final session in visibleSessions)
                                    Positioned(
                                      key: ValueKey(
                                        'topology-position-${session.id}',
                                      ),
                                      left: _positions[session.id]!.dx,
                                      top: _positions[session.id]!.dy,
                                      width: _size(session.id).width,
                                      height: _size(session.id).height,
                                      child: IgnorePointer(
                                        ignoring: _boxStart != null,
                                        child: _nodeView(
                                          theme,
                                          workspaces,
                                          session,
                                        ),
                                      ),
                                    ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: RepaintBoundary(
                                        child: ValueListenableBuilder<Rect?>(
                                          valueListenable: _selectionRect,
                                          builder: (context, rect, _) => Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              if (rect != null)
                                                Positioned.fromRect(
                                                  rect: rect,
                                                  child: IgnorePointer(
                                                    child: DecoratedBox(
                                                      key: const ValueKey(
                                                        'topology-selection-overlay',
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: theme.basePrimary
                                                            .withValues(
                                                              alpha: .08,
                                                            ),
                                                        border: Border.all(
                                                          color: theme
                                                              .basePrimary
                                                              .withValues(
                                                                alpha: .8,
                                                              ),
                                                          width:
                                                              1 /
                                                              _transform.value
                                                                  .entry(0, 0)
                                                                  .abs()
                                                                  .clamp(
                                                                    .25,
                                                                    1.8,
                                                                  ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: _graphHeader(theme, workspaces, parent),
                    ),
                  ],
                );
              },
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Padding(
            key: const ValueKey('topology-footer'),
            padding: const EdgeInsets.fromLTRB(18, 8, 12, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        _connectingSource != null
                            ? l10n.aiTopologyConnectHint
                            : _selectedIds.length > 1
                            ? l10n.aiTopologySelectedCount(_selectedIds.length)
                            : l10n.aiTopologySelectionHelp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.textColorTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Material(
                      key: const ValueKey('topology-view-toolbar'),
                      color: theme.primary,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _viewButton(
                              theme,
                              l10n.aiTopologyZoomOut,
                              Symbols.remove_rounded,
                              () => _zoom(1 / 1.2),
                            ),
                            const SizedBox(width: 4),
                            _viewButton(
                              theme,
                              l10n.aiTopologyZoomIn,
                              Symbols.add_rounded,
                              () => _zoom(1.2),
                            ),
                            const SizedBox(width: 4),
                            _backgroundControl(theme, workspaces),
                            const SizedBox(width: 4),
                            KeyedSubtree(
                              key: const ValueKey('topology-auto-layout'),
                              child: _viewButton(
                                theme,
                                l10n.aiTopologyAutoLayout,
                                Symbols.auto_awesome_mosaic_rounded,
                                () => _autoLayout(visibleSessions),
                                iconFill: 1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            _viewButton(
                              theme,
                              l10n.aiTopologyReset,
                              Symbols.fit_screen_rounded,
                              () {
                                _fit(animate: true);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _graphHeader(
    AppTheme theme,
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace? parent,
  ) {
    final l10n = context.l10n;
    const titleStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final labels = [
      l10n.aiTopologyCreatePrimary,
      l10n.aiTopologyCreateChild,
      l10n.aiTopologyDelete,
    ];
    final toolbarWidth = labels.fold<double>(
      12 + (labels.length - 1) * 4,
      (width, label) =>
          width + textWidth(label, const TextStyle(fontSize: 12)) + 49,
    );
    final titleWidth = textWidth(l10n.aiTopologyTitle, titleStyle) + 54;
    final title = IgnorePointer(
      child: DecoratedBox(
        key: const ValueKey('topology-canvas-title'),
        decoration: BoxDecoration(
          color: theme.secondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.blur_on,
                size: 22,
                fill: 1,
                color: theme.textColorPrimary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.aiTopologyTitle,
                  style: titleStyle.copyWith(color: theme.textColorPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Widget action(
      Key key,
      String label,
      IconData icon,
      VoidCallback? onPressed,
    ) => Semantics(
      button: true,
      enabled: onPressed != null,
      child: MenuItemSurface(
        key: key,
        theme: theme,
        onPressed: onPressed,
        disableWhenSelected: false,
        backgroundColor: Colors.transparent,
        surfaceColor: theme.primary,
        hoverColor: theme.basePrimary,
        selectedColor: theme.secondaryTextSelectedColor,
        foregroundColor: onPressed != null
            ? theme.textColorSecondary
            : theme.textColorTertiary,
        hoverForegroundColor: theme.materialColors.onPrimary,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, fill: 1, grade: 200, weight: 300),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: onPressed != null
                        ? FontWeight.w400
                        : FontWeight.w300,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final toolbarSurface = CardShadow(
      theme: theme,
      borderRadius: BorderRadius.circular(999),
      child: Material(
        key: const ValueKey('topology-action-toolbar'),
        color: theme.primary,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              action(
                const ValueKey('topology-new-primary'),
                l10n.aiTopologyCreatePrimary,
                Symbols.add_rounded,
                () => _create(workspaces),
              ),
              action(
                const ValueKey('topology-new-child'),
                l10n.aiTopologyCreateChild,
                Symbols.account_tree_rounded,
                parent == null
                    ? null
                    : () => _create(workspaces, parent: parent),
              ),
              action(
                const ValueKey('topology-delete'),
                l10n.aiTopologyDelete,
                Symbols.delete_outline_rounded,
                _selectedIds.isEmpty ? null : () => _delete(workspaces),
              ),
            ],
          ),
        ),
      ),
    );
    final toolbar = MediaQuery.disableAnimationsOf(context)
        ? toolbarSurface
        : AnimatedSize(
            clipBehavior: Clip.none,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: toolbarSurface,
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Center the tools on the canvas independently of the title.
        // A second row avoids overlap when the window or text size changes.
        if (constraints.maxWidth < titleWidth * 2 + toolbarWidth + 32) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: title),
              const SizedBox(height: 12),
              Center(child: toolbar),
            ],
          );
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            Align(alignment: Alignment.centerLeft, child: title),
            Center(child: toolbar),
          ],
        );
      },
    );
  }

  Widget _viewButton(
    AppTheme theme,
    String label,
    IconData icon,
    VoidCallback onPressed, {
    double iconFill = 0,
  }) => AppTooltip(
    message: label,
    child: Semantics(
      label: label,
      button: true,
      child: MenuItemSurface(
        theme: theme,
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        surfaceColor: theme.primary,
        hoverColor: theme.basePrimary,
        selectedColor: theme.secondaryTextSelectedColor,
        foregroundColor: theme.textColorSecondary,
        hoverForegroundColor: theme.materialColors.onPrimary,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox.square(
          dimension: 24,
          child: Center(child: Icon(icon, size: 17, fill: iconFill)),
        ),
      ),
    ),
  );
}

class _TopologyEditFrame {
  const _TopologyEditFrame(
    this.snapshot,
    this.positions,
    this.frontOrder,
    this.selectedIds,
    this.selectedEdges,
    this.transform,
  );
  final AiTopologyEditSnapshot snapshot;
  final Map<String, Offset> positions;
  final List<String> frontOrder;
  final Set<String> selectedIds;
  final Set<String> selectedEdges;
  final Matrix4 transform;
}

/// 会话顶部名称限高两行，超出后独立滚动。
class _TaskTitleScroll extends StatefulWidget {
  const _TaskTitleScroll({super.key, required this.title, required this.style});
  final String title;
  final TextStyle style;

  @override
  State<_TaskTitleScroll> createState() => _TaskTitleScrollState();
}

class _TaskTitleScrollState extends State<_TaskTitleScroll> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant _TaskTitleScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'M\nM',
        style: DefaultTextStyle.of(context).style.merge(widget.style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final height = painter.height.ceilToDouble();
    painter.dispose();
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = TextPainter(
          text: TextSpan(
            text: widget.title,
            style: DefaultTextStyle.of(context).style.merge(widget.style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final rightInset = content.height > height ? 20.0 : 0.0;
        final width = math.min(
          constraints.maxWidth,
          content.width + rightInset,
        );
        content.dispose();
        return SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: ScrollConfiguration(
              behavior: const AppScrollBehavior(scrollbars: false),
              child: ScrollbarTheme(
                data: ScrollbarTheme.of(context).copyWith(
                  crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                  mainAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                ),
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: false,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    primary: false,
                    padding: EdgeInsets.only(right: rightInset),
                    child: Text(widget.title, style: widget.style),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TaskNode extends StatelessWidget {
  const _TaskNode({
    required this.session,
    required this.selected,
    required this.onOpen,
    required this.theme,
  });
  final AiAgentWorkspace session;
  final bool selected;
  final VoidCallback onOpen;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = _taskStatus(context, session);
    final serviceName =
        session.assistant.selectedService?.name ??
        session.assistant.services
            .where((service) => service.id == session.serviceId)
            .firstOrNull
            ?.name;
    final modelLabel = serviceName == null
        ? session.model
        : '$serviceName · ${session.model}';
    final kind = _kind(l10n, session.kind);
    return Semantics(
      button: true,
      selected: selected,
      label: '${session.title}, $kind, ${status.label}',
      child: AnimatedContainer(
        key: ValueKey('topology-node-${session.id}'),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? theme.basePrimary : Colors.transparent,
          ),
        ),
        child: CardShadow(
          theme: theme,
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: theme.primary,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        session.kind == AiWorkspaceKind.primary
                            ? Symbols.hub_rounded
                            : Symbols.account_tree_rounded,
                        fill: 1,
                        size: _taskKindIconSize,
                        color: theme.textColorTertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          kind,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _taskKindTitleStyle.copyWith(
                            color: theme.textColorTertiary,
                          ),
                        ),
                      ),
                      if (session.busy || session.needsAttention) ...[
                        const SizedBox(width: 8),
                        AppTooltip(
                          message: status.label,
                          child: DecoratedBox(
                            key: ValueKey('topology-status-lamp-${session.id}'),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: session.needsAttention
                                  ? theme.permissionWarningColor
                                  : theme.basePrimary,
                            ),
                            child: const SizedBox(width: 8, height: 8),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    session.title,
                    key: ValueKey('topology-title-${session.id}'),
                    style: _taskNodeTitleStyle.copyWith(
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const Spacer(),
                  AppTooltip(
                    message: l10n.aiAgentModelServiceValue(modelLabel),
                    child: Text(
                      l10n.aiAgentModelServiceValue(modelLabel),
                      key: ValueKey('topology-model-label-${session.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.textColorTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  AppTooltip(
                    message: session.id,
                    child: Text(
                      l10n.aiAgentIdValue(session.id),
                      key: ValueKey('topology-task-id-${session.id}'),
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.textColorTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        status.icon,
                        size: 13,
                        fill: status.fill,
                        color: theme.textColorSecondary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          status.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.textColorSecondary,
                          ),
                        ),
                      ),
                      AppTooltip(
                        message: l10n.aiTopologyOpen,
                        child: TitleBarIconButton(
                          key: ValueKey('topology-open-${session.id}'),
                          theme: theme,
                          isFocused: true,
                          icon: Symbols.arrow_outward_rounded,
                          size: 22,
                          iconSize: 14,
                          backgroundColor: Colors.transparent,
                          surfaceColor: theme.primary,
                          onPressed: onOpen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _kind(AppLocalizations l10n, AiWorkspaceKind kind) => switch (kind) {
  AiWorkspaceKind.primary => l10n.aiTopologyPrimary,
  AiWorkspaceKind.permanent => l10n.aiTopologyPermanent,
};

({String label, IconData icon, double fill}) _taskStatus(
  BuildContext context,
  AiAgentWorkspace session,
) {
  final l10n = context.l10n;
  if (session.closed) {
    return (
      label: l10n.aiTopologyClosed,
      icon: Symbols.task_alt_rounded,
      fill: 0,
    );
  }
  if (session.status == 'unavailable') {
    return (label: l10n.aiSelectModel, icon: Symbols.error_rounded, fill: 1);
  }
  if (session.assistant.stopRequested || session.status == 'stopped') {
    return (
      label: l10n.aiWorkspaceStopped,
      icon: Symbols.stop_circle_rounded,
      fill: 0,
    );
  }
  final response = session.assistant.messages
      .where((message) => message.role == 'assistant' && message.status != null)
      .lastOrNull;
  if (response != null) {
    final summary = aiMessageProcessSummary(context, response);
    if (summary != null) return summary;
  }
  if (session.assistant.pendingApproval != null) {
    return (
      label: l10n.aiWorkspaceNeedsApproval,
      icon: Symbols.safety_check_rounded,
      fill: 1,
    );
  }
  if (session.assistant.pendingUserInput != null) {
    return (
      label: l10n.aiWorkspaceNeedsAnswer,
      icon: Symbols.help_rounded,
      fill: 1,
    );
  }
  if (session.busy) {
    return (
      label: l10n.aiWorkspaceRunning,
      icon: Symbols.progress_activity_rounded,
      fill: 0,
    );
  }
  if (session.status == 'failed') {
    return (
      label: l10n.aiWorkspaceFailed,
      icon: Symbols.error_rounded,
      fill: 1,
    );
  }
  return session.assistant.messages.isEmpty
      ? (
          label: l10n.aiWorkspaceIdle,
          icon: Symbols.chat_bubble_outline_rounded,
          fill: 0,
        )
      : (
          label: l10n.aiWorkspaceCompleted,
          icon: Symbols.check_circle_rounded,
          fill: 0,
        );
}

class _CreatePrimaryTile extends StatelessWidget {
  const _CreatePrimaryTile({required this.theme, required this.onPressed});
  final AppTheme theme;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 124),
    child: TiltCard(
      child: CardShadow(
        theme: theme,
        borderRadius: BorderRadius.circular(24),
        child: MenuItemSurface(
          key: const ValueKey('topology-empty-create'),
          theme: theme,
          backgroundColor: theme.primary,
          hoverColor: theme.primary,
          borderRadius: BorderRadius.circular(24),
          onPressed: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Symbols.add_rounded,
                  size: 24,
                  color: theme.textColorSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.aiTopologyCreatePrimary,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.aiTopologyEmptyHelp,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: theme.textColorTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ConnectionPreviewPainter extends CustomPainter {
  _ConnectionPreviewPainter({
    required this.start,
    required this.pointer,
    required this.transform,
    required this.color,
  }) : super(repaint: Listenable.merge([pointer, transform]));
  final Offset? start;
  final ValueNotifier<Offset?> pointer;
  final TransformationController transform;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final end = pointer.value;
    if (start == null || end == null) return;
    canvas.drawPath(
      TaskTopologyConnection.preview(start!, end).path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / transform.value.entry(0, 0).abs().clamp(.25, 1.8),
    );
  }

  @override
  bool shouldRepaint(_ConnectionPreviewPainter oldDelegate) =>
      start != oldDelegate.start ||
      color != oldDelegate.color ||
      pointer != oldDelegate.pointer ||
      transform != oldDelegate.transform;
}

class _TopologyPainter extends CustomPainter {
  const _TopologyPainter({
    required this.positions,
    required this.nodeSizes,
    required this.sessions,
    required this.connections,
    required this.routes,
    required this.gridColor,
    required this.lineColor,
    required this.canvasStyle,
    required this.scale,
    required this.backgroundBounds,
    required this.accentColor,
    this.selectedEdges = const {},
    this.activeEdges = const {},
  });
  final Color accentColor;
  final Set<String> selectedEdges;
  final Set<String> activeEdges;
  final Rect backgroundBounds;
  final AiTaskCanvasStyle canvasStyle;
  final double scale;
  final Map<String, Offset> positions;
  final Map<String, Size> nodeSizes;
  final List<AiAgentWorkspace> sessions;
  final List<AiTaskConnection> connections;
  final Map<String, TaskTopologyConnection> routes;
  final Color gridColor;
  final Color lineColor;
  @override
  void paint(Canvas canvas, Size size) {
    // 背景覆盖当前可见窗口，包括智能体场景原点外侧，避免重置居中后出现空白边界。
    final origin = Offset(
      (backgroundBounds.left / 24).floor() * 24.0,
      (backgroundBounds.top / 24).floor() * 24.0,
    );
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    paintTaskCanvasBackground(
      canvas,
      Size(backgroundBounds.width + 48, backgroundBounds.height + 48),
      style: canvasStyle,
      color: gridColor,
      scale: scale,
    );
    canvas.restore();
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final socket = Paint()..color = lineColor;
    for (final connection in connections) {
      final parent = positions[connection.fromId];
      final target = positions[connection.toId];
      if (parent == null || target == null) continue;
      final route = routes[connection.id];
      if (route == null) continue;
      final highlighted = selectedEdges.contains(connection.id);
      final edgePaint = highlighted
          ? (Paint()
              ..color = accentColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 / scale.clamp(.25, 1.8))
          : line;
      if (!activeEdges.contains(connection.id)) {
        canvas.drawPath(route.path, edgePaint);
      }
      canvas.drawCircle(
        route.start,
        3.5,
        highlighted ? (Paint()..color = accentColor) : socket,
      );
      canvas.drawCircle(
        route.end,
        3.5,
        highlighted ? (Paint()..color = accentColor) : socket,
      );
    }
  }

  @override
  bool shouldRepaint(_TopologyPainter oldDelegate) =>
      !mapEquals(oldDelegate.positions, positions) ||
      !identical(oldDelegate.routes, routes) ||
      !mapEquals(oldDelegate.nodeSizes, nodeSizes) ||
      oldDelegate.sessions.length != sessions.length ||
      !listEquals(
        oldDelegate.connections.map((c) => (c.id, c.fromId, c.toId)).toList(),
        connections.map((c) => (c.id, c.fromId, c.toId)).toList(),
      ) ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.canvasStyle != canvasStyle ||
      oldDelegate.backgroundBounds != backgroundBounds ||
      oldDelegate.accentColor != accentColor ||
      !setEquals(oldDelegate.selectedEdges, selectedEdges) ||
      !setEquals(oldDelegate.activeEdges, activeEdges) ||
      oldDelegate.scale != scale ||
      oldDelegate.lineColor != lineColor;
}

class _TopologyConversation extends StatelessWidget {
  const _TopologyConversation({
    super.key,
    required this.session,
    required this.onBack,
  });
  final AiAgentWorkspace session;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppTooltip(
                message: l10n.back,
                child: Semantics(
                  label: l10n.back,
                  button: true,
                  child: TitleBarIconButton(
                    key: const ValueKey('topology-back'),
                    theme: theme,
                    backgroundColor: theme.primary,
                    isFocused: true,
                    icon: Symbols.arrow_back_rounded,
                    size: 28,
                    iconSize: 18,
                    onPressed: onBack,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: _TaskTitleScroll(
                  key: ValueKey(
                    'topology-conversation-title-scroll-${session.id}',
                  ),
                  title: session.title,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  key: ValueKey('topology-conversation-info-${session.id}'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          switch (session.kind) {
                            AiWorkspaceKind.primary => Symbols.hub_rounded,
                            AiWorkspaceKind.permanent =>
                              Symbols.account_tree_rounded,
                          },
                          fill: 1,
                          size: _taskKindIconSize,
                          color: theme.textColorTertiary,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            _kind(l10n, session.kind),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _taskKindTitleStyle.copyWith(
                              color: theme.textColorTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.aiAgentIdValue(session.id),
                      key: ValueKey(
                        'topology-conversation-task-id-${session.id}',
                      ),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.textColorTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
        Expanded(
          child: AssistantPage(
            initialDraft: session.assistant.messages.isEmpty
                ? session.task
                : '',
          ),
        ),
      ],
    );
  }
}

class _TopologyCreateDialog extends StatefulWidget {
  const _TopologyCreateDialog({required this.workspaces, this.parent});
  final AiWorkspaceProvider workspaces;
  final AiAgentWorkspace? parent;
  @override
  State<_TopologyCreateDialog> createState() => _TopologyCreateDialogState();
}

class _TopologyCreateDialogState extends State<_TopologyCreateDialog> {
  final _title = TextEditingController();
  final _task = TextEditingController();
  final _scroll = ScrollController();
  bool _working = false;
  bool _missing = false;
  Object? _error;
  String _model = '';
  late final AiAssistantProvider _draft;
  @override
  void initState() {
    super.initState();
    final inherited = widget.parent?.assistant ?? widget.workspaces.main;
    _draft = inherited.forkForWorkspace();
    _draft.addListener(_draftChanged);
    if (widget.parent == null &&
        inherited.hasApiKey &&
        inherited.selectedService != null &&
        inherited.selectedModel != null) {
      _model = jsonEncode([
        inherited.selectedService!.id,
        inherited.selectedModel,
      ]);
    }
    if (!inherited.hasApiKey || inherited.selectedModel == null) {
      final fallback = widget.workspaces.main.services
          .where(
            (service) =>
                widget.workspaces.main.hasServiceKey(service.id) &&
                service.models.isNotEmpty,
          )
          .firstOrNull;
      if (fallback != null) {
        _model = jsonEncode([fallback.id, fallback.models.first]);
      }
    }
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _draft.removeListener(_draftChanged);
    _draft.dispose();
    _title.dispose();
    _task.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_task.text.trim().isEmpty) {
      setState(() => _missing = true);
      return;
    }
    setState(() {
      _working = true;
      _missing = false;
      _error = null;
    });
    try {
      final choice = _model.isEmpty
          ? null
          : (jsonDecode(_model) as List).cast<String>();
      final session = widget.parent == null
          ? await widget.workspaces.createPrimary(
              title: _title.text.trim(),
              task: _task.text.trim(),
              serviceId: choice?[0],
              model: choice?[1],
              permissions: _draft.permissions,
              reasoningEffort: _draft.reasoningEffort,
            )
          : await widget.workspaces.create(
              title: _title.text.trim(),
              task: _task.text.trim(),
              serviceId: choice?[0],
              model: choice?[1],
              permissions: _draft.permissions,
              reasoningEffort: _draft.reasoningEffort,
              parentId: widget.parent!.id,
              kind: AiWorkspaceKind.permanent,
            );
      if (mounted) {
        Navigator.pop(context, session.id);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final l10n = context.l10n;
    final title = widget.parent == null
        ? l10n.aiTopologyCreatePrimary
        : l10n.aiTopologyCreateChild;
    return AppDialog(
      theme: theme,
      title: title,
      titleFontSize: 18,
      titleFontWeight: FontWeight.w500,
      constraints: const BoxConstraints(maxWidth: 540),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
      content: SizedBox(
        width: 492,
        child: ScrollbarTheme(
          data: ScrollbarTheme.of(
            context,
          ).copyWith(crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset),
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.parent == null
                      ? l10n.aiTopologyNewPrimaryHelp
                      : l10n.aiTopologyNewChildHelp,
                  style: AppDialogStyle.descriptionStyle(theme),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.aiTopologyNameOptional,
                  style: AppDialogStyle.fieldTitleStyle(theme),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.aiTopologyNameHelp,
                  style: AppDialogStyle.descriptionStyle(theme),
                ),
                const SizedBox(height: 8),
                SettingControlledTextField(
                  key: const ValueKey('topology-title-input'),
                  theme: theme,
                  controller: _title,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 200,
                  autofocus: true,
                  enabled: !_working,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.aiTopologyModel,
                  style: AppDialogStyle.fieldTitleStyle(theme),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.aiTopologyModelHelp,
                  style: AppDialogStyle.descriptionStyle(theme),
                ),
                const SizedBox(height: 8),
                IgnorePointer(
                  ignoring: _working,
                  child: ExcludeFocus(
                    excluding: _working,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ModelSelector(
                        key: const ValueKey('topology-model-select'),
                        theme: theme,
                        assistant: _draft,
                        fieldSurfaceColor: AppDialogStyle.backgroundColor(
                          theme,
                        ),
                        selectedServiceId: _model.isEmpty
                            ? null
                            : (jsonDecode(_model) as List)[0] as String,
                        selectedModel: _model.isEmpty
                            ? null
                            : (jsonDecode(_model) as List)[1] as String,
                        inheritLabel: widget.parent == null
                            ? null
                            : l10n.aiTopologyInherit,
                        onInherit:
                            widget.parent != null &&
                                widget.parent!.assistant.hasApiKey
                            ? () async {
                                final parent = widget.parent!.assistant;
                                await _draft.selectModel(
                                  parent.selectedService!.id,
                                  parent.selectedModel!,
                                );
                                await _draft.setReasoningEffort(
                                  parent.reasoningEffort,
                                );
                                if (mounted) setState(() => _model = '');
                              }
                            : null,
                        onSelected: (serviceId, model) => setState(
                          () => _model = jsonEncode([serviceId, model]),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.aiPermissions,
                  style: AppDialogStyle.fieldTitleStyle(theme),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.aiTopologyPermissionsHelp,
                  style: AppDialogStyle.descriptionStyle(theme),
                ),
                const SizedBox(height: 8),
                IgnorePointer(
                  ignoring: _working,
                  child: ExcludeFocus(
                    excluding: _working,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ListenableBuilder(
                        listenable: _draft,
                        builder: (context, _) => AssistantPermissionsButton(
                          theme: theme,
                          assistant: _draft,
                          fieldSurfaceColor: AppDialogStyle.backgroundColor(
                            theme,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.aiWorkspaceTaskPrompt,
                  style: AppDialogStyle.fieldTitleStyle(theme),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.aiTopologyTaskHelp,
                  style: AppDialogStyle.descriptionStyle(theme),
                ),
                const SizedBox(height: 8),
                SettingControlledTextField(
                  key: const ValueKey('topology-task-input'),
                  theme: theme,
                  controller: _task,
                  minLines: 4,
                  maxLines: 8,
                  enabled: !_working,
                ),
                if (_missing || _error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _missing
                        ? l10n.aiTopologyTaskContentRequired
                        : aiErrorText(l10n, _error!),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        AppActionButton.dialog(
          theme: theme,
          label: l10n.settingsCancel,
          onPressed: _working ? null : () => Navigator.pop(context),
        ),
        AppActionButton.dialog(
          key: const ValueKey('topology-create-confirm'),
          theme: theme,
          label: title,
          primary: true,
          onPressed: _working ? null : _save,
        ),
      ],
    );
  }
}

class _TopologyRenameDialog extends StatefulWidget {
  const _TopologyRenameDialog({required this.title});
  final String title;

  @override
  State<_TopologyRenameDialog> createState() => _TopologyRenameDialogState();
}

class _TopologyRenameDialogState extends State<_TopologyRenameDialog> {
  late final _title = TextEditingController(text: widget.title);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final l10n = context.l10n;
    return AppDialog(
      theme: theme,
      title: l10n.aiTopologyRename,
      titleFontSize: 18,
      titleFontWeight: FontWeight.w500,
      constraints: const BoxConstraints(maxWidth: 480),
      content: SizedBox(
        width: 432,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.aiWorkspaceTaskTitle,
              style: AppDialogStyle.fieldTitleStyle(theme),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.aiTopologyRenameHelp,
              style: AppDialogStyle.descriptionStyle(theme),
            ),
            const SizedBox(height: 8),
            SettingControlledTextField(
              key: const ValueKey('topology-rename-input'),
              theme: theme,
              controller: _title,
              minLines: 1,
              maxLines: 4,
              autofocus: true,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        AppActionButton.dialog(
          theme: theme,
          label: l10n.settingsCancel,
          onPressed: () => Navigator.pop(context),
        ),
        AppActionButton.dialog(
          key: const ValueKey('topology-rename-confirm'),
          theme: theme,
          label: l10n.aiTopologyRename,
          primary: true,
          onPressed: _title.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _title.text.trim()),
        ),
      ],
    );
  }
}
