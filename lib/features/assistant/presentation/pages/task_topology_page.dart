/*
 * @Description: 在可平移缩放的多层智能体树中组织主智能体和可见子智能体，并保留独立对话。
 */
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
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
import '../../../../core/widgets/interaction_decoration.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/retained_page_stack.dart';
import '../../../../core/widgets/settings/fields.dart';
import '../../../../core/widgets/settings/select.dart';
import '../../../../core/widgets/tilt_card.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../settings/presentation/widgets/content_layout.dart';
import '../../domain/roleplay_card.dart';
import '../../domain/task_canvas_style.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/provider.dart';
import '../widgets/agent_direct_transfer.dart';
import '../widgets/agent_transfer_layer.dart';
import '../widgets/error_text.dart';
import '../widgets/model_selector.dart';
import '../widgets/permissions_button.dart';
import '../widgets/process_event_view.dart';
import '../widgets/roleplay_card_controls.dart';
import '../widgets/storage_content.dart';
import '../widgets/task_canvas_background.dart';
import '../widgets/task_navigation_scope.dart';
import '../widgets/task_topology_connection.dart';
import '../widgets/task_topology_connection_layer.dart';
import '../widgets/task_topology_layout.dart';
import '../widgets/task_topology_node_layer.dart';
import '../widgets/task_topology_overview_card.dart';
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
const _topologyHeaderTitleStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
);
const _topologyHeaderTitlePadding = EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 8,
);
const _topologyHeaderTitleRadius = BorderRadius.all(Radius.circular(10));
const _sceneSize = Size(1060, 700);

class TaskTopologyPage extends StatefulWidget {
  const TaskTopologyPage({super.key});
  @override
  State<TaskTopologyPage> createState() => _TaskTopologyPageState();
}

