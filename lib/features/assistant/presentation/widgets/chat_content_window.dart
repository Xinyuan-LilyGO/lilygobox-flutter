import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'chat_message_list.dart';
import 'conversation_scroll_controller.dart';

class ChatContentRegistry {
  ChatContentRegistry({
    required this.controller,
    required this.followsLatest,
    required this.hasSelection,
    required this.onChanged,
    this.isSeeking,
    this.storageId,
  });

  final ConversationScrollController controller;
  final bool Function() followsLatest;
  final bool Function() hasSelection;
  final VoidCallback onChanged;
  final bool Function()? isSeeking;
  final Object? storageId;
  final _windows = <ChatContentWindowState>{};
  final _pointers = <int>{};
  bool _notificationPending = false;
  bool _disposed = false;

  bool get hasEarlier => _windows.any((window) => window.hasEarlier);
  bool get hasLater => _windows.any((window) => window.hasLater);
  bool get _trackingPointer => _pointers.isNotEmpty;
  int get navigationUnits =>
      _windows.fold(0, (total, window) => total + window.widget.childCount);

  ChatContentWindowState? _messageWindow(String messageId) => _windows
      .where(
        (window) =>
            window._messageId == messageId && window._parentWindow == null,
      )
      .firstOrNull;

  ChatContentWindowState? _childWindow(
    ChatContentWindowState parent,
    int index,
  ) => _windows
      .where(
        (window) =>
            identical(window._parentWindow, parent) &&
            window._parentIndex == index,
      )
      .firstOrNull;

  double? messageFraction(String messageId) =>
      _messageWindow(messageId)?._visibleFraction();

  bool revealMessage(String messageId, double fraction) =>
      _messageWindow(messageId)?._revealFraction(fraction) ?? false;

  double? messageOffset(String messageId, double fraction) =>
      _messageWindow(messageId)?._offsetForFraction(fraction);

  bool hasLaterFor(String messageId) {
    final root = _windows
        .where(
          (window) =>
              window._messageId == messageId && window._parentWindow == null,
        )
        .lastOrNull;
    return root != null && _hasLaterAtTail(root);
  }

  bool _hasLaterAtTail(ChatContentWindowState window) {
    if (window.hasLater) return true;
    final lastChild = _windows
        .where(
          (child) =>
              identical(child._parentWindow, window) &&
              child._parentIndex == window.widget.childCount - 1,
        )
        .lastOrNull;
    return lastChild != null && _hasLaterAtTail(lastChild);
  }

  void _register(ChatContentWindowState window) {
    if (_disposed || !_windows.add(window)) return;
    if (_windows.length == 1) controller.addListener(_scheduleWindows);
    _notifyChanged();
  }

  void _unregister(ChatContentWindowState window) {
    if (!_windows.remove(window)) return;
    if (_windows.isEmpty) controller.removeListener(_scheduleWindows);
    _notifyChanged();
  }

  void _scheduleWindows() {
    for (final window in _windows.toList()) {
      window._scheduleUpdate();
    }
  }

  void _notifyChanged() {
    if (_disposed || _notificationPending) return;
    _notificationPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationPending = false;
      if (!_disposed) onChanged();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void showLatest() {
    for (final window in _windows.toList()) {
      window._showLatest();
    }
  }

  void selectionChanged() => _scheduleWindows();

  void pointerDown(PointerDownEvent event) {
    if (event.buttons == kPrimaryMouseButton) _pointers.add(event.pointer);
  }

  void pointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    _scheduleWindows();
  }

  void pointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _scheduleWindows();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_windows.isNotEmpty) controller.removeListener(_scheduleWindows);
    _windows.clear();
    _pointers.clear();
  }
}

class ChatContentScope extends InheritedWidget {
  const ChatContentScope({
    super.key,
    required this.state,
    required super.child,
  });

  final ChatContentRegistry state;

  static ChatContentRegistry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatContentScope>()?.state;

  @override
  bool updateShouldNotify(ChatContentScope oldWidget) =>
      !identical(state, oldWidget.state);
}

class ChatContentMessageScope extends InheritedWidget {
  const ChatContentMessageScope({
    super.key,
    required this.messageId,
    required super.child,
  });

  final String messageId;

  static ChatContentMessageScope? _maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatContentMessageScope>();

  @override
  bool updateShouldNotify(ChatContentMessageScope oldWidget) =>
      messageId != oldWidget.messageId;
}

class ChatContentWindow extends StatefulWidget {
  const ChatContentWindow({
    super.key,
    required this.childCount,
    required this.revision,
    required this.itemBuilder,
    required this.storageId,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  }) : assert(childCount >= 0);

