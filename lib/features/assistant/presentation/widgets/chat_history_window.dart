import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../domain/models.dart';
import 'chat_content_window.dart';
import 'chat_history_scrollbar.dart';
import 'chat_message_list.dart';
import 'conversation_scroll_controller.dart';

class ChatHistoryWindow extends StatefulWidget {
  const ChatHistoryWindow({
    super.key,
    required this.messages,
    required this.controller,
    required this.historyId,
    required this.itemBuilder,
    required this.viewportBuilder,
    required this.followsLatest,
    required this.onRangeChanged,
    required this.hasSelection,
    this.onContentRangeChanged,
    this.scrollbar = false,
  });

  final List<AiMessage> messages;
  final ConversationScrollController controller;
  final String historyId;
  final Widget Function(AiMessage) itemBuilder;
  final Widget Function(BuildContext, Widget) viewportBuilder;
  final bool Function() followsLatest;
  final ValueChanged<Set<String>> onRangeChanged;
  final bool Function() hasSelection;
  final VoidCallback? onContentRangeChanged;
  final bool scrollbar;

  @override
  State<ChatHistoryWindow> createState() => ChatHistoryWindowState();
}

class ChatHistoryWindowState extends State<ChatHistoryWindow> {
  static const initialMessages = 32;
  static const batchMessages = 4;
  static const maximumMessages = 96;
  static const preloadScreens = 4;
  static const _maximumBatch = 16;

  int _start = 0;
  int _end = 0;
  int _knownCount = 0;
  String? _firstId;
  bool _initialized = false;
  bool _updatePending = false;
  bool _pendingTail = false;
  final _trackPointers = <int>{};
  List<ChatMessageGeometry> _geometry = const [];
  (String, double)? _anchor;
  late ChatContentRegistry _content;
  double? _pendingSeek;
  bool _seekScheduled = false;
  bool get _usesLogicalNavigation =>
      _start > 0 || _end < widget.messages.length || hasUnloadedContent;

  double _logicalScrollFraction() {
    if (!widget.controller.hasClients ||
        _geometry.isEmpty ||
        widget.messages.isEmpty) {
      return 0;
    }
    final position = widget.controller.position;
    if (position.extentAfter <= 0 && !hasLater) return 1;
    if (position.extentBefore <= 0 && !hasEarlier) return 0;
    final center = position.pixels + position.viewportDimension / 2 - 16;
    final entry = _geometry.firstWhere(
      (entry) => entry.bottom > center,
      orElse: () => _geometry.last,
    );
    final index = entry.index;
    final within =
        _content.messageFraction(widget.messages[index].id) ??
        ((center - entry.top) / math.max(1, entry.bottom - entry.top)).clamp(
          0.0,
          1.0,
        );
    return (index + within) / widget.messages.length;
  }

  void _seek(double fraction, bool logicalNavigation) {
    if (widget.messages.isEmpty) return;
    if (!logicalNavigation) {
      final position = widget.controller.position;
      widget.controller.jumpTo(fraction * position.maxScrollExtent);
      return;
    }
    final index = (fraction * widget.messages.length).floor().clamp(
      0,
      widget.messages.length - 1,
    );
    _pendingSeek = fraction;
    if (index < _start || index >= _end) {
      setState(() {
        _anchor = null;
        _pendingTail = false;
        _start = math.max(0, index - initialMessages ~/ 2);
        _end = math.min(widget.messages.length, _start + initialMessages);
      });
    }
    _scheduleSeek();
  }