class _TaskTopologyPageState extends State<TaskTopologyPage>
    with SingleTickerProviderStateMixin {
  static const _graphKey = 'topology-graph';
  static const _windowFocusChannel = OptionalMethodChannel(
    'lilygobox/window_focus',
  );
  final _transform = TransformationController();
  late final AnimationController _viewMotion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(_animateView);
  Matrix4Tween? _viewTween;
  Curve _viewCurve = Curves.easeOut;
  double? _wheelZoomTargetScale;
  int _wheelZoomDirection = 0;
  Offset? _wheelPanTarget;
  Offset _wheelPanDirection = Offset.zero;
  final _wheelPanAcceleration = WheelScrollAcceleration();

  void _animateView() {
    if (_viewTween case final tween?) {
      _transform.value = tween.transform(
        _viewCurve.transform(_viewMotion.value),
      );
    }
  }

  void _animateViewTo(Matrix4 target, Curve curve) {
    _viewTween = Matrix4Tween(begin: _transform.value.clone(), end: target);
    _viewCurve = curve;
    _viewMotion.forward(from: 0);
  }

  final _movedNodes = <String, Offset>{};
  final _nodeMenus = <String, RightClickMenuController>{};
  String? _openNodeMenuId;
  String? _overviewMenuId;
  int? _overviewMenuPointer;
  final _backgroundMenu = RightClickMenuController();
  final _canvasMenu = RightClickMenuController();
  final _canvasFocus = FocusNode(debugLabel: 'task topology canvas');
  final _sceneKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _selectedIds = <String>{};
  final _frontOrder = <String>[];
  List<AiTaskCardCopy> _copiedCards = const [];
  Map<String, Offset> _copiedPositions = const {};
  String? _cardClipboardToken;
  Offset? _canvasPointer;
  Offset? _menuPointer;
  Offset? _importPlacement;
  bool _importCommitting = false;
  int _lastImportRevision = 0;
  bool _pastingCards = false;
  bool _connectingTasks = false;
  bool _disconnectingTasks = false;
  final _selectedEdges = <String>{};
  Set<String> _boxEdgeBase = {};
  String? _rightEdge;
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
  final _dragPreview = TaskCanvasDragPreview();
  Rect _dragBounds = Rect.zero;
  double _dragEdgeMargin = 0;
  double _maxNodeSide() => _nodeSizes.values.fold<double>(
    0,
    (largest, size) => math.max(largest, size.longestSide),
  );
  Offset _dragDelta = Offset.zero;
  String? _dragAnchorId;
  Offset _dragPointer = Offset.zero;
  Offset _nodeGrabOffset = Offset.zero;
  String? _lastTapId;
  Duration? _lastTapTime;
  Offset? _lastTapPosition;
  Offset? _nodePointerDown;
  bool _nodePrimaryDown = false;
  bool _nodeDragged = false;
  String? _openId;
  final List<String?> _conversationHistory = [];
  final _editingRoleplay = <String>{};
  final _visitedChats = <String>{};
  int _lastNavigationRevision = 0;
  AiWorkspaceProvider? _navigationWorkspace;
  bool _pageActive = true;
  Size _viewport = Size.zero;
  bool _fitOnLayout = false;
  static const _viewportPreference = 'ai.agentCanvasViewport.v1';
  bool _initializeViewport = true;
  bool _hasSavedViewport = false;
  Map<String, Offset> _positions = const {};
  final _nodePositions = <String, ValueNotifier<Offset>>{};
  final _sceneExtent = ValueNotifier(_sceneSize);
  final _sceneOrigin = ValueNotifier(Offset.zero);
  final _connectionGeometry = ValueNotifier(0);
  final _nodeIndex = TaskCanvasSpatialIndex();
  final _overviewPaint = TaskOverviewPaintCache();
  final _nodeGeometry = ValueNotifier(0);
  final Set<String> _restoredPositionIds = {};
  Map<String, Size> _nodeSizes = const {};
  Map<String, TaskTopologyConnection> _connectionRoutes = const {};
  final _incidentEdges = <String, List<AiTaskConnection>>{};
  final _edgeIndex = TaskCanvasSpatialIndex();
  final _edgeLayers = <String, int>{};
  List<AiTaskConnection> _routedConnections = const [];
  int _routedNodeRevision = -1;
  int _visibleRouteRevision = -1;
  Rect _edgeCoverage = Rect.zero;
  double _edgeCoverageScale = 0;
  Map<String, TaskTopologyConnection> _visibleRoutes = const {};
  Rect _backgroundCoverage = Rect.zero;
  final _backgroundPattern = TaskCanvasBackgroundPattern();
  double _backgroundScale = 0;
  List<(String, String, String)> _routedEdges = const [];

  final _undoEdits = <(_TopologyEditFrame, _TopologyEditFrame)>[];
  final _redoEdits = <(_TopologyEditFrame, _TopologyEditFrame)>[];
  AiWorkspaceProvider? _historyWorkspace;
  int _recycleRevision = 0;
  _TopologyEditFrame? _dragEdit;
  bool _restoringHistory = false;
  bool _controlHints = false;
  bool _shiftHints = false;
  bool _spaceHints = false;
  bool _ignoreStaleShift = false;
  Timer? _shiftReleaseCheck;

  _TopologyEditFrame _captureEdit(AiWorkspaceProvider workspaces) {
    _historyWorkspace = workspaces;
    final visible = workspaces.sessions;
    late final fallback = _layout(visible);
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
      _sceneOrigin.value,
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
        listEquals(before.frontOrder, after.frontOrder) &&
        before.origin == after.origin) {
      _releaseFrame(before);
      _releaseFrame(after);
      return;
    }
    workspaces.updateCanvasPositions({
      for (final e in after.positions.entries) e.key: [e.value.dx, e.value.dy],
    }, origin: after.origin);
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
      final positions = {
        for (final entry in _positions.entries)
          if (workspaces.find(entry.key) != null) entry.key: entry.value,
        for (final entry in frame.positions.entries)
          if (workspaces.find(entry.key) != null) entry.key: entry.value,
      };
      setState(() {
        _movedNodes
          ..clear()
          ..addAll(positions);
        _positions = positions;
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
        _sceneOrigin.value = frame.origin;
        _transform.value = frame.transform.clone();
      });
      workspaces.updateCanvasPositions({
        for (final entry in positions.entries)
          entry.key: [entry.value.dx, entry.value.dy],
      }, origin: frame.origin);
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

  final _measuredNodes = <String, ((String, bool), Size)>{};
  final _nodeCards = <String, (Object, Widget)>{};
  final _textHeights = <(String, TextStyle), double>{};
  Object? _measurementEnvironment;

  Map<String, Size> _measureNodes(Iterable<AiAgentWorkspace> sessions) {
    final scaler = MediaQuery.textScalerOf(context);
    final defaultStyle = DefaultTextStyle.of(context).style;
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final l10n = context.l10n;
    final environment = (scaler, defaultStyle, direction, locale, l10n);
    if (environment != _measurementEnvironment) {
      _measurementEnvironment = environment;
      _textHeights.clear();
      _measuredNodes.clear();
    }
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: defaultStyle.merge(style)),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
      )..layout(maxWidth: _nodeSize.width - 28);
      final result = painter.height;
      painter.dispose();
      return result;
    }

    double sharedHeight(String text, TextStyle style) {
      final key = (text, style);
      if (_textHeights[key] case final cached?) return cached;
      if (_textHeights.length >= 512) _textHeights.clear();
      return _textHeights[key] = measure(text, style);
    }

    late final twoLines = sharedHeight('M\nM', _taskNodeTitleStyle);
    late final small = sharedHeight('M', const TextStyle(fontSize: 10));
    late final kind = sharedHeight('M', _taskKindTitleStyle);
    late final status = sharedHeight('M', const TextStyle(fontSize: 11));
    late final roleRow = math.max(
      27.0,
      sharedHeight('M', const TextStyle(fontSize: 11)) + 8,
    );
    final minimum = _nodeSize.height * math.max(1, scaler.scale(13) / 13);
    final sizes = <String, Size>{};
    for (final session in sessions) {
      final hasRole = session.assistant.roleplayBinding != null;
      final signature = (session.title, hasRole);
      final cached = _measuredNodes[session.id];
      if (cached != null && cached.$1 == signature) {
        sizes[session.id] = cached.$2;
        continue;
      }
      final title = sharedHeight(session.title, _taskNodeTitleStyle);
      final taskId = measure(
        l10n.aiAgentIdValue(session.id),
        const TextStyle(fontSize: 10),
      );
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
      final size = Size(
        _nodeSize.width,
        math
                .max(minimum + math.max(0, title - twoLines), content)
                .ceilToDouble() +
            (hasRole ? roleRow + 6 : 0),
      );
      sizes[session.id] = size;
      _measuredNodes[session.id] = (signature, size);
    }
    return sizes;
  }

  int _lastCount = -1;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_saveViewport);
  }

  @override
  void dispose() {
    _shiftReleaseCheck?.cancel();
    _shiftReleaseCheck = null;
    _transform.removeListener(_saveViewport);
    if (_hasSavedViewport) {
      unawaited(_navigationWorkspace?.main.workspacePreferences.flush());
    }
    _clearEdits(_undoEdits);
    _clearEdits(_redoEdits);
    if (_dragEdit case final frame?) _releaseFrame(frame);
    if (_navigationWorkspace?.layoutCanvasGroup == _layoutCanvasGroup) {
      _navigationWorkspace?.layoutCanvasGroup = null;
    }
    _navigationWorkspace?.activeConversationId = null;
    for (final position in _nodePositions.values) {
      position.dispose();
    }
    _sceneExtent.dispose();
    _sceneOrigin.dispose();
    _overviewPaint.dispose();
    _connectionGeometry.dispose();
    _nodeGeometry.dispose();
    _dragPreview.dispose();
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
      _visitedChats.add(session.id);
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

  Future<void> _chooseRoleplayOpening(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
    AppTheme theme,
    AiRoleplayBinding binding,
  ) async {
    final assistant = session.assistant;
    bool current() =>
        mounted &&
        _openId == session.id &&
        identical(workspaces.find(session.id), session) &&
        identical(assistant.roleplayBinding, binding) &&
        assistant.canChooseRoleplayOpening;
    if (!current()) return;
    final chosen = await pickRoleplayOpening(
      context,
      theme,
      binding,
      hasConversationToRestart: () => assistant.hasConversationToRestart,
    );
    if (chosen == null || !current()) return;
    assistant.startRoleplayOpening(
      chosen.index,
      clearExisting: chosen.clearExisting,
    );
  }

  Future<void> _editRoleplaySettings(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
    AppTheme theme,
  ) async {
    final assistant = session.assistant;
    final previous = assistant.roleplayBinding;
    if (previous == null || !_editingRoleplay.add(session.id)) return;
    try {
      final updated = await showDialog<AiRoleplayBinding>(
        context: context,
        builder: (_) =>
            RoleplayCardOptionsDialog(binding: previous, theme: theme),
      );
      if (updated != null &&
          mounted &&
          identical(workspaces.find(session.id), session)) {
        assistant.updateRoleplayOptions(previous, updated);
      }
    } finally {
      _editingRoleplay.remove(session.id);
    }
  }

  bool get _canvasShortcutModifierPressed {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isControlPressed ||
        (defaultTargetPlatform != TargetPlatform.windows &&
            keyboard.isMetaPressed);
  }

  bool get _extendSelection =>
      _canvasShortcutModifierPressed || _canvasShiftPressed;

  bool get _canvasShiftPressed =>
      !_ignoreStaleShift && HardwareKeyboard.instance.isShiftPressed;

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
        _nodeDragged ||
        _nodePointerDown == null ||
        (event.position - _nodePointerDown!).distance > 8) {
      _lastTapId = null;
      return;
    }
    if (!_extendSelection &&
        _lastTapId == session.id &&
        _lastTapTime != null &&
        event.timeStamp - _lastTapTime! >= Duration.zero &&
        event.timeStamp - _lastTapTime! <= const Duration(milliseconds: 500) &&
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
    _nodeDragged = true;
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
    _dragAnchorId = session.id;
    if (_positions.length > 64 && _dragStarts.length >= 32) {
      _dragPreview.starts = _dragStarts;
      _dragPreview.all = _dragStarts.length == _positions.length;
      _dragBounds = _dragStarts.keys
          .map((id) => _nodeIndex[id]!)
          .reduce((first, next) => first.expandToInclude(next));
      _dragEdgeMargin = _dragPreview.all ? 0 : _maxNodeSide();
    }
    _dragEdit = _captureEdit(workspaces);
    _transform.addListener(_syncDraggedNodes);
  }

  void _updateNodeDrag(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
    Offset globalPosition,
  ) {
    if (_dragAnchorId == null) {
      final down = _nodePointerDown;
      if (!_nodePrimaryDown ||
          down == null ||
          (globalPosition - down).distance <= 8) {
        return;
      }
      _startNodeDrag(workspaces, session);
    }
    if (_dragAnchorId != session.id) return;
    final viewport =
        _viewportKey.currentContext!.findRenderObject()! as RenderBox;
    _dragPointer = viewport.globalToLocal(globalPosition);
    _syncDraggedNodes();
  }

  void _syncDraggedNodes() {
    final anchor = _dragStarts[_dragAnchorId];
    final workspaces = _navigationWorkspace;
    if (anchor == null || workspaces == null) return;
    final delta = _transform.toScene(_dragPointer) - anchor - _nodeGrabOffset;
    if ((delta - _dragDelta).distanceSquared < precisionErrorTolerance) return;
    _dragDelta = delta;
    if (_dragPreview.starts.isNotEmpty) {
      final bounds = _dragBounds.shift(delta);
      if (bounds.left < 24 || bounds.top < 24) {
        _commitDragPreview(workspaces, continueDrag: true);
      } else {
        final extent = _sceneExtent.value;
        _sceneExtent.value = Size(
          math.max(extent.width, bounds.right + 200),
          math.max(extent.height, bounds.bottom + 200),
        );
        _dragPreview.move(delta);
      }
      return;
    }
    var left = double.infinity;
    var top = double.infinity;
    for (final entry in _dragStarts.entries) {
      final next = entry.value + delta;
      _positions[entry.key] = _movedNodes[entry.key] = next;
      left = math.min(left, next.dx);
      top = math.min(top, next.dy);
    }
    // 卡片接近有限绘制区域边缘前重新设置坐标原点；按完整网格单元平移，
    // 保持背景稳定，再通过视图反向平移保持
    // 指针和卡片的位置。这只是坐标换算，不限制拖动范围。
    final shift = Offset(
      left < 24 ? ((240 - left) / 24).ceil() * 24.0 : 0,
      top < 24 ? ((240 - top) / 24).ceil() * 24.0 : 0,
    );
    if (shift != Offset.zero) {
      _dragStarts = {
        for (final entry in _dragStarts.entries) entry.key: entry.value + shift,
      };
      _positions = {
        for (final entry in _positions.entries) entry.key: entry.value + shift,
      };
      _movedNodes.addAll(_positions);
      _rebaseView(shift);
    }
    final moved = shift == Offset.zero ? _dragStarts.keys : null;
    _syncSceneGeometry(ids: moved);
    _updateConnectionRoutes(workspaces, movedIds: moved);
  }

  void _commitDragPreview(
    AiWorkspaceProvider workspaces, {
    bool continueDrag = false,
  }) {
    final bounds = _dragBounds.shift(_dragDelta);
    final shift = Offset(
      bounds.left < 24 ? ((240 - bounds.left) / 24).ceil() * 24.0 : 0,
      bounds.top < 24 ? ((240 - bounds.top) / 24).ceil() * 24.0 : 0,
    );
    for (final entry in _dragStarts.entries) {
      _positions[entry.key] = _movedNodes[entry.key] = entry.value + _dragDelta;
    }
    if (shift != Offset.zero) {
      _positions = {
        for (final entry in _positions.entries) entry.key: entry.value + shift,
      };
      _movedNodes.addAll(_positions);
    }
    if (continueDrag) {
      _dragStarts = {for (final id in _dragStarts.keys) id: _positions[id]!};
      _dragPreview.starts = _dragStarts;
      _dragBounds = bounds.shift(shift);
      _dragPreview.move(Offset.zero);
    } else {
      _dragPreview.reset();
    }
    _dragDelta = Offset.zero;
    if (shift != Offset.zero) _rebaseView(shift);
    _syncSceneGeometry();
    _updateConnectionRoutes(workspaces);
  }

  void _rebaseView(Offset shift) {
    _sceneOrigin.value += shift;
    Matrix4 rebased(Matrix4 matrix) =>
        matrix.clone()..translateByDouble(-shift.dx, -shift.dy, 0, 1);
    final tween = _viewTween;
    if (_viewMotion.isAnimating && tween != null) {
      tween.begin = rebased(tween.begin!);
      final target = tween.end = rebased(tween.end!);
      if (_wheelPanTarget != null) {
        _wheelPanTarget = Offset(target.entry(0, 3), target.entry(1, 3));
      }
    }
    _transform.value = rebased(_transform.value);
  }

  void _endNodeDrag(AiWorkspaceProvider workspaces, {bool recordEdit = true}) {
    final before = _dragEdit;
    if (before == null && _dragStarts.isEmpty) return;
    _transform.removeListener(_syncDraggedNodes);
    _dragAnchorId = null;
    if (_dragPreview.starts.isNotEmpty) _commitDragPreview(workspaces);
    _dragEdit = null;
    _dragStarts.clear();
    _dragDelta = Offset.zero;
    _nodePrimaryDown = false;
    _nodePointerDown = null;
    if (before == null) return;
    if (recordEdit) {
      _finishEdit(workspaces, before);
    } else {
      _releaseFrame(before);
    }
  }

  void _autoLayout(List<AiAgentWorkspace> sessions) {
    final workspaces = context.read<AiWorkspaceProvider>();
    _edit(workspaces, () {
      _viewMotion.stop();
      setState(() {
        _movedNodes.clear();
        workspaces.canvasPositions.clear();
        _sceneOrigin.value = Offset.zero;
        _positions = _layout(sessions, incremental: false);
      });
      _fit(animate: true);
    });
  }

  bool _layoutCanvasGroup(Set<String> ids) {
    final workspaces = _navigationWorkspace;
    if (!mounted ||
        workspaces == null ||
        _restoringHistory ||
        _dragEdit != null) {
      return false;
    }
    final sessions = workspaces.sessions.toList();
    final group = sessions
        .where((session) => ids.contains(session.id))
        .toList();
    if (group.isEmpty) return false;
    final sizes = _measureNodes(sessions);
    final current = {..._layout(sessions), ..._positions};
    final next = layoutTaskTopology(
      sessions: group,
      nodeSizes: sizes,
      connections: workspaces.connections,
    );
    final leader = group.firstWhere((session) => session.parentId == null);
    var offset = (current[leader.id] ?? next[leader.id]!) - next[leader.id]!;
    final bounds = next.entries
        .map((entry) => entry.value & sizes[entry.key]!)
        .reduce((first, second) => first.expandToInclude(second));
    final obstacles = [
      for (final session in sessions)
        if (!ids.contains(session.id))
          (current[session.id]! & sizes[session.id]!).inflate(40),
    ];
    while (true) {
      final overlaps = obstacles.where(bounds.shift(offset).overlaps);
      if (overlaps.isEmpty) break;
      final right = overlaps.map((rect) => rect.right).reduce(math.max);
      offset = Offset(right - bounds.left + 1, offset.dy);
    }
    _edit(workspaces, () {
      setState(() {
        _movedNodes.addAll(current);
        for (final entry in next.entries) {
          _movedNodes[entry.key] = entry.value + offset;
        }
        _positions = {
          for (final session in sessions) session.id: _movedNodes[session.id]!,
        };
      });
    });
    return true;
  }

  TaskTopologyConnection? _route(AiTaskConnection connection) =>
      _connectionRoutes[connection.id];

  void _syncSceneGeometry({Iterable<String>? ids}) {
    var changed = false;
    if (ids == null) {
      final removed = _nodeIndex.ids
          .where((id) => !_positions.containsKey(id))
          .toList();
      for (final id in removed) {
        _nodeIndex.remove(id);
        changed = true;
      }
    }
    var extent = ids == null ? _sceneSize : _sceneExtent.value;
    for (final id in ids ?? _positions.keys) {
      final position = _positions[id];
      if (position == null) continue;
      final rect = position & _size(id);
      if (_nodeIndex.update(id, rect)) changed = true;
      extent = Size(
        math.max(extent.width, rect.right + 200),
        math.max(extent.height, rect.bottom + 200),
      );
      final notifier = _nodePositions[id];
      if (notifier == null) {
        _nodePositions[id] = ValueNotifier(position);
      } else {
        notifier.value = position;
      }
    }
    _sceneExtent.value = extent;
    if (changed) _nodeGeometry.value++;
  }

  void _updateConnectionRoutes(
    AiWorkspaceProvider workspaces, {
    Iterable<String>? movedIds,
  }) {
    if (movedIds != null) {
      final affected = <String, AiTaskConnection>{
        for (final id in movedIds)
          for (final edge in _incidentEdges[id] ?? const <AiTaskConnection>[])
            edge.id: edge,
      };
      for (final edge in affected.values) {
        final route = TaskTopologyConnection.between(
          _nodeIndex[edge.fromId]!,
          _nodeIndex[edge.toId]!,
        );
        _connectionRoutes[edge.id] = route;
        _edgeIndex.update(
          edge.id,
          Rect.fromPoints(route.start, route.end).inflate(8),
        );
      }
      _routedNodeRevision = _nodeGeometry.value;
      if (affected.isNotEmpty) _connectionGeometry.value++;
      return;
    }
    final connections = workspaces.connections;
    final edges = [
      for (final edge in connections) (edge.id, edge.fromId, edge.toId),
    ];
    if (_routedNodeRevision == _nodeGeometry.value &&
        listEquals(edges, _routedEdges)) {
      return;
    }
    _routedNodeRevision = _nodeGeometry.value;
    _routedEdges = edges;
    _routedConnections = connections;
    _incidentEdges.clear();
    _edgeLayers.clear();
    for (final (index, edge) in connections.indexed) {
      _edgeLayers[edge.id] = index;
      (_incidentEdges[edge.fromId] ??= []).add(edge);
      (_incidentEdges[edge.toId] ??= []).add(edge);
    }
    _connectionRoutes = buildTaskTopologyRoutes(
      nodes: {for (final id in _positions.keys) id: _nodeIndex[id]!},
      connections: connections,
    );
    for (final id
        in _edgeIndex.ids
            .where((id) => !_connectionRoutes.containsKey(id))
            .toList()) {
      _edgeIndex.remove(id);
    }
    for (final entry in _connectionRoutes.entries) {
      _edgeIndex.update(
        entry.key,
        Rect.fromPoints(entry.value.start, entry.value.end).inflate(8),
      );
    }
    _connectionGeometry.value += 1;
  }

  Map<String, TaskTopologyConnection> _routesInView() {
    final scale = _transform.value.entry(0, 0).abs();
    var viewport = Rect.fromPoints(
      _transform.toScene(Offset.zero),
      _transform.toScene(_viewport.bottomRight(Offset.zero)),
    );
    final delta = _dragPreview.value;
    if (_dragPreview.all) {
      viewport = viewport.shift(-delta);
    } else if (delta != Offset.zero) {
      final coverage = viewport.inflate(96 / scale);
      _edgeCoverage = coverage;
      _visibleRouteRevision = -1;
      final search = coverage
          .expandToInclude(coverage.shift(-delta))
          .inflate(_dragEdgeMargin);
      final candidates = _edgeIndex.intersecting(search).toList()
        ..sort(
          (first, second) =>
              _edgeLayers[first]!.compareTo(_edgeLayers[second]!),
        );
      final routes = <String, TaskTopologyConnection>{};
      for (final id in candidates) {
        final edge = _routedConnections[_edgeLayers[id]!];
        final fromMoved = _dragPreview.starts.containsKey(edge.fromId);
        final toMoved = _dragPreview.starts.containsKey(edge.toId);
        final route = fromMoved || toMoved
            ? TaskTopologyConnection.between(
                _nodeIndex[edge.fromId]!.shift(fromMoved ? delta : Offset.zero),
                _nodeIndex[edge.toId]!.shift(toMoved ? delta : Offset.zero),
              )
            : _connectionRoutes[id]!;
        if (Rect.fromPoints(
          route.start,
          route.end,
        ).inflate(8).overlaps(coverage)) {
          routes[id] = route;
        }
      }
      return routes;
    }
    if (_connectionRoutes.length <= 64) return _connectionRoutes;
    if (_visibleRouteRevision != _connectionGeometry.value ||
        scale >= _edgeCoverageScale * 1.5 ||
        !_edgeCoverage.contains(viewport.topLeft) ||
        !_edgeCoverage.contains(viewport.bottomRight)) {
      _edgeCoverage = viewport.inflate(96 / scale);
      _edgeCoverageScale = scale;
      _visibleRouteRevision = _connectionGeometry.value;
      final ids = _edgeIndex.intersecting(_edgeCoverage).toList()
        ..sort(
          (first, second) =>
              _edgeLayers[first]!.compareTo(_edgeLayers[second]!),
        );
      _visibleRoutes = {for (final id in ids) id: _connectionRoutes[id]!};
    }
    return _visibleRoutes;
  }

  String? _edgeAt(Offset point) {
    final tolerance =
        8 /
        _transform.value
            .entry(0, 0)
            .abs()
            .clamp(taskCanvasMinScale, taskCanvasMaxScale);
    final area = Rect.fromCircle(center: point, radius: tolerance);
    String? front;
    for (final id in _edgeIndex.intersecting(area)) {
      if ((front == null || _edgeLayers[id]! > _edgeLayers[front]!) &&
          _connectionRoutes[id]!.hitTest(point, tolerance: tolerance)) {
        front = id;
      }
    }
    return front;
  }

  void _backgroundTap(AiWorkspaceProvider workspaces, Offset point) {
    final edge = _edgeAt(point);
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
      _movedNodes.addAll(_positions);
      _edit(workspaces, () => workspaces.disconnectConnections(targets));
      setState(() => _selectedEdges.clear());
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

  String? get _shortcutHints {
    final hints = [
      if (_controlHints) context.l10n.agentTopologyControlHints,
      if (_shiftHints) context.l10n.agentTopologyShiftHints,
      if (_spaceHints) context.l10n.agentTopologySpaceHints,
    ];
    return hints.isEmpty ? null : hints.join('  ·  ');
  }

  bool get _canvasOwnsKeyboard =>
      _openId == null && _canvasFocus.hasPrimaryFocus;

  void _watchShiftRelease(bool shift) {
    if (!shift || kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      _shiftReleaseCheck?.cancel();
      _shiftReleaseCheck = null;
      return;
    }
    _shiftReleaseCheck ??= Timer(const Duration(milliseconds: 80), () async {
      final check = _shiftReleaseCheck;
      final pressed = await _windowFocusChannel.invokeMethod<bool>(
        'isPhysicalShiftDown',
      );
      if (check != _shiftReleaseCheck) return;
      _shiftReleaseCheck = null;
      if (pressed == null) return;
      _ignoreStaleShift = !pressed;
      _updateShortcutHints();
    });
  }

  void _updateShortcutHints() {
    final keyboard = HardwareKeyboard.instance;
    final active = _canvasOwnsKeyboard;
    final control = active && _canvasShortcutModifierPressed;
    final shift = active && _canvasShiftPressed;
    final space =
        active && keyboard.isLogicalKeyPressed(LogicalKeyboardKey.space);
    _watchShiftRelease(shift);
    if (_controlHints == control &&
        _shiftHints == shift &&
        _spaceHints == space) {
      return;
    }
    setState(() {
      _controlHints = control;
      _shiftHints = shift;
      _spaceHints = space;
    });
  }

  void _selectAll(AiWorkspaceProvider workspaces) {
    setState(() {
      _selectedEdges
        ..clear()
        ..addAll(workspaces.connections.map((connection) => connection.id));
      _selectedIds
        ..clear()
        ..addAll(workspaces.sessions.map((item) => item.id));
    });
  }

  KeyEventResult _canvasKey(AiWorkspaceProvider workspaces, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight) {
      _watchShiftRelease(false);
      if (!event.synthesized || !HardwareKeyboard.instance.isShiftPressed) {
        _ignoreStaleShift = false;
      }
    }
    _updateShortcutHints();
    final shortcutModifier = _canvasShortcutModifierPressed;
    final shortcut =
        shortcutModifier &&
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
            event.logicalKey == LogicalKeyboardKey.space)) {
      _closeCanvasMenus();
    }
    if (!_canvasOwnsKeyboard) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (shortcutModifier && event.logicalKey == LogicalKeyboardKey.keyA) {
      _selectAll(workspaces);
      return KeyEventResult.handled;
    }
    if (shortcutModifier) {
      if (event.logicalKey == LogicalKeyboardKey.keyZ ||
          event.logicalKey == LogicalKeyboardKey.keyY) {
        if (event is KeyDownEvent) {
          _historyStep(
            workspaces,
            redo:
                event.logicalKey == LogicalKeyboardKey.keyY ||
                _canvasShiftPressed,
          );
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        if (event is KeyDownEvent) {
          _copySelectedCards(workspaces);
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        if (event is KeyDownEvent) {
          _pasteSelectedCards(workspaces);
        }
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
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
      // 空白处单击沿用框选的指针处理流程完成。
      // 不能依赖框选浮层重建后仍然存活的点击识别器。
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
      _movedNodes.addAll(_positions);
      _edit(workspaces, () => workspaces.connectCanvasTasks(fromId, toId));
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

  Offset _portAnchor(Size size, String side) => switch (side) {
    'in' => Offset(1, size.height / 2),
    'out' => Offset(size.width - 1, size.height / 2),
    'top' => Offset(size.width / 2, 1),
    _ => Offset(size.width / 2, size.height - 1),
  };

  void _startConnection(String id, Offset at) {
    _viewMotion.stop();
    _canvasFocus.requestFocus();
    setState(() {
      _connectingSource = id;
      _connectingStart = _positions[id]! + at;
      _connectingEnd = _connectingStart;
      _connectionPointer.value = _connectingEnd;
    });
  }

  void _moveConnection(Offset globalPosition) {
    _connectingEnd = _scenePoint(globalPosition);
    _connectionPointer.value = _connectingEnd;
  }

  void _cancelConnection() => setState(() {
    _connectingSource = null;
    _connectingStart = null;
    _connectingEnd = null;
    _connectionPointer.value = null;
  });

  Widget _port(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
    AppTheme theme,
    String side, {
    required bool hovered,
  }) {
    final visible =
        hovered ||
        _selectedIds.contains(session.id) ||
        _connectingSource != null;
    final at = _portAnchor(_size(session.id), side);
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
          onPanStart: (_) => _startConnection(session.id, at),
          onPanUpdate: (details) => _moveConnection(details.globalPosition),
          onPanEnd: (_) => _finishConnection(workspaces),
          onPanCancel: _cancelConnection,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 150),
            tween: Tween(begin: visible ? 1 : .16, end: visible ? 1 : .16),
            builder: (context, opacity, child) => Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.primary.withValues(
                    alpha: theme.primary.a * opacity,
                  ),
                  border: Border.all(
                    color: theme.basePrimary.withValues(
                      alpha: theme.basePrimary.a * opacity,
                    ),
                    width: 1.5,
                  ),
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
    final wasEmpty = workspaces.sessions.isEmpty;
    await workspaces.main.initialized;
    if (!mounted) return;
    if (!workspaces.main.services.any(
      (service) =>
          workspaces.main.hasServiceKey(service.id) &&
          service.models.isNotEmpty,
    )) {
      final configure = await showAppConfirmation(
        context: context,
        theme: context.read<ThemeProvider>().themeData,
        actionKey: 'topology-model-service-required',
        title: context.l10n.aiCreateRequiresServiceTitle,
        description: context.l10n.aiCreateRequiresServiceDescription,
        confirmLabel: context.l10n.aiGoToModelSettings,
        constraints: const BoxConstraints(maxWidth: 420),
      );
      if (!mounted || !configure) return;
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
    if (session == null) return;
    _nodeSizes = _measureNodes(workspaces.sessions);
    if (parent == null) {
      final viewportCenter = _viewport.isEmpty
          ? _placementPoint()
          : _transform.toScene(_viewport.center(Offset.zero));
      final topLeft = viewportCenter - _size(session.id).center(Offset.zero);
      _movedNodes.addAll(_positions);
      setState(() {
        _placeNodes({session.id: Offset.zero}, topLeft);
        if (wasEmpty) {
          _sceneOrigin.value =
              _positions[session.id]! + _size(session.id).center(Offset.zero);
        }
      });
      workspaces.updateCanvasPositions({
        for (final entry in _positions.entries)
          entry.key: [entry.value.dx, entry.value.dy],
      }, origin: _sceneOrigin.value);
    }
    _open(workspaces, session);
  }

  void _delete(
    AiWorkspaceProvider workspaces, {
    AiAgentWorkspace? target,
    Set<String>? targets,
    Set<String>? edgeTargets,
  }) {
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
    _endNodeDrag(workspaces);
    _edit(workspaces, () {
      workspaces.removeMany(ids);
      workspaces.disconnectConnections(edges);
    });
    setState(() {
      _selectedIds.removeAll(ids);
      _selectedEdges.clear();
    });
  }

  Future<void> _makeRoot(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) async {
    if (!mounted || workspaces.find(session.id) != session) {
      return;
    }
    _movedNodes.addAll(_positions);
    _edit(workspaces, () => workspaces.promoteToRoot(session.id));
  }

  void _makeWorkflowMain(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) {
    if (!mounted || !workspaces.canMakeWorkflowMain(session.id)) return;
    _movedNodes.addAll(_positions);
    _edit(workspaces, () => workspaces.makeWorkflowMain(session.id));
  }

  Iterable<AiAgentWorkspace> _parentCandidates(
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
  });

  Future<void> _makeChild(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) async {
    final candidates = _parentCandidates(workspaces, session).toList();
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
                            '${candidate.id} · ${candidate.title}',
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

  Offset _placementPoint() => _transform.toScene(
    _canvasPointer ?? Offset(_viewport.width / 2, _viewport.height / 2),
  );

  /// 整组平移，保留节点间的相对位置；负坐标通过调整原点保持可点击。
  void _placeNodes(Map<String, Offset> nodes, Offset anchor) {
    if (nodes.isEmpty) return;
    final origin = Offset(
      nodes.values.map((p) => p.dx).reduce(math.min),
      nodes.values.map((p) => p.dy).reduce(math.min),
    );
    for (final entry in nodes.entries) {
      _movedNodes[entry.key] = entry.value - origin + anchor;
    }
    _positions = {..._positions, ..._movedNodes};
    final left = _positions.values.map((p) => p.dx).reduce(math.min);
    final top = _positions.values.map((p) => p.dy).reduce(math.min);
    final shift = Offset(
      left < 24 ? ((240 - left) / 24).ceil() * 24.0 : 0,
      top < 24 ? ((240 - top) / 24).ceil() * 24.0 : 0,
    );
    if (shift != Offset.zero) {
      _positions = {
        for (final entry in _positions.entries) entry.key: entry.value + shift,
      };
      _movedNodes.addAll(_positions);
      _rebaseView(shift);
    }
  }

  Future<void> _importAtPointer(
    AiWorkspaceProvider workspaces,
    AppTheme theme,
  ) async {
    _importPlacement = _transform.toScene(
      _menuPointer ?? _canvasPointer ?? _viewport.center(Offset.zero),
    );
    final revision = workspaces.importRevision;
    try {
      await runDirectAgentTransfer(
        context,
        theme,
        '',
        'import-agents',
        onImportCommitting: (committing) {
          if (mounted && _importCommitting != committing) {
            setState(() => _importCommitting = committing);
          }
        },
      );
    } finally {
      if (workspaces.importRevision == revision) _importPlacement = null;
    }
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
    setState(() {
      _cardClipboardToken = token;
    });
  }

  Future<void> _pasteSelectedCards(
    AiWorkspaceProvider workspaces, {
    bool fromMenu = false,
  }) async {
    if (_pastingCards || _copiedCards.isEmpty) return;
    _pastingCards = true;
    final pointer =
        (fromMenu ? _menuPointer : null) ??
        _canvasPointer ??
        _viewport.center(Offset.zero);
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted ||
          (!fromMenu && !_canvasFocus.hasPrimaryFocus) ||
          _openId != null ||
          clipboard?.text != _cardClipboardToken) {
        return;
      }
      final cards = _copiedCards;
      final positions = _copiedPositions;
      final topLeft = Offset(
        positions.values.map((p) => p.dx).reduce(math.min),
        positions.values.map((p) => p.dy).reduce(math.min),
      );
      _movedNodes.addAll(_positions);
      final before = _captureEdit(workspaces);
      late final List<AiAgentWorkspace> copies;
      try {
        copies = await workspaces.pasteCards(
          cards,
          titleForCopy: _copyTitle,
          positionForCopy: (id) =>
              _transform.toScene(pointer) + (positions[id]! - topLeft),
        );
        if (!mounted) {
          _releaseFrame(before);
          return;
        }
        _canvasFocus.requestFocus();
        if (_lastCount == 0) _lastCount = workspaces.sessions.length;
        _movedNodes.addAll(_positions);
        setState(() {
          _placeNodes({
            for (var index = 0; index < copies.length; index++)
              copies[index].id: positions[cards[index].sourceId]!,
          }, _transform.toScene(pointer));
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

  List<RightClickMenuItem> _nodeMenuItems(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
    AppTheme theme,
    Set<String> connectedIds,
    ({bool hasStop, bool hasDisconnect}) selectedActions,
    VoidCallback closeMenu,
  ) {
    final l10n = context.l10n;
    final canMakeMain =
        session.kind != AiWorkspaceKind.primary &&
        workspaces.canMakeWorkflowMain(session.id);
    final selected = _selectedIds.contains(session.id);
    final targetIds = selected ? _selectedIds : {session.id};
    final multipleTargets = targetIds.length > 1;
    final hasStop = selected ? selectedActions.hasStop : session.busy;
    final hasDisconnect = selected
        ? selectedActions.hasDisconnect
        : connectedIds.contains(session.id);
    final connectTarget = targetIds.length == 2
        ? targetIds.where((id) => id != session.id).firstOrNull
        : null;
    final canConnect =
        connectTarget != null &&
        !workspaces.isConnected(session.id, connectTarget);
    final hasParentCandidate =
        !multipleTargets && _parentCandidates(workspaces, session).isNotEmpty;
    return [
      if (!multipleTargets)
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
        label: multipleTargets
            ? l10n.aiTopologyCopyWorkflow
            : l10n.aiTopologyDuplicate,
        icon: Symbols.content_copy_rounded,
        onTap: () {
          closeMenu();
          _copySelectedCards(workspaces);
        },
      ),
      if (!multipleTargets)
        RightClickMenuItem(
          key: const ValueKey('topology-context-paste'),
          label: _copiedCards.length > 1
              ? l10n.aiTopologyPasteWorkflow
              : l10n.aiTopologyPasteAgent,
          icon: Symbols.content_paste_rounded,
          isEnabled: _copiedCards.isNotEmpty && !_pastingCards,
          onTap: _copiedCards.isEmpty || _pastingCards
              ? null
              : () {
                  closeMenu();
                  _pasteSelectedCards(workspaces, fromMenu: true);
                },
        ),
      if (!multipleTargets)
        RightClickMenuItem(
          key: const ValueKey('topology-context-copy-id'),
          label: l10n.aiTopologyCopyId,
          icon: Symbols.content_copy_rounded,
          onTap: () async {
            closeMenu();
            await Clipboard.setData(ClipboardData(text: session.id));
          },
        ),
      if (multipleTargets)
        RightClickMenuItem(
          key: const ValueKey('topology-context-export-workflow'),
          label: l10n.agentStorageExportWorkflow,
          icon: Symbols.archive,
          onTap: () {
            final exportIds = Set<String>.of(targetIds);
            closeMenu();
            showAgentStorage(
              context,
              theme,
              '',
              action: 'workflow',
              selectedIds: exportIds,
            );
          },
        )
      else
        RightClickMenuItem(
          key: const ValueKey('topology-context-storage'),
          label: l10n.agentStorageTitle,
          icon: Symbols.memory,
          children: [
            RightClickMenuItem(
              label: l10n.agentStorageManage,
              icon: Symbols.memory,
              onTap: () {
                closeMenu();
                showAgentStorage(context, theme, session.id);
              },
            ),
            RightClickMenuItem(
              key: const ValueKey('topology-context-manage-chat'),
              label: l10n.agentStorageManageContext,
              icon: Symbols.chat_rounded,
              onTap: () {
                closeMenu();
                showAgentContextStorage(context, theme, session.id);
              },
            ),
            RightClickMenuItem(
              label: l10n.agentStorageImportMemory,
              icon: Symbols.file_open,
              onTap: () {
                closeMenu();
                showAgentStorage(context, theme, session.id, action: 'import');
              },
            ),
            RightClickMenuItem(
              label: l10n.agentStorageExportMemory,
              icon: Symbols.file_save,
              onTap: () {
                closeMenu();
                showAgentStorage(context, theme, session.id, action: 'memory');
              },
            ),
            RightClickMenuItem(
              key: const ValueKey('topology-context-export-chat'),
              label: l10n.agentStorageExportChat,
              icon: Symbols.file_save,
              onTap: () {
                closeMenu();
                showAgentStorage(context, theme, session.id, action: 'chat');
              },
            ),
            RightClickMenuItem(
              label: l10n.agentStorageExportAgent,
              icon: Symbols.archive,
              onTap: () {
                closeMenu();
                showAgentStorage(context, theme, session.id, action: 'agent');
              },
            ),
          ],
        ),
      if (!multipleTargets)
        RightClickMenuItem(
          key: const ValueKey('topology-context-rename'),
          label: l10n.aiTopologyRename,
          icon: Symbols.edit_rounded,
          onTap: () {
            closeMenu();
            _rename(workspaces, session);
          },
        ),
      if (!multipleTargets)
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
      if (!multipleTargets)
        RightClickMenuItem(
          key: const ValueKey('topology-context-workflow'),
          label: l10n.aiTopologyWorkflowActions,
          icon: Symbols.account_tree_rounded,
          showDivider: !hasStop && !hasDisconnect,
          children: [
            RightClickMenuItem(
              key: const ValueKey('topology-context-create'),
              label: l10n.aiTopologyCreateChild,
              icon: Symbols.account_tree_rounded,
              onTap: () {
                closeMenu();
                _create(workspaces, parent: session);
              },
            ),
            if (canMakeMain)
              RightClickMenuItem(
                key: const ValueKey('topology-context-make-workflow-main'),
                label: l10n.aiTopologyMakeWorkflowMain,
                icon: Symbols.hub_rounded,
                onTap: () {
                  closeMenu();
                  _makeWorkflowMain(workspaces, session);
                },
              ),
            if (session.kind != AiWorkspaceKind.primary)
              RightClickMenuItem(
                key: const ValueKey('topology-context-make-root'),
                label: l10n.aiTopologyMakeRoot,
                icon: Symbols.hub_rounded,
                onTap: () {
                  closeMenu();
                  _makeRoot(workspaces, session);
                },
              ),
            if (hasParentCandidate)
              RightClickMenuItem(
                key: const ValueKey('topology-context-make-child'),
                label: l10n.aiTopologyMakeChild,
                icon: Symbols.subdirectory_arrow_right_rounded,
                onTap: () {
                  closeMenu();
                  _makeChild(workspaces, session);
                },
              ),
          ],
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
    ];
  }

  Widget _nodeContextMenu(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
    AppTheme theme,
    Widget child,
    Set<String> connectedIds,
    ({bool hasStop, bool hasDisconnect}) selectedActions,
  ) => RightClickMenuBuilder.buildMenuAnchor(
    context: context,
    fitWidthToItems: true,
    fitHeightToWindow: true,
    onMenuPointerEvent: _menuPointerEvent,
    controller: _nodeMenus.putIfAbsent(
      session.id,
      RightClickMenuController.new,
    ),
    theme: theme,
    onSecondaryTap: () {
      _openNodeMenuId = session.id;
      _viewMotion.stop();
      _selectNode(workspaces, session, contextMenu: true);
    },
    menuItemsBuilder: () => _nodeMenuItems(
      workspaces,
      session,
      theme,
      connectedIds,
      selectedActions,
      () => _nodeMenus[session.id]?.close(),
    ),
    child: child,
  );

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

  List<Object> _layoutSignature = const [];
  Map<String, Offset> _automaticPositions = const {};
  String? _defaultOriginAnchorId;

  Map<String, Offset> _layout(
    List<AiAgentWorkspace> sessions, {
    bool incremental = true,
  }) {
    final workspace = context.read<AiWorkspaceProvider>();
    final placed = <String, Offset>{};
    var hasValidStoredPosition = false;
    for (final session in sessions) {
      final id = session.id;
      final stored = workspace.canvasPositions[id];
      if (stored != null &&
          stored.length >= 2 &&
          stored[0].isFinite &&
          stored[1].isFinite) {
        hasValidStoredPosition = true;
      }
      if (_restoredPositionIds.add(id)) {
        if (workspace.canvasPositions[id] case [final x, final y]
            when x.isFinite && y.isFinite) {
          _movedNodes.putIfAbsent(id, () => Offset(x, y));
        }
      }
      if (_movedNodes[id] case final position?) placed[id] = position;
    }
    if (placed.length == sessions.length) return placed;
    if (incremental &&
        _lastImportRevision == workspace.importRevision &&
        sessions.any(
          (session) =>
              session.parentId != null &&
              !placed.containsKey(session.id) &&
              !_positions.containsKey(session.id),
        )) {
      final anchors = {
        for (final session in sessions)
          session.id: ?(placed[session.id] ?? _positions[session.id]),
      };
      final additions = placeNewTaskChildren(
        sessions: sessions,
        anchors: anchors,
        sizeOf: _size,
      );
      if (additions.isNotEmpty) {
        placed
          ..addAll(anchors)
          ..addAll(additions);
        _movedNodes.addAll(placed);
        workspace.updateCanvasPositions({
          ...workspace.canvasPositions,
          for (final entry in placed.entries)
            entry.key: [entry.value.dx, entry.value.dy],
        }, origin: _sceneOrigin.value);
        if (placed.length == sessions.length) return placed;
      }
    }
    final connections = workspace.connections;
    final signature = <Object>[
      for (final session in sessions)
        (session.id, session.parentId, session.kind, _size(session.id)),
      for (final edge in connections)
        (edge.id, edge.fromId, edge.toId, edge.isHierarchy),
    ];
    if (!listEquals(signature, _layoutSignature)) {
      _layoutSignature = signature;
      var automatic = layoutTaskTopology(
        sessions: sessions,
        nodeSizes: {
          for (final session in sessions) session.id: _size(session.id),
        },
        connections: connections,
      );
      // A new workspace has no persisted scene coordinates. Keep the first
      // primary card centered on the world origin, then lay out its children
      // relative to that anchor. Persisted positions always take precedence.
      if (!hasValidStoredPosition &&
          _movedNodes.isEmpty &&
          _automaticPositions.isEmpty &&
          automatic.isNotEmpty) {
        final anchor = sessions.firstWhere(
          (session) => session.kind == AiWorkspaceKind.primary,
          orElse: () => sessions.first,
        );
        final anchorPosition = automatic[anchor.id];
        if (anchorPosition != null) {
          _defaultOriginAnchorId = anchor.id;
          final origin = anchorPosition + _size(anchor.id).center(Offset.zero);
          if (_sceneOrigin.value != origin) {
            _sceneOrigin.value = origin;
            workspace.updateCanvasPositions(
              workspace.canvasPositions,
              origin: origin,
            );
          }
        }
      }
      _automaticPositions = automatic;
    }
    return {..._automaticPositions, ...placed};
  }

  void _fit({bool animate = false, bool initial = false}) {
    if (_viewport.isEmpty) return;
    _wheelPanAcceleration.reset();
    _wheelZoomTargetScale = null;
    _wheelPanTarget = null;
    _viewMotion.stop();
    Rect bounds;
    if (_positions.isEmpty) {
      bounds = Offset.zero & _nodeSize;
      final origin = bounds.center;
      if (_sceneOrigin.value != origin) {
        _sceneOrigin.value = origin;
        final workspace = _navigationWorkspace;
        if (workspace != null && workspace.canvasOrigin != origin) {
          workspace.updateCanvasPositions(
            workspace.canvasPositions,
            origin: origin,
          );
        }
      }
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
        .clamp(taskCanvasMinScale, 1.0);
    var center = bounds.center;
    if (initial && _positions.length == 1) {
      final anchorId = _defaultOriginAnchorId;
      final anchor = anchorId == null ? null : _positions[anchorId];
      if (anchor != null && anchorId != null) {
        center = anchor + _size(anchorId).center(Offset.zero);
      }
    }
    if (initial &&
        scale == taskCanvasMinScale &&
        _positions.isNotEmpty &&
        _nodeIndex
            .intersecting(
              Rect.fromCenter(
                center: center,
                width: _viewport.width / scale,
                height: _viewport.height / scale,
              ),
            )
            .isEmpty) {
      center = _nodeIndex[_positions.keys.first]!.center;
    }
    final target = _centerView(center, scale);
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _transform.value = target;
      return;
    }
    _animateViewTo(target, Curves.easeInOut);
  }

  Matrix4 _centerView(Offset sceneCenter, double scale) {
    final translation = _viewport.center(Offset.zero) - sceneCenter * scale;
    return Matrix4.translationValues(translation.dx, translation.dy, 0) *
        Matrix4.diagonal3Values(scale, scale, 1);
  }

  void _saveViewport() {
    if (_initializeViewport || _fitOnLayout || _viewport.isEmpty) {
      return;
    }
    final matrix = _transform.value;
    final scale = matrix.entry(0, 0);
    if (!scale.isFinite || scale <= 0) return;
    final translation = Offset(matrix.entry(0, 3), matrix.entry(1, 3));
    final center =
        (_viewport.center(Offset.zero) - translation) / scale -
        _sceneOrigin.value;
    if (!center.isFinite) return;
    _hasSavedViewport = true;
    _navigationWorkspace!.main.workspacePreferences.setValue(
      _viewportPreference,
      jsonEncode([scale, center.dx, center.dy]),
      notify: false,
    );
  }

  bool _restoreViewport(AiWorkspaceProvider workspaces) {
    final saved = workspaces.main.workspacePreferences.stringValue(
      _viewportPreference,
      '',
    );
    if (saved.isEmpty) return false;
    try {
      if (jsonDecode(saved) case [final num zoom, final num x, final num y]) {
        if (!zoom.isFinite || zoom <= 0) return false;
        final scale = zoom.toDouble().clamp(
          taskCanvasMinScale,
          taskCanvasMaxScale,
        );
        final center = Offset(x.toDouble(), y.toDouble()) + _sceneOrigin.value;
        if (!(center * scale).isFinite) return false;
        _transform.value = _centerView(center, scale);
        return true;
      }
    } on FormatException {
      return false;
    }
    return false;
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
    _wheelPanAcceleration.reset();
    final currentScale = _transform.value.entry(0, 0).abs();
    final direction = factor.compareTo(1);
    final baseScale =
        accumulateWheel &&
            _viewMotion.isAnimating &&
            _wheelZoomDirection == direction
        ? _wheelZoomTargetScale ?? currentScale
        : currentScale;
    final scale = (baseScale * factor).clamp(
      taskCanvasMinScale,
      taskCanvasMaxScale,
    );
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
      _animateViewTo(
        target,
        accumulateWheel ? Curves.easeOut : Curves.easeInOut,
      );
    } else {
      _transform.value = target;
    }
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
      _animateViewTo(target, Curves.easeOut);
    }
  }

  Widget _canvasLoading(AppTheme theme, String label, {double? progress}) {
    final percentage = progress == null ? null : '${(progress * 100).floor()}%';
    return SizedBox(
      width: 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            key: const ValueKey('topology-loading-progress'),
            value: progress,
            semanticsLabel: label,
            semanticsValue: percentage,
          ),
          if (percentage != null) ...[
            const SizedBox(height: 8),
            Text(
              percentage,
              key: const ValueKey('topology-loading-percentage'),
              style: TextStyle(fontSize: 12, color: theme.textColorSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _prepareColdCanvas(List<AiAgentWorkspace> sessions, AppTheme theme) {
    if (sessions.length - math.max(0, _lastCount) < 512) return null;
    _measureNodes(const []);
    final pending = [
      for (final session in sessions)
        if (_measuredNodes[session.id]?.$1 !=
            (session.title, session.assistant.roleplayBinding != null))
          session,
    ];
    if (pending.isEmpty) return null;

    var next = 0;
    return StatefulBuilder(
      key: ObjectKey(pending),
      builder: (loadingContext, refresh) {
        if (TickerMode.valuesOf(loadingContext).enabled) {
          final budget = Stopwatch()..start();
          Iterable<AiAgentWorkspace> batch() sync* {
            final end = math.min(next + 256, pending.length);
            while (next < end) {
              yield pending[next++];
              if (budget.elapsedMicroseconds >= 4000) break;
            }
          }

          _measureNodes(batch());
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!loadingContext.mounted) return;
            if (next == pending.length) {
              setState(() {});
            } else {
              refresh(() {});
            }
          });
        }
        final measuredCount = sessions.length - pending.length + next;
        return ColoredBox(
          color: theme.secondary,
          child: Center(
            child: _canvasLoading(
              theme,
              loadingContext.l10n.aiTopologyLoading,
              progress: measuredCount / sessions.length,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final workspaces = context.watch<AiWorkspaceProvider>();
    if (workspaces.pendingRecycleRestore != null) {
      return _workspacePages(
        theme,
        workspaces,
        Center(
          child: _canvasLoading(theme, context.l10n.agentRecycleRestoring),
        ),
      );
    }
    if (_importCommitting) {
      return ColoredBox(
        color: theme.secondary,
        child: Center(
          child: _canvasLoading(
            theme,
            context.l10n.agentStorageTransferCommitting,
          ),
        ),
      );
    }
    if (workspaces.isRestoring ||
        (workspaces.restoreFailed && workspaces.sessions.isEmpty)) {
      return ColoredBox(
        color: theme.secondary,
        child: Center(
          child: workspaces.isRestoring
              ? ValueListenableBuilder<double?>(
                  valueListenable: workspaces.restoreProgress,
                  builder: (context, progress, _) => _canvasLoading(
                    theme,
                    progress == null
                        ? context.l10n.aiTopologyLoading
                        : context.l10n.aiTopologyRestoring,
                    progress: progress,
                  ),
                )
              : Text(context.l10n.aiTopologyRestoreFailed),
        ),
      );
    }
    if (_recycleRevision != workspaces.recycleRevision) {
      _recycleRevision = workspaces.recycleRevision;
      _clearEdits(_undoEdits);
      _clearEdits(_redoEdits);
    }
    if (!identical(_navigationWorkspace, workspaces)) {
      if (_navigationWorkspace?.layoutCanvasGroup == _layoutCanvasGroup) {
        _navigationWorkspace?.layoutCanvasGroup = null;
      }
      _navigationWorkspace?.activeConversationId = null;
      _navigationWorkspace = workspaces;
      _initializeViewport = true;
      _hasSavedViewport = false;
      _sceneOrigin.value = workspaces.canvasOrigin;
      _lastCount = -1;
      _layoutSignature = const [];
      _automaticPositions = const {};
      _defaultOriginAnchorId = null;
      workspaces.layoutCanvasGroup = _layoutCanvasGroup;
      _lastNavigationRevision = workspaces.navigationRequest?.revision ?? 0;
    }
    final request = workspaces.navigationRequest;
    if (request != null && request.revision > _lastNavigationRevision) {
      _lastNavigationRevision = request.revision;
      if (_pageActive && _openId != null && request.sourceId == _openId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              identical(_navigationWorkspace, workspaces) &&
              _pageActive &&
              _openId == request.sourceId) {
            _openLinkedTask(workspaces, request.targetId);
          }
        });
      }
    }
    final sessions = workspaces.sessions;
    if (_prepareColdCanvas(sessions, theme) case final loading?) {
      return _workspacePages(theme, workspaces, loading);
    }
    final sessionIds = sessions.map((session) => session.id).toSet();
    final dragInterrupted = _dragStarts.keys.any(
      (id) => !sessionIds.contains(id),
    );
    if (dragInterrupted) _endNodeDrag(workspaces, recordEdit: false);
    if (_dragPreview.all && _dragStarts.length != sessions.length) {
      _dragPreview.all = false;
      _dragPreview.partial.value = _dragPreview.value;
    }
    _measuredNodes.removeWhere((id, _) => !sessionIds.contains(id));
    _nodeCards.removeWhere((id, _) => !sessionIds.contains(id));
    _nodePositions.removeWhere((id, position) {
      if (sessionIds.contains(id)) return false;
      position.dispose();
      return true;
    });
    _selectedIds.removeWhere((id) => workspaces.find(id) == null);
    final connectionIds = workspaces.connections
        .map((connection) => connection.id)
        .toSet();
    _selectedEdges.removeWhere((id) => !connectionIds.contains(id));
    final visibleSessions = sessions.toList();
    final sizes = _measureNodes(visibleSessions);
    if (_nodeSizes.entries.any(
      (entry) =>
          sizes.containsKey(entry.key) && sizes[entry.key] != entry.value,
    )) {
      // 重命名只在原位置调整卡片尺寸，重新排列仍由用户明确触发。
      _movedNodes.addAll(_positions);
    }
    _nodeSizes = sizes;
    if (_dragPreview.starts.isNotEmpty && !_dragPreview.all) {
      _dragEdgeMargin = _maxNodeSide();
    }
    _positions = _layout(visibleSessions);
    final imported = _lastImportRevision != workspaces.importRevision;
    if (imported) {
      _lastImportRevision = workspaces.importRevision;
      final nodes = {
        for (final id in workspaces.importedAgentIds) id: ?_positions[id],
      };
      if (nodes.isNotEmpty) {
        _movedNodes.addAll(_positions);
        _placeNodes(nodes, _importPlacement ?? _placementPoint());
        _importPlacement = null;
        _selectedIds
          ..clear()
          ..addAll(nodes.keys);
        _selectedEdges.clear();
        final positions = {
          for (final entry in _positions.entries)
            entry.key: [entry.value.dx, entry.value.dy],
        };
        final origin = _sceneOrigin.value;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            workspaces.updateCanvasPositions(positions, origin: origin);
          }
        });
      }
    }
    _syncSceneGeometry();
    _updateConnectionRoutes(workspaces);
    if (dragInterrupted) {
      final positions = {
        for (final entry in _positions.entries)
          entry.key: [entry.value.dx, entry.value.dy],
      };
      final origin = _sceneOrigin.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          workspaces.updateCanvasPositions(positions, origin: origin);
        }
      });
    }
    if (visibleSessions.length != _lastCount) {
      final firstTasks = _lastCount <= 0 && visibleSessions.isNotEmpty;
      _lastCount = visibleSessions.length;
      if (visibleSessions.isEmpty ||
          (firstTasks && !imported && !_pastingCards && !_hasSavedViewport)) {
        _fitOnLayout = true;
      }
    }
    if (_openId != null && workspaces.find(_openId) == null) _openId = null;
    _visitedChats.removeWhere((id) => !sessionIds.contains(id));
    return _workspacePages(theme, workspaces, _graph(theme, workspaces));
  }

  Widget _workspacePages(
    AppTheme theme,
    AiWorkspaceProvider workspaces,
    Widget graph,
  ) {
    final content = ColoredBox(
      color: theme.secondary,
      child: RetainedPageStack(
        activeKey: _openId ?? _graphKey,
        pages: {
          _graphKey: graph,
          for (final id in _visitedChats)
            if (workspaces.find(id) case final session?)
              session.id: ChangeNotifierProvider<AiAssistantProvider>.value(
                // 主智能体移除或节点提升会改变 IndexedStack 的索引，按会话身份保留草稿。
                key: GlobalObjectKey(session.assistant),
                value: session.assistant,
                child: TaskNavigationScope(
                  openTask: (id) => _openLinkedTask(workspaces, id),
                  child: _TopologyConversation(
                    key: ValueKey('topology-chat-${session.id}'),
                    session: session,
                    onRename: () => _rename(workspaces, session),
                    onChooseOpening: (binding) => _chooseRoleplayOpening(
                      workspaces,
                      session,
                      theme,
                      binding,
                    ),
                    onBack: () => _backToConversation(workspaces),
                  ),
                ),
              ),
        },
      ),
    );
    return AppTooltipScope(
      child: Builder(
        builder: (context) {
          _pageActive =
              TickerMode.valuesOf(context).enabled &&
              (ModalRoute.isCurrentOf(context) ?? true);
          workspaces.activeConversationId = _pageActive ? _openId : null;
          return content;
        },
      ),
    );
  }

  Rect _backgroundInView() {
    final scale = _transform.value.entry(0, 0).abs();
    final viewport = Rect.fromPoints(
      _transform.toScene(Offset.zero),
      _transform.toScene(_viewport.bottomRight(Offset.zero)),
    );
    if (_backgroundScale != scale ||
        !_backgroundCoverage.contains(viewport.topLeft) ||
        !_backgroundCoverage.contains(viewport.bottomRight)) {
      _backgroundScale = scale;
      _backgroundCoverage = viewport.inflate(96 / scale);
    }
    return _backgroundCoverage;
  }

  Widget _sceneBackground(AppTheme theme, AiWorkspaceProvider workspaces) {
    final selected = Set.of(_selectedEdges);
    return ListenableBuilder(
      listenable: Listenable.merge([
        _transform,
        workspaces.transfers,
        _connectionGeometry,
        _dragPreview,
      ]),
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _TopologyBackgroundPainter(
                pattern: _backgroundPattern,
                canvasStyle: workspaces.canvasStyle,
                scale: _transform.value.entry(0, 0).abs(),
                backgroundBounds: _backgroundInView(),
                gridColor: theme.textColorTertiary.withValues(alpha: .28),
              ),
            ),
          ),
          Transform.translate(
            offset: _dragPreview.all ? _dragPreview.value : Offset.zero,
            child: TaskTopologyConnectionLayer(
              routes: _routesInView(),
              bounds: _connectionRoutes.length > 64 ? _edgeCoverage : null,
              revision: _connectionGeometry.value,
              scale: _transform.value.entry(0, 0).abs(),
              lineColor: theme.textColorTertiary.withValues(alpha: .48),
              accentColor: theme.basePrimary,
              selectedEdges: selected,
              activeEdges: {
                if (workspaces.transfers.value.isNotEmpty)
                  for (final edge in _routedConnections)
                    if (workspaces.transfers.value.any(
                      (item) =>
                          (item.fromId == edge.fromId &&
                              item.toId == edge.toId) ||
                          (item.fromId == edge.toId &&
                              item.toId == edge.fromId),
                    ))
                      edge.id,
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _canvasInteractions(
    AppTheme theme,
    AiWorkspaceProvider workspaces,
    Widget child,
    Set<String> connectedIds,
    ({bool hasStop, bool hasDisconnect}) selectedActions,
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
      fitWidthToItems: _overviewMenuId != null,
      fitHeightToWindow: true,
      theme: theme,
      onSecondaryTap: () {
        if (workspaces.find(_overviewMenuId) case final session?) {
          _viewMotion.stop();
          _selectNode(workspaces, session, contextMenu: true);
        } else if (_rightEdge == null) {
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
      menuItemsBuilder: () => switch (workspaces.find(_overviewMenuId)) {
        final session? => _nodeMenuItems(
          workspaces,
          session,
          theme,
          connectedIds,
          selectedActions,
          _canvasMenu.close,
        ),
        null => [
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
            RightClickMenuItem(
              key: const ValueKey('topology-canvas-paste'),
              label: _copiedCards.length > 1
                  ? l10n.aiTopologyPasteWorkflow
                  : l10n.aiTopologyPasteAgent,
              icon: Symbols.content_paste_rounded,
              isEnabled: _copiedCards.isNotEmpty && !_pastingCards,
              onTap: _copiedCards.isEmpty || _pastingCards
                  ? null
                  : () {
                      _canvasMenu.close();
                      _pasteSelectedCards(workspaces, fromMenu: true);
                    },
            ),
            action(
              'topology-canvas-import-agents',
              l10n.agentStorageImportAgents,
              Symbols.file_open_rounded,
              () => _importAtPointer(workspaces, theme),
              divider: sessions.isEmpty,
            ),
            if (sessions.isNotEmpty)
              action(
                'topology-canvas-select-all',
                l10n.cardSelectAll,
                Symbols.select_all,
                () => _selectAll(workspaces),
                divider: true,
              ),
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
              Symbols.grid_view_rounded,
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
      },
      child: Listener(
        key: _viewportKey,
        onPointerHover: (event) => _canvasPointer = event.localPosition,
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
                  _wheelPanAcceleration.apply(
                    _canvasShiftPressed
                        ? Offset(
                            -event.scrollDelta.dy - event.scrollDelta.dx,
                            0,
                          )
                        : -event.scrollDelta,
                    event.timeStamp,
                    continuing:
                        event.kind == PointerDeviceKind.mouse &&
                        _viewMotion.isAnimating &&
                        _wheelPanTarget != null,
                  ),
                );
              }
            });
          }
        },
        onPointerDown: (event) {
          _wheelPanAcceleration.reset();
          _canvasPointer = event.localPosition;
          if (event.buttons & kSecondaryMouseButton != 0) {
            if (_overviewMenuPointer != event.pointer) _overviewMenuId = null;
            _menuPointer = event.localPosition;
          }
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
          final onNode = _nodeIndex.containsPoint(point);
          if (event.buttons & kSecondaryMouseButton != 0) {
            _secondaryPointer = event.pointer;
            _secondaryDown = event.localPosition;
            setState(() {
              _rightEdge = onNode ? null : _edgeAt(point);
            });
            if (onNode && _overviewMenuId == null) {
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
          _canvasPointer = event.localPosition;
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
    Set<String> connectedIds,
    ({bool hasStop, bool hasDisconnect}) selectedActions, {
    bool overview = false,
  }) {
    if (overview) {
      final kind = _kind(context.l10n, session.kind);
      final status = _taskStatus(context, session).label;
      final model = session.assistant.selectedService?.name;
      final summary = '$kind · $status';
      return _nodeSurface(
        workspaces,
        session,
        overview: true,
        child: TaskTopologyOverviewCard(
          key: ValueKey('topology-node-${session.id}'),
          title: session.title,
          summary: summary,
          modelLabel: context.l10n.aiAgentModelServiceValue(
            model == null ? session.model : '$model · ${session.model}',
          ),
          idLabel: context.l10n.aiAgentIdValue(session.id),
          selected: _selectedIds.contains(session.id),
          showPorts:
              _selectedIds.contains(session.id) || _connectingSource != null,
          indicator: session.needsAttention
              ? theme.permissionWarningColor
              : session.busy
              ? theme.basePrimary
              : null,
          onOpen: () => _open(workspaces, session),
          onSelect: () => _selectNode(workspaces, session),
          theme: theme,
          cache: _overviewPaint,
        ),
      );
    }
    return _nodeContextMenu(
      workspaces,
      session,
      theme,
      _TaskNodeHover(
        builder: (hovered) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _nodeSurface(
                workspaces,
                session,
                child: _nodeCard(theme, workspaces, session),
              ),
            ),
            for (final side in ['in', 'out', 'top', 'bottom'])
              _port(workspaces, session, theme, side, hovered: hovered),
          ],
        ),
      ),
      connectedIds,
      selectedActions,
    );
  }

  Widget _nodeSurface(
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session, {
    required Widget child,
    bool overview = false,
  }) => Listener(
    onPointerDown: (event) {
      _nodePointerDown = event.position;
      _nodeGrabOffset = event.localPosition;
      _nodeDragged = false;
      _nodePrimaryDown = event.buttons & kPrimaryMouseButton != 0;
      if (overview && event.buttons & kSecondaryMouseButton != 0) {
        _overviewMenuId = session.id;
        _overviewMenuPointer = event.pointer;
      }
    },
    onPointerCancel: (_) {
      _nodePrimaryDown = false;
      _nodePointerDown = null;
      _lastTapId = null;
    },
    onPointerUp: (event) => _nodePointerUp(workspaces, session, event),
    child: GestureDetector(
      excludeFromSemantics: overview,
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: () {
        if (!HardwareKeyboard.instance.isLogicalKeyPressed(
          LogicalKeyboardKey.space,
        )) {
          final size = _size(session.id);
          if (overview &&
              Rect.fromLTWH(
                size.width - 38,
                size.height - 38,
                32,
                32,
              ).contains(_nodeGrabOffset)) {
            _open(workspaces, session);
            return;
          }
          _selectNode(workspaces, session);
        }
      },
      onPanDown: (_) => _viewMotion.stop(),
      onPanStart: (details) {
        if (overview) {
          final size = _size(session.id);
          for (final side in ['in', 'out', 'top', 'bottom']) {
            final at = _portAnchor(size, side);
            if (Rect.fromCenter(
              center: at,
              width: 24,
              height: 24,
            ).contains(_nodeGrabOffset)) {
              _nodeDragged = true;
              _startConnection(session.id, at);
              return;
            }
          }
        }
        _updateNodeDrag(workspaces, session, details.globalPosition);
      },
      onPanUpdate: (details) => overview && _connectingSource == session.id
          ? _moveConnection(details.globalPosition)
          : _updateNodeDrag(workspaces, session, details.globalPosition),
      onPanEnd: (_) => overview && _connectingSource == session.id
          ? _finishConnection(workspaces)
          : _endNodeDrag(workspaces),
      onPanCancel: () => overview && _connectingSource == session.id
          ? _cancelConnection()
          : _endNodeDrag(workspaces),
      child: child,
    ),
  );

  Widget _nodeCard(
    AppTheme theme,
    AiWorkspaceProvider workspaces,
    AiAgentWorkspace session,
  ) {
    final selected = _selectedIds.contains(session.id);
    final signature = (
      session,
      session.title,
      session.kind,
      session.assistant.roleplayBinding,
      session.model,
      session.serviceId,
      session.assistant.selectedService?.name,
      session.status,
      session.busy,
      session.needsAttention,
      _taskStatus(context, session),
      selected,
      theme,
    );
    final cached = _nodeCards[session.id];
    if (cached != null && cached.$1 == signature) return cached.$2;
    final card = RepaintBoundary(
      child: _TaskNode(
        session: session,
        selected: selected,
        onOpen: () => _open(workspaces, session),
        onRoleplayPointerUp: (_) => _nodePrimaryDown = false,
        onRoleplaySettings: () =>
            unawaited(_editRoleplaySettings(workspaces, session, theme)),
        theme: theme,
      ),
    );
    _nodeCards[session.id] = (signature, card);
    return card;
  }

  Widget _graph(AppTheme theme, AiWorkspaceProvider workspaces) {
    final l10n = context.l10n;
    final parent = _selectedIds.length == 1 ? _parentFor(workspaces) : null;
    final sessions = workspaces.sessions;
    final connectedIds = {
      for (final connection in workspaces.connections) ...[
        connection.fromId,
        connection.toId,
      ],
    };
    final selectedActions = (
      hasStop: _selectedIds.any((id) => workspaces.find(id)?.busy ?? false),
      hasDisconnect: _selectedIds.any(connectedIds.contains),
    );
    final layers = {
      for (final (index, session) in sessions.indexed) session.id: index,
      for (final (index, id) in _frontOrder.indexed)
        id: sessions.length + index,
    };
    Widget positionedNode(String id, {bool overview = false}) {
      final session = workspaces.find(id)!;
      final notifier = _nodePositions[id]!;
      return ListenableBuilder(
        key: ValueKey('topology-position-listener-$id'),
        listenable: Listenable.merge([notifier, _dragPreview.partial]),
        builder: (context, child) {
          final position =
              notifier.value +
              (_dragPreview.starts.containsKey(id)
                  ? _dragPreview.partial.value
                  : Offset.zero);
          return Positioned(
            key: ValueKey('topology-position-$id'),
            left: position.dx,
            top: position.dy,
            width: _size(id).width,
            height: _size(id).height,
            child: child!,
          );
        },
        child: IgnorePointer(
          ignoring: _boxStart != null,
          child: _nodeView(
            theme,
            workspaces,
            session,
            connectedIds,
            selectedActions,
            overview: overview,
          ),
        ),
      );
    }

    return Focus(
      focusNode: _canvasFocus,
      onFocusChange: (_) => _updateShortcutHints(),
      onKeyEvent: (_, event) => _canvasKey(workspaces, event),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!constraints.biggest.isEmpty &&
                    _viewport != constraints.biggest) {
                  _viewport = constraints.biggest;
                  if (!_initializeViewport && _hasSavedViewport) {
                    _saveViewport();
                  } else if (sessions.isEmpty) {
                    _fitOnLayout = true;
                  }
                }
                if ((_initializeViewport || _fitOnLayout) &&
                    !constraints.biggest.isEmpty) {
                  if (_initializeViewport && _restoreViewport(workspaces)) {
                    _hasSavedViewport = true;
                  } else {
                    _fit(initial: true);
                  }
                  _initializeViewport = false;
                  _fitOnLayout = false;
                  if (!_hasSavedViewport && sessions.isNotEmpty) {
                    _saveViewport();
                  }
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: TaskCanvasAxesPainter(
                              transform: _transform,
                              color: theme.textColorSecondary,
                              sceneOrigin: _sceneOrigin,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: _canvasInteractions(
                        theme,
                        workspaces,
                        ClipRect(
                          child: InteractiveViewer(
                            key: const ValueKey('task-topology-canvas'),
                            transformationController: _transform,
                            panEnabled: false,
                            // 滚轮缩放统一由画布监听器处理一次，
                            // 即使画布尚未获得焦点，也必须按住 Ctrl。
                            scaleEnabled: false,
                            constrained: false,
                            boundaryMargin: const EdgeInsets.all(
                              double.infinity,
                            ),
                            minScale: taskCanvasMinScale,
                            maxScale: taskCanvasMaxScale,
                            child: Semantics(
                              container: true,
                              child: ValueListenableBuilder<Size>(
                                valueListenable: _sceneExtent,
                                builder: (context, size, child) =>
                                    SizedBox.fromSize(
                                      key: _sceneKey,
                                      size: size,
                                      child: child,
                                    ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned.fill(
                                      child: _sceneBackground(
                                        theme,
                                        workspaces,
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: ListenableBuilder(
                                        listenable: Listenable.merge([
                                          _connectionGeometry,
                                          _dragPreview,
                                          workspaces.transfers,
                                        ]),
                                        builder: (context, _) =>
                                            Transform.translate(
                                              offset: _dragPreview.all
                                                  ? _dragPreview.value
                                                  : Offset.zero,
                                              child: AgentTransferLayer(
                                                transfers: workspaces.transfers,
                                                connections: _routedConnections,
                                                routes:
                                                    _dragPreview
                                                                .partial
                                                                .value !=
                                                            Offset.zero &&
                                                        workspaces
                                                            .transfers
                                                            .value
                                                            .isNotEmpty
                                                    ? _routesInView()
                                                    : _connectionRoutes,
                                                transform: _transform,
                                                color: theme.basePrimary,
                                              ),
                                            ),
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
                                        left: 0,
                                        top: 0,
                                        width: _nodeSize.width,
                                        child: IgnorePointer(
                                          ignoring: _boxStart != null,
                                          child: _CreatePrimaryTile(
                                            theme: theme,
                                            onPressed: () =>
                                                _create(workspaces),
                                          ),
                                        ),
                                      ),
                                    if (sessions.length > 64)
                                      Positioned.fill(
                                        child: TaskTopologyNodeLayer(
                                          index: _nodeIndex,
                                          geometry: _nodeGeometry,
                                          drag: _dragPreview,
                                          viewport: _viewport,
                                          transform: _transform,
                                          layers: layers,
                                          pinnedIds: () sync* {
                                            if (_dragAnchorId case final id?) {
                                              yield id;
                                            }
                                            if (_connectingSource
                                                case final id?) {
                                              yield id;
                                            }
                                            if (_openNodeMenuId case final id?
                                                when _nodeMenus[id]?.isOpen ==
                                                    true) {
                                              yield id;
                                            }
                                          },
                                          nodeBuilder: positionedNode,
                                          overviewNodeBuilder: (id) =>
                                              positionedNode(
                                                id,
                                                overview: true,
                                              ),
                                        ),
                                      ),
                                    if (sessions.length <= 64)
                                      for (final session
                                          in sessions.toList()..sort(
                                            (first, second) => layers[first.id]!
                                                .compareTo(layers[second.id]!),
                                          ))
                                        positionedNode(session.id),
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
                                                          color: theme
                                                              .basePrimary
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
                                                                      taskCanvasMinScale,
                                                                      taskCanvasMaxScale,
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
                        connectedIds,
                        selectedActions,
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: _graphHeader(theme, workspaces, parent),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 8,
                      child: Material(
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
                              _CanvasZoomPercentage(
                                transform: _transform,
                                theme: theme,
                                onZoom: _zoom,
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
                                  Symbols.grid_view_rounded,
                                  () => _autoLayout(sessions),
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
                    ),
                    if (_shortcutHints case final hint?)
                      Positioned(
                        left: 16,
                        right: 300,
                        bottom: 8,
                        child: IgnorePointer(
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: Material(
                                key: const ValueKey('topology-shortcut-hints'),
                                color: theme.primary.withValues(alpha: .92),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    hint,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.textColorPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
    final titleWidth =
        textWidth(l10n.aiTopologyTitle, _topologyHeaderTitleStyle) + 48;
    final title = IgnorePointer(
      child: DecoratedBox(
        key: const ValueKey('topology-canvas-title'),
        decoration: BoxDecoration(
          color: theme.primary,
          borderRadius: _topologyHeaderTitleRadius,
        ),
        child: Padding(
          padding: _topologyHeaderTitlePadding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.blur_on,
                size: 18,
                fill: 1,
                color: theme.textColorPrimary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  l10n.aiTopologyTitle,
                  style: _topologyHeaderTitleStyle.copyWith(
                    color: theme.textColorPrimary,
                  ),
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
                Symbols.hub_rounded,
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
        // 工具栏相对画布独立居中，不受标题宽度影响。
        // 窗口或字号变化时允许换到第二行，避免重叠。
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

class _TaskNodeHover extends StatefulWidget {
  const _TaskNodeHover({required this.builder});

  final Widget Function(bool hovered) builder;

  @override
  State<_TaskNodeHover> createState() => _TaskNodeHoverState();
}

class _TaskNodeHoverState extends State<_TaskNodeHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: RepaintBoundary(child: widget.builder(_hovered)),
  );
}

/// 局部编辑器独立监听视口动画，避免重建整个拓扑。
class _CanvasZoomPercentage extends StatefulWidget {
  const _CanvasZoomPercentage({
    required this.transform,
    required this.theme,
    required this.onZoom,
  });
  final TransformationController transform;
  final AppTheme theme;
  final ValueChanged<double> onZoom;

  @override
  State<_CanvasZoomPercentage> createState() => _CanvasZoomPercentageState();
}

class _CanvasZoomPercentageState extends State<_CanvasZoomPercentage> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'canvas zoom percentage');
  bool _skipBlurCommit = false;

  @override
  void initState() {
    super.initState();
    widget.transform.addListener(_sync);
    _focus.addListener(_focusChanged);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _CanvasZoomPercentage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transform != widget.transform) {
      oldWidget.transform.removeListener(_sync);
      widget.transform.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    if (!_focus.hasFocus) {
      final percent = widget.transform.value.entry(0, 0).abs() * 100;
      final value = percent < 10
          ? percent.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')
          : percent.round().toString();
      if (_text.text != value) _text.text = value;
    }
  }

  void _focusChanged() {
    if (mounted) setState(() {});
    if (_focus.hasFocus) {
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    } else {
      if (!_skipBlurCommit) _commit();
      _skipBlurCommit = false;
      _sync();
    }
  }

  void _commit() {
    final percent = double.tryParse(_text.text.replaceAll(',', '.'));
    if (percent == null || !percent.isFinite) return;
    final currentScale = widget.transform.value.entry(0, 0).abs();
    final scale = (percent / 100).clamp(taskCanvasMinScale, taskCanvasMaxScale);
    widget.onZoom(scale / currentScale);
  }

  void _finish({bool cancel = false}) {
    if (!cancel) _commit();
    _skipBlurCommit = true;
    _focus.unfocus();
    _sync();
  }

  @override
  void dispose() {
    widget.transform.removeListener(_sync);
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppTooltip(
    message: context.l10n.agentTopologyZoomPercentage,
    child: Semantics(
      label: context.l10n.agentTopologyZoomPercentage,
      child: SizedBox(
        width: 58,
        height: 24,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              if (event is KeyDownEvent) _finish(cancel: true);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: InteractionDecoration(
            key: const ValueKey('topology-zoom-field-frame'),
            palette: widget.theme,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _focus.hasFocus
                    ? widget.theme.basePrimary
                    : Colors.transparent,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: MediaQuery.textScalerOf(context).scale(12) * 1.2,
                      child: TextField(
                        key: const ValueKey('topology-zoom-percentage'),
                        controller: _text,
                        focusNode: _focus,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          color: widget.theme.textColorSecondary,
                        ),
                        cursorHeight: 14,
                        cursorColor: widget.theme.basePrimary,
                        decoration: null,
                        onSubmitted: (_) => _finish(),
                        onTapOutside: (_) => _focus.unfocus(),
                      ),
                    ),
                  ),
                  Text(
                    '%',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: widget.theme.textColorSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    this.origin,
  );
  final AiTopologyEditSnapshot snapshot;
  final Map<String, Offset> positions;
  final List<String> frontOrder;
  final Set<String> selectedIds;
  final Set<String> selectedEdges;
  final Matrix4 transform;
  final Offset origin;
}

/// 会话顶部名称限高两行，超出后独立滚动。
class _TaskTitleScroll extends StatefulWidget {
  const _TaskTitleScroll({
    super.key,
    required this.title,
    required this.theme,
    required this.onRename,
  });
  final String title;
  final AppTheme theme;
  final VoidCallback onRename;

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
    final theme = widget.theme;
    final hoverColor = theme.secondaryTextHoverColor;
    final titleStyle = _topologyHeaderTitleStyle.copyWith(
      color: theme.textColorPrimary,
    );
    return AppTooltip(
      message: context.l10n.aiTopologyRename,
      child: Semantics(
        button: true,
        child: MenuItemSurface(
          theme: theme,
          onPressed: widget.onRename,
          backgroundColor: hoverColor.withValues(alpha: 0),
          surfaceColor: theme.primary,
          hoverColor: hoverColor,
          borderRadius: _topologyHeaderTitleRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final style = DefaultTextStyle.of(context).style
                    .merge(titleStyle);
                TextPainter measure(
                  String text, {
                  double maxWidth = double.infinity,
                }) => TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  locale: Localizations.maybeLocaleOf(context),
                )..layout(maxWidth: maxWidth);
                final lines = measure('M\nM');
                final height = lines.height.ceilToDouble();
                lines.dispose();
                final content = measure(
                  widget.title,
                  maxWidth: constraints.maxWidth,
                );
                final scrollbarInset = content.height > height ? 20.0 : 0.0;
                final width = math.min(
                  constraints.maxWidth,
                  content.width + scrollbarInset,
                );
                content.dispose();
                return ConstrainedBox(
                  constraints: BoxConstraints.tightFor(width: width)
                      .copyWith(maxHeight: height),
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
                          padding: EdgeInsetsDirectional.only(
                            end: scrollbarInset,
                          ),
                          child: Text(widget.title, style: titleStyle),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskNode extends StatelessWidget {
  const _TaskNode({
    required this.session,
    required this.selected,
    required this.onOpen,
    required this.onRoleplayPointerUp,
    required this.onRoleplaySettings,
    required this.theme,
  });
  final AiAgentWorkspace session;
  final bool selected;
  final VoidCallback onOpen;
  final PointerUpEventListener onRoleplayPointerUp;
  final VoidCallback onRoleplaySettings;
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
                        _kindIcon(session.kind),
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
                  if (session.assistant.roleplayBinding?.card
                      case final card?) ...[
                    const SizedBox(height: 6),
                    AppTooltip(
                      message: '${l10n.aiRoleplayCardSettings} · ${card.name}',
                      child: Listener(
                        onPointerUp: onRoleplayPointerUp,
                        child: MenuItemSurface(
                          key: ValueKey('topology-roleplay-${session.id}'),
                          theme: theme,
                          onPressed: onRoleplaySettings,
                          borderRadius: BorderRadius.circular(6),
                          backgroundColor: theme
                              .buttonColorsForSurface(theme.primary)
                              .hover
                              .withValues(alpha: 0),
                          surfaceColor: theme.primary,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                RoleplayAvatar(
                                  card: card,
                                  theme: theme,
                                  size: 19,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    card.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.textColorSecondary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Symbols.chevron_right_rounded,
                                  size: 14,
                                  color: theme.iconColor,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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

IconData _kindIcon(AiWorkspaceKind kind) => switch (kind) {
  AiWorkspaceKind.primary => Symbols.hub_rounded,
  AiWorkspaceKind.permanent => Symbols.account_tree_rounded,
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
  final response = session.latestProcessMessage;
  if (session.assistant.stopRequested ||
      (session.status == 'stopped' && response?.role != 'compaction')) {
    return (
      label: l10n.aiWorkspaceStopped,
      icon: Symbols.stop_circle_rounded,
      fill: 0,
    );
  }
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
          icon: Symbols.chat_bubble_rounded,
          fill: 1,
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
        ..strokeWidth =
            2 /
            transform.value
                .entry(0, 0)
                .abs()
                .clamp(taskCanvasMinScale, taskCanvasMaxScale),
    );
  }

  @override
  bool shouldRepaint(_ConnectionPreviewPainter oldDelegate) =>
      start != oldDelegate.start ||
      color != oldDelegate.color ||
      pointer != oldDelegate.pointer ||
      transform != oldDelegate.transform;
}

class _TopologyBackgroundPainter extends CustomPainter {
  const _TopologyBackgroundPainter({
    required this.pattern,
    required this.gridColor,
    required this.canvasStyle,
    required this.scale,
    required this.backgroundBounds,
  });
  final Rect backgroundBounds;
  final TaskCanvasBackgroundPattern pattern;
  final AiTaskCanvasStyle canvasStyle;
  final double scale;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    pattern.paint(
      canvas,
      backgroundBounds,
      style: canvasStyle,
      color: gridColor,
      scale: scale,
    );
  }

  @override
  bool shouldRepaint(_TopologyBackgroundPainter oldDelegate) =>
      oldDelegate.gridColor != gridColor ||
      oldDelegate.canvasStyle != canvasStyle ||
      oldDelegate.backgroundBounds != backgroundBounds ||
      oldDelegate.scale != scale;
}

class _TopologyConversation extends StatelessWidget {
  const _TopologyConversation({
    super.key,
    required this.session,
    required this.onBack,
    required this.onRename,
    required this.onChooseOpening,
  });
  final AiAgentWorkspace session;
  final VoidCallback onBack;
  final VoidCallback onRename;
  final Future<void> Function(AiRoleplayBinding) onChooseOpening;

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
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _TaskTitleScroll(
                    key: ValueKey(
                      'topology-conversation-title-scroll-${session.id}',
                    ),
                    title: session.title,
                    theme: theme,
                    onRename: onRename,
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
                          _kindIcon(session.kind),
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
        Expanded(
          child: AssistantPage(
            initialDraft:
                session.assistant.messages.every(
                  (message) => message.isRoleplayOpening,
                )
                ? session.task
                : '',
            onManageContext: () =>
                showAgentContextStorage(context, theme, session.id),
            roleplayMenuBuilder: (compact) => RoleplayMenuButton(
              theme: theme,
              assistant: session.assistant,
              compact: compact,
              onChooseOpening: onChooseOpening,
            ),
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
  late final TextEditingController _contextBudget;
  late final TextEditingController _contextPercent;
  bool _invalidBudget = false;
  bool _invalidPercent = false;
  final _scroll = ScrollController();
  bool _working = false;
  bool _missing = false;
  Object? _error;
  String _model = '';
  AiRoleplayBinding? _roleplay;
  int? _roleplayOpening;
  late final AiAssistantProvider _draft;
  @override
  void initState() {
    super.initState();
    final inherited = widget.parent?.assistant ?? widget.workspaces.main;
    _draft = inherited.forkForWorkspace();
    _contextBudget = TextEditingController(
      text: inherited.contextBudgetTokens.toString(),
    );
    _contextPercent = TextEditingController(
      text: inherited.contextCompactionPercent.toString(),
    );
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
    _contextBudget.dispose();
    _contextPercent.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_working) return;
    final budget = int.tryParse(_contextBudget.text.trim());
    final percent = int.tryParse(_contextPercent.text.trim());
    setState(() {
      _invalidBudget = budget == null || budget <= 0;
      _invalidPercent = percent == null || percent < 1 || percent > 100;
    });
    if (_invalidBudget || _invalidPercent) return;
    if (_task.text.trim().isEmpty && _roleplay == null) {
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
              processingSpeed: _draft.processingSpeed,
              contextBudgetTokens: budget,
              contextCompactionPercent: percent,
              auxiliaryModels: _draft.auxiliaryModels,
              roleplay: _roleplay,
              roleplayOpening: _roleplayOpening,
            )
          : await widget.workspaces.create(
              title: _title.text.trim(),
              task: _task.text.trim(),
              serviceId: choice?[0],
              model: choice?[1],
              permissions: _draft.permissions,
              reasoningEffort: _draft.reasoningEffort,
              processingSpeed: _draft.processingSpeed,
              contextBudgetTokens: budget,
              contextCompactionPercent: percent,
              auxiliaryModels: _draft.auxiliaryModels,
              roleplay: _roleplay,
              roleplayOpening: _roleplayOpening,
              parentId: widget.parent!.id,
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

  void _setRoleplay(AiRoleplayBinding? binding) => setState(() {
    if (!identical(_roleplay, binding)) _roleplayOpening = null;
    _roleplay = binding;
    _missing = false;
  });

  Future<void> _editRoleplaySettings(
    AppTheme theme,
    AiRoleplayBinding binding,
  ) async {
    final updated = await showDialog<AiRoleplayBinding>(
      context: context,
      builder: (_) => RoleplayCardOptionsDialog(binding: binding, theme: theme),
    );
    if (mounted && updated != null && identical(_roleplay, binding)) {
      setState(() => _roleplay = updated);
    }
  }

  Future<void> _chooseOpening(AppTheme theme, AiRoleplayBinding binding) async {
    final selected = await pickRoleplayOpening(
      context,
      theme,
      binding,
      hasConversationToRestart: () => false,
      forCreation: true,
      selectedOpening: _roleplayOpening,
      onClearSelection: _roleplayOpening == null
          ? null
          : () => setState(() => _roleplayOpening = null),
    );
    if (mounted && selected != null && identical(_roleplay, binding)) {
      setState(() => _roleplayOpening = selected.index);
    }
  }

  List<Widget> _roleplayFields(AppTheme theme) {
    final l10n = context.l10n;
    final binding = _roleplay;
    final enabled = !_working;
    return [
      SettingsField(
        theme: theme,
        title: l10n.aiRoleplayTemplateOptional,
        description: l10n.aiRoleplayTemplateHelp,
        trailing: Flexible(
          child: RoleplayTemplateMenu(
            key: const ValueKey('topology-roleplay-template'),
            theme: theme,
            binding: binding,
            templates: widget.workspaces.roleplayTemplates,
            onSelected: enabled ? _setRoleplay : null,
            onSettings: (binding) =>
                unawaited(_editRoleplaySettings(theme, binding)),
          ),
        ),
      ),
      if (binding != null && binding.sourceCard.openings.isNotEmpty) ...[
        const SizedBox(height: 16),
        SettingsField(
          theme: theme,
          title: l10n.aiRoleplayOpeningOptional,
          description: l10n.aiRoleplayOpeningHelp,
          trailing: Flexible(
            child: RoleplayFieldButton(
              key: const ValueKey('topology-roleplay-opening'),
              theme: theme,
              label: _roleplayOpening == null
                  ? l10n.aiRoleplayManualOpening
                  : l10n.aiRoleplayOpeningNumber(_roleplayOpening! + 1),
              icon: Icon(
                _roleplayOpening == null
                    ? Symbols.edit_note_rounded
                    : Symbols.auto_stories_rounded,
                fill: 1,
              ),
              onPressed: enabled ? () => _chooseOpening(theme, binding) : null,
            ),
          ),
        ),
      ],
    ];
  }

  Widget _contextUnit(AppTheme theme, String unit) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Center(
      widthFactor: 1,
      child: Text(
        unit,
        style: TextStyle(fontSize: 12, color: theme.textColorTertiary),
      ),
    ),
  );

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
          data: ScrollbarTheme.of(context)
              .copyWith(crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset),
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
                SettingsField(
                  theme: theme,
                  title: l10n.aiTopologyModel,
                  description: l10n.aiTopologyModelHelp,
                  trailing: Flexible(
                    child: IgnorePointer(
                      ignoring: _working,
                      child: ExcludeFocus(
                        excluding: _working,
                        child: ModelSelector(
                          key: const ValueKey('topology-model-select'),
                          theme: theme,
                          assistant: _draft,
                          fieldSurfaceColor: AppDialogStyle.backgroundColor(
                            theme,
                          ),
                          selectedServiceId: _model.isEmpty
                              ? _draft.selectedService?.id
                              : (jsonDecode(_model) as List)[0] as String,
                          selectedModel: _model.isEmpty
                              ? _draft.selectedModel
                              : (jsonDecode(_model) as List)[1] as String,
                          onSelected: (serviceId, model) => setState(
                            () => _model = jsonEncode([serviceId, model]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SettingsField(
                  theme: theme,
                  title: l10n.aiPermissions,
                  description: l10n.aiTopologyPermissionsHelp,
                  trailing: IgnorePointer(
                    ignoring: _working,
                    child: ExcludeFocus(
                      excluding: _working,
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
                ..._roleplayFields(theme),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SettingsField(
                        theme: theme,
                        title: l10n.agentStorageContextBudget,
                        description: '',
                        child: SettingControlledTextField(
                          key: const ValueKey('topology-context-budget'),
                          theme: theme,
                          controller: _contextBudget,
                          enabled: !_working,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          suffixIcon: _contextUnit(theme, 'token'),
                          onChanged: (_) =>
                              setState(() => _invalidBudget = false),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SettingsField(
                        theme: theme,
                        title: l10n.agentStorageContextPercent,
                        description: '',
                        child: SettingControlledTextField(
                          key: const ValueKey('topology-context-percent'),
                          theme: theme,
                          controller: _contextPercent,
                          enabled: !_working,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          suffixIcon: _contextUnit(theme, '%'),
                          onChanged: (_) =>
                              setState(() => _invalidPercent = false),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.agentStorageContextTriggerTokens(
                    math.max(
                      1,
                      (int.tryParse(_contextBudget.text) ?? 0) *
                          (int.tryParse(_contextPercent.text) ?? 0) ~/
                          100,
                    ),
                  ),
                  style: AppDialogStyle.descriptionStyle(theme),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.agentStorageContextHint,
                  style: AppDialogStyle.descriptionStyle(theme),
                ),
                if (_invalidBudget) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.agentStorageContextInvalid,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.materialColors.error,
                    ),
                  ),
                ],
                if (_invalidPercent) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.agentStorageContextPercentInvalid,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.materialColors.error,
                    ),
                  ),
                ],
                if ((int.tryParse(_contextPercent.text) ?? 0) >= 95) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.agentStorageContextPercentWarning,
                    style: AppDialogStyle.descriptionStyle(theme),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  _roleplay == null
                      ? l10n.aiWorkspaceTaskPrompt
                      : l10n.aiRoleplayOptionalTask,
                  style: AppDialogStyle.fieldTitleStyle(theme),
                ),
                const SizedBox(height: 4),
                Text(
                  _roleplay == null
                      ? l10n.aiTopologyTaskHelp
                      : l10n.aiRoleplayOptionalTaskHelp,
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