  final int childCount;
  final int revision;
  final IndexedWidgetBuilder itemBuilder;
  final Object storageId;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<ChatContentWindow> createState() => ChatContentWindowState();
}

class ChatContentWindowState extends State<ChatContentWindow> {
  static const initialChildren = 4;
  static const batchChildren = 4;
  static const targetChildren = 24;
  static const preloadScreens = 2;
  static const retainScreens = 4;

  ChatContentRegistry? _registry;
  ChatContentWindowState? _parentWindow;
  int? _parentIndex;
  String? _messageId;
  List<ChatMessageGeometry> _geometry = const [];
  int _start = 0;
  int _end = 0;
  int _knownCount = 0;
  bool _initialized = false;
  bool _updatePending = false;
  bool _pendingTail = false;
  _ContentAnchor? _anchor;

  bool get hasEarlier => _start > 0;
  bool get hasLater => _end < widget.childCount;
  int get loadedChildCount => _end - _start;
  int get firstChildIndex => _start;
  int get lastChildIndex => _end - 1;

  double _visibleFraction() {
    final viewport = _viewport();
    if (viewport == null || _geometry.isEmpty || widget.childCount == 0) {
      return 0;
    }
    final center = viewport.visible.center.dy;
    final entry = _geometry.firstWhere(
      (entry) => entry.bottom > center,
      orElse: () => _geometry.last,
    );
    final index = entry.index;
    final child = _registry?._childWindow(this, index);
    final within =
        child?._visibleFraction() ??
        ((center - entry.top) / math.max(1, entry.bottom - entry.top)).clamp(
          0.0,
          1.0,
        );
    return (index + within) / widget.childCount;
  }

  bool _revealFraction(double fraction) {
    if (widget.childCount == 0) return false;
    _anchor = null;
    _pendingTail = false;
    final target = (fraction * widget.childCount).clamp(
      0.0,
      widget.childCount - .000001,
    );
    final index = target.floor();
    if (index < _start || index >= _end) {
      setState(() {
        _anchor = null;
        _pendingTail = false;
        _start = math.max(0, index - initialChildren ~/ 2);
        _end = math.min(widget.childCount, _start + initialChildren);
      });
      return true;
    }
    return _registry
            ?._childWindow(this, index)
            ?._revealFraction(target - index) ??
        false;
  }

  double? _offsetForFraction(double fraction) {
    if (widget.childCount == 0) return null;
    final target = (fraction * widget.childCount).clamp(
      0.0,
      widget.childCount - .000001,
    );
    final index = target.floor();
    final childOffset = _registry
        ?._childWindow(this, index)
        ?._offsetForFraction(target - index);
    if (childOffset != null) return childOffset;
    final viewport = _viewport();
    if (viewport == null) return null;
    final entry = _geometry.where((entry) => entry.index == index).firstOrNull;
    return entry == null
        ? null
        : viewport.origin +
              entry.top +
              (entry.bottom - entry.top) * (target - index);
  }