  void _scheduleSeek() {
    if (_seekScheduled || _pendingSeek == null) return;
    _seekScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seekScheduled = false;
      final fraction = _pendingSeek;
      if (!mounted ||
          fraction == null ||
          !widget.controller.hasClients ||
          widget.messages.isEmpty) {
        return;
      }
      final target = (fraction * widget.messages.length).clamp(
        0.0,
        widget.messages.length - .000001,
      );
      final index = target.floor();
      final message = widget.messages[index];
      if (_content.revealMessage(message.id, target - index)) {
        _scheduleSeek();
        return;
      }
      final entry = _geometry
          .where((entry) => entry.index == index)
          .firstOrNull;
      if (entry == null) {
        _pendingSeek = null;
        _scheduleUpdate();
        return;
      }
      final position = widget.controller.position;
      final bodyOffset = _content.messageOffset(message.id, target - index);
      final offset = bodyOffset == null
          ? 16 +
                entry.top +
                (entry.bottom - entry.top) * (target - index) -
                position.viewportDimension / 2
          : position.pixels + bodyOffset - position.viewportDimension / 2;
      _pendingSeek = null;
      widget.controller.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      _scheduleUpdate();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool get hasLater =>
      _end < widget.messages.length ||
      (widget.messages.isNotEmpty &&
          _content.hasLaterFor(widget.messages.last.id));
  bool get hasEarlier => _start > 0 || _content.hasEarlier;
  bool get hasUnloadedContent => _content.hasEarlier || _content.hasLater;
  int get loadedMessageCount => _end - _start;

  void selectionChanged() {
    _content.selectionChanged();
    _scheduleUpdate();
  }

  ChatContentRegistry _createContentRegistry() => ChatContentRegistry(
    controller: widget.controller,
    storageId: widget.historyId,
    followsLatest: () => widget.followsLatest(),
    hasSelection: () => widget.hasSelection(),
    isSeeking: () => _pendingSeek != null,
    onChanged: () => widget.onContentRangeChanged?.call(),
  );

  Object get _storageId => ValueKey('chat-window-${widget.historyId}');

  @override
  void initState() {
    super.initState();
    _content = _createContentRegistry();
    widget.controller.addListener(_scheduleUpdate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) _reset();
  }

  @override
  void didUpdateWidget(ChatHistoryWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleUpdate);
      widget.controller.addListener(_scheduleUpdate);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.historyId != widget.historyId) {
      _content.dispose();
      _content = _createContentRegistry();
    }
    final messages = widget.messages;
    if (widget.historyId != oldWidget.historyId ||
        messages.length < _knownCount ||
        messages.firstOrNull?.id != _firstId) {
      _reset();
    } else if (messages.length != _knownCount) {
      if ((_end == _knownCount || _pendingTail) && widget.followsLatest()) {
        if (_trackPointers.isEmpty) {
          _includeLatestMessages();
        } else {
          _pendingTail = true;
        }
      }
      _knownCount = messages.length;
    }
    _scheduleUpdate();
  }

  void _reset() {
    _pendingSeek = null;
    final messages = widget.messages;
    _knownCount = messages.length;
    _firstId = messages.firstOrNull?.id;
    final saved = PageStorage.maybeOf(context)
        ?.readState(context, identifier: _storageId);
    if (saved is _SavedHistoryWindow &&
        saved.firstId == _firstId &&
        saved.end <= messages.length &&
        saved.start >= 0 &&
        saved.start < saved.end) {
      _start = saved.start;
      _end = saved.end;
    } else {
      _end = messages.length;
      _start = math.max(0, _end - initialMessages);
    }
    _geometry = const [];
    _anchor = null;
    _pendingTail = false;
    _initialized = true;
    _scheduleUpdate();
  }

  void showLatest() {
    if (!mounted) return;
    _pendingSeek = null;
    _content.showLatest();
    if (_end == widget.messages.length) return;
    setState(() {
      _anchor = null;
      _pendingTail = false;
      _end = widget.messages.length;
      _start = math.max(0, _end - initialMessages);
    });
  }

  void _includeLatestMessages() {
    _pendingTail = false;
    final nextEnd = widget.messages.length;
    if (nextEnd - _start > maximumMessages && !widget.hasSelection()) {
      _rememberAnchor();
      _start = math.max(0, nextEnd - maximumMessages);
    }
    _end = nextEnd;
  }

  void _saveLaidOutRange() {
    final range = _SavedHistoryWindow(_firstId, _start, _end);
    final historyId = widget.historyId;
    final storageId = _storageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _pendingSeek != null ||
          historyId != widget.historyId ||
          range.firstId != widget.messages.firstOrNull?.id ||
          range.end > widget.messages.length ||
          !widget.controller.hasClients) {
        return;
      }
      widget.controller.saveHistoryOffset();
      PageStorage.maybeOf(context)
          ?.writeState(context, range, identifier: storageId);
    });
  }

  void _rememberAnchor() {
    if (_anchor != null || !widget.controller.hasClients || _geometry.isEmpty) {
      return;
    }
    final top = widget.controller.offset - 16;
    final entry = _geometry.firstWhere(
      (entry) => entry.bottom > top,
      orElse: () => _geometry.last,
    );
    final index = entry.index;
    if (index < widget.messages.length) {
      _anchor = (widget.messages[index].id, entry.top);
    }
  }

  void _handleLayout(List<ChatMessageGeometry> geometry) {
    _geometry = geometry;
    if (_anchor case final anchor?) {
      _anchor = null;
      for (final entry in geometry) {
        if (widget.messages[entry.index].id == anchor.$1) {
          final correction = entry.top - anchor.$2;
          if (correction != 0 && widget.controller.hasClients) {
            widget.controller.correctForHistoryChange(correction);
          }
          break;
        }
      }
    }
    _saveLaidOutRange();
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    if (_updatePending || !mounted) return;
    _updatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePending = false;
      if (!mounted ||
          _pendingSeek != null ||
          !widget.controller.hasClients ||
          _trackPointers.isNotEmpty) {
        return;
      }
      final position = widget.controller.position;
      if (!position.hasContentDimensions || !position.hasViewportDimension) {
        return;
      }
      if (_pendingTail) {
        _pendingTail = false;
        if (widget.followsLatest() && hasLater) {
          setState(_includeLatestMessages);
          return;
        }
      }
      final scrolling = position.isScrollingNotifier.value;
      final idleMargin = position.viewportDimension * preloadScreens;
      final margin = scrolling ? idleMargin / 2 : idleMargin;
      final velocity = scrolling ? widget.controller.scrollVelocity : 0.0;
      final lookAhead = (velocity * .12).clamp(-idleMargin * 2, idleMargin * 2);
      final earlier =
          _start > 0 && position.extentBefore < math.max(margin, -lookAhead);
      final later =
          _end < widget.messages.length &&
          position.extentAfter < math.max(margin, lookAhead);
      final retainSelection = widget.hasSelection();
      if (!earlier &&
          !later &&
          (scrolling ||
              retainSelection ||
              loadedMessageCount <= maximumMessages)) {
        return;
      }
      final loadEarlier =
          earlier && (!later || position.extentBefore < position.extentAfter);
      final remaining = loadEarlier
          ? position.extentBefore
          : position.extentAfter;
      final fastScroll = lookAhead.abs() > margin;
      final retainMargin = fastScroll ? idleMargin : idleMargin * 2;
      var preferredBatch = scrolling ? 2 : batchMessages;
      if (_geometry.isNotEmpty &&
          (loadEarlier ? -lookAhead : lookAhead) > margin) {
        final averageHeight = math.max(
          1,
          (_geometry.last.bottom - _geometry.first.top) / _geometry.length,
        );
        preferredBatch = (lookAhead.abs() / (3 * averageHeight)).ceil().clamp(
          preferredBatch,
          _maximumBatch,
        );
      }
      final batch = remaining < position.viewportDimension / 2
          ? _maximumBatch
          : preferredBatch;
      final oldestRetained = _geometry
          .where(
            (entry) =>
                entry.bottom <= position.extentBefore - retainMargin - 16,
          )
          .lastOrNull;
      final newestRetained = _geometry
          .where(
            (entry) =>
                entry.top >=
                position.extentBefore +
                    position.viewportDimension +
                    retainMargin -
                    16,
          )
          .firstOrNull;
      final safeStart = oldestRetained == null
          ? _start
          : oldestRetained.index + 1;
      final safeEnd = newestRetained == null ? _end : newestRetained.index;
      var nextStart = _start;
      var nextEnd = _end;
      if (loadEarlier) {
        nextStart = math.max(0, _start - batch);
        if (nextEnd - nextStart > maximumMessages && !retainSelection) {
          nextEnd = math.min(
            nextEnd,
            math.max(nextStart + maximumMessages, safeEnd),
          );
        }
      } else if (later) {
        nextEnd = math.min(widget.messages.length, _end + batch);
        if (nextEnd - nextStart > maximumMessages && !retainSelection) {
          nextStart = math.max(
            nextStart,
            math.min(nextEnd - maximumMessages, safeStart),
          );
        }
      } else {
        nextStart = math.min(
          safeStart,
          math.max(_start, safeEnd - maximumMessages),
        );
        nextEnd = math.max(
          safeEnd,
          math.min(_end, nextStart + maximumMessages),
        );
      }
      if (nextStart == _start && nextEnd == _end) return;
      _rememberAnchor();
      setState(() {
        _start = nextStart;
        _end = nextEnd;
      });
    });
  }

  @override
  void dispose() {
    _content.dispose();
    widget.controller.removeListener(_scheduleUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.controller.hasUnloadedBefore = _start > 0;
    widget.controller.hasUnloadedAfter = _end < widget.messages.length;
    final loaded = widget.messages.getRange(_start, _end);
    widget.onRangeChanged({for (final message in loaded) message.id});
    return ChatContentScope(
      state: _content,
      child: Listener(
        onPointerDown: (event) {
          _content.pointerDown(event);
          final render = context.findRenderObject();
          if (event.kind == PointerDeviceKind.mouse &&
              event.buttons == kPrimaryMouseButton &&
              render is RenderBox &&
              event.localPosition.dx >= render.size.width - 24) {
            _trackPointers.add(event.pointer);
          }
        },
        onPointerUp: (event) {
          _content.pointerUp(event);
          _trackPointers.remove(event.pointer);
          _scheduleUpdate();
        },
        onPointerCancel: (event) {
          _content.pointerCancel(event);
          _trackPointers.remove(event.pointer);
          _scheduleUpdate();
        },
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification.metrics.axis == Axis.vertical) {
              _scheduleUpdate();
              WidgetsBinding.instance.ensureVisualUpdate();
            }
            return false;
          },
          child: _viewport(
            widget.viewportBuilder(
              context,
              ChatMessageList(
                firstIndex: _start,
                onLayout: _handleLayout,
                children: [
                  for (final message in loaded)
                    ChatContentMessageScope(
                      key: ValueKey(('chat-content-message', message.id)),
                      messageId: message.id,
                      child: widget.itemBuilder(message),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _viewport(Widget child) => widget.scrollbar
      ? ChatHistoryScrollbar(
          key: ValueKey(('history-scrollbar', widget.historyId)),
          controller: widget.controller,
          readLogicalFraction: _logicalScrollFraction,
          seek: _seek,
          isSeeking: () => _pendingSeek != null,
          readUnits: () =>
              math.max(widget.messages.length, _content.navigationUnits),
          usesLogicalNavigation: () => _usesLogicalNavigation,
          child: child,
        )
      : child;
}

class _SavedHistoryWindow {
  const _SavedHistoryWindow(this.firstId, this.start, this.end);

  final String? firstId;
  final int start;
  final int end;
}