  Object get _storageId =>
      ValueKey(('chat-content', _registry?.storageId, widget.storageId));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final messageId = ChatContentMessageScope._maybeOf(context)?.messageId;
    final parent = _ContentParentScope.maybeOf(context);
    final parentWindow = parent?.state;
    final parentIndex = parent?.index;
    if (_messageId != messageId ||
        !identical(_parentWindow, parentWindow) ||
        _parentIndex != parentIndex) {
      _messageId = messageId;
      _parentWindow = parentWindow;
      _parentIndex = parentIndex;
      _registry?._notifyChanged();
    }
    final registry = ChatContentScope.maybeOf(context);
    if (!identical(registry, _registry)) {
      _registry?._unregister(this);
      _registry = registry;
      _initialized = false;
    }
    if (!_initialized) _reset();
    registry?._register(this);
  }

  @override
  void didUpdateWidget(ChatContentWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.storageId != oldWidget.storageId ||
        widget.childCount < _knownCount) {
      _reset();
    } else if (_registry == null) {
      _start = 0;
      _end = widget.childCount;
    } else if (widget.childCount != _knownCount) {
      if ((_end == _knownCount || _pendingTail) && _registry!.followsLatest()) {
        if (_registry!._trackingPointer) {
          _pendingTail = true;
        } else {
          _includeLatest();
        }
      }
    }
    _knownCount = widget.childCount;
    if (widget.revision != oldWidget.revision) _anchor = null;
    _scheduleUpdate();
  }

  void _reset() {
    final previousStart = _start;
    final previousEnd = _end;
    _knownCount = widget.childCount;
    final saved = PageStorage.maybeOf(context)
        ?.readState(context, identifier: _storageId);
    if (_registry == null) {
      _start = 0;
      _end = widget.childCount;
    } else if (saved is _SavedContentWindow &&
        saved.revision == widget.revision &&
        saved.count == widget.childCount &&
        saved.start >= 0 &&
        saved.start < saved.end &&
        saved.end <= widget.childCount) {
      _start = saved.start;
      _end = saved.end;
    } else {
      _end = widget.childCount;
      _start = math.max(0, _end - initialChildren);
    }
    if (_start != previousStart || _end != previousEnd) {
      _geometry = const [];
    }
    _anchor = null;
    _pendingTail = false;
    _initialized = true;
    _scheduleUpdate();
  }

  _ContentViewport? _viewport() {
    final registry = _registry;
    if (registry == null || !registry.controller.hasClients || !mounted) {
      return null;
    }
    final position = registry.controller.position;
    if (!position.hasPixels || !position.hasViewportDimension) return null;
    final viewport = position.context.notificationContext?.findRenderObject();
    final content = context.findRenderObject();
    if (viewport is! RenderBox ||
        !viewport.attached ||
        !viewport.hasSize ||
        content is! RenderBox ||
        !content.attached) {
      return null;
    }
    final transform = content.getTransformTo(viewport);
    if (transform.determinant() == 0) return null;
    final visible = MatrixUtils.inverseTransformRect(
      transform,
      Rect.fromLTWH(0, 0, 1, position.viewportDimension),
    );
    return _ContentViewport(
      visible: visible,
      origin: MatrixUtils.transformPoint(transform, Offset.zero).dy,
      extent: position.viewportDimension,
      scrollOffset: position.pixels,
      direction: axisDirectionIsReversed(position.axisDirection) ? -1 : 1,
    );
  }

  void _rememberAnchor(_ContentViewport viewport) {
    if (_anchor != null || _geometry.isEmpty || _startsBelowReader(viewport)) {
      return;
    }
    final entry = _geometry.firstWhere(
      (entry) => entry.bottom > viewport.visible.top,
      orElse: () => _geometry.last,
    );
    _anchor = _ContentAnchor(
      index: entry.index,
      viewportOffset: viewport.origin + entry.top,
      scrollOffset: viewport.scrollOffset,
    );
  }

  bool _startsBelowReader(_ContentViewport viewport) {
    final position = _registry!.controller.position;
    return viewport.visible.top < 0 &&
        position.hasContentDimensions &&
        position.extentAfter > 0;
  }

  void _handleLayout(List<ChatMessageGeometry> geometry) {
    _geometry = geometry;
    final anchor = _anchor;
    final viewport = anchor == null ? null : _viewport();
    _anchor = null;
    if (anchor != null && viewport != null) {
      for (final entry in geometry) {
        if (entry.index != anchor.index) continue;
        final expected =
            anchor.viewportOffset -
            (viewport.scrollOffset - anchor.scrollOffset) * viewport.direction;
        final correction =
            (viewport.origin + entry.top - expected) / viewport.direction;
        if (correction.isFinite && correction.abs() > .001) {
          _registry!.controller.correctForHistoryChange(correction);
        }
        break;
      }
    }
    _saveRange();
    _scheduleUpdate();
  }

  void _saveRange() {
    final registry = _registry;
    if (registry == null) return;
    final range = _SavedContentWindow(
      revision: widget.revision,
      count: widget.childCount,
      start: _start,
      end: _end,
    );
    final storageId = _storageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(registry, _registry) ||
          range.revision != widget.revision ||
          range.count != widget.childCount ||
          range.start != _start ||
          range.end != _end ||
          !registry.controller.hasClients) {
        return;
      }
      registry.controller.saveHistoryOffset();
      PageStorage.maybeOf(context)
          ?.writeState(context, range, identifier: storageId);
    });
  }

  void _includeLatest() {
    _pendingTail = false;
    final registry = _registry;
    if (registry != null &&
        widget.childCount - _start > targetChildren &&
        !registry.hasSelection()) {
      final viewport = _viewport();
      if (viewport != null) _rememberAnchor(viewport);
      _start = math.max(0, widget.childCount - targetChildren);
    }
    _end = widget.childCount;
  }

  void _showLatest() {
    if (!mounted || _end == widget.childCount) return;
    setState(() {
      _pendingTail = false;
      _anchor = null;
      _end = widget.childCount;
      _start = math.max(0, _end - initialChildren);
    });
    _registry?._notifyChanged();
  }

  void _scheduleUpdate() {
    if (_updatePending || !mounted || _registry == null) return;
    if (!hasEarlier && !hasLater && loadedChildCount <= targetChildren) return;
    _updatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePending = false;
      if (!mounted ||
          _registry == null ||
          _registry!._trackingPointer ||
          (_registry!.isSeeking?.call() ?? false)) {
        return;
      }
      final registry = _registry!;
      final viewport = _viewport();
      if (viewport == null || _geometry.isEmpty) return;
      final height = _geometry.last.bottom;
      if (viewport.visible.bottom <= 0 || viewport.visible.top >= height) {
        return;
      }
      if (_pendingTail) {
        _pendingTail = false;
        if (registry.followsLatest() && hasLater) {
          setState(_includeLatest);
          registry._notifyChanged();
          return;
        }
      }
      final margin = viewport.extent * preloadScreens;
      final earlier = hasEarlier && viewport.visible.top < margin;
      final later = hasLater && height - viewport.visible.bottom < margin;
      final retainSelection = registry.hasSelection();
      if (earlier &&
          _startsBelowReader(viewport) &&
          !retainSelection &&
          !registry.followsLatest()) {
        setState(() {
          _start = 0;
          _end = math.min(widget.childCount, initialChildren);
        });
        registry._notifyChanged();
        return;
      }
      if (!earlier &&
          !later &&
          (retainSelection || loadedChildCount <= targetChildren)) {
        return;
      }
      final loadEarlier =
          earlier &&
          (!later || viewport.visible.top < height - viewport.visible.bottom);
      final retainedTop =
          viewport.visible.top - viewport.extent * retainScreens;
      final retainedBottom =
          viewport.visible.bottom + viewport.extent * retainScreens;
      final oldestRetained = _geometry
          .where((entry) => entry.bottom <= retainedTop)
          .lastOrNull;
      final newestRetained = _geometry
          .where((entry) => entry.top >= retainedBottom)
          .firstOrNull;
      final safeStart = oldestRetained == null
          ? _start
          : oldestRetained.index + 1;
      final safeEnd = newestRetained == null ? _end : newestRetained.index;
      var nextStart = _start;
      var nextEnd = _end;
      if (loadEarlier) {
        nextStart = math.max(0, _start - batchChildren);
        if (nextEnd - nextStart > targetChildren && !retainSelection) {
          nextEnd = math.min(
            nextEnd,
            math.max(nextStart + targetChildren, safeEnd),
          );
        }
      } else if (later) {
        nextEnd = math.min(widget.childCount, _end + batchChildren);
        if (nextEnd - nextStart > targetChildren && !retainSelection) {
          nextStart = math.max(
            nextStart,
            math.min(nextEnd - targetChildren, safeStart),
          );
        }
      } else {
        nextStart = math.min(
          safeStart,
          math.max(_start, safeEnd - targetChildren),
        );
        nextEnd = math.max(safeEnd, math.min(_end, nextStart + targetChildren));
      }
      if (nextStart == _start && nextEnd == _end) return;
      _rememberAnchor(viewport);
      setState(() {
        _start = nextStart;
        _end = nextEnd;
      });
      registry._notifyChanged();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _registry?._unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _registry?.pointerDown,
    onPointerUp: _registry?.pointerUp,
    onPointerCancel: _registry?.pointerCancel,
    child: ChatMessageList(
      crossAxisAlignment: widget.crossAxisAlignment,
      firstIndex: _start,
      onLayout: _handleLayout,
      children: [
        for (var index = _start; index < _end; index++)
          _ContentParentScope(
            key: ValueKey((widget.storageId, index)),
            state: this,
            index: index,
            child: widget.itemBuilder(context, index),
          ),
      ],
    ),
  );
}

class _ContentParentScope extends InheritedWidget {
  const _ContentParentScope({
    super.key,
    required this.state,
    required this.index,
    required super.child,
  });

  final ChatContentWindowState state;
  final int index;

  static _ContentParentScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ContentParentScope>();

  @override
  bool updateShouldNotify(_ContentParentScope oldWidget) =>
      !identical(state, oldWidget.state) || index != oldWidget.index;
}

class _ContentViewport {
  const _ContentViewport({
    required this.visible,
    required this.origin,
    required this.extent,
    required this.scrollOffset,
    required this.direction,
  });

  final Rect visible;
  final double origin;
  final double extent;
  final double scrollOffset;
  final double direction;
}

class _ContentAnchor {
  const _ContentAnchor({
    required this.index,
    required this.viewportOffset,
    required this.scrollOffset,
  });

  final int index;
  final double viewportOffset;
  final double scrollOffset;
}

class _SavedContentWindow {
  const _SavedContentWindow({
    required this.revision,
    required this.count,
    required this.start,
    required this.end,
  });

  final int revision;
  final int count;
  final int start;
  final int end;
}
