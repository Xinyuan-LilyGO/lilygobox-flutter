import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/context_menu/text_selection_menu.dart';
import '../../domain/models.dart';

class ChatHistorySelection extends StatefulWidget {
  const ChatHistorySelection({
    super.key,
    required this.focusNode,
    required this.messages,
    required this.hasUnloadedMessages,
    required this.child,
    this.onSelectionChanged,
  });

  final FocusNode focusNode;
  final List<AiMessage> messages;
  final bool Function() hasUnloadedMessages;
  final Widget child;
  final VoidCallback? onSelectionChanged;

  @override
  State<ChatHistorySelection> createState() => ChatHistorySelectionState();
}

class ChatHistorySelectionState extends State<ChatHistorySelection> {
  bool _allSelected = false;
  bool hasSelection = false;

  Future<void> _copyAll() async {
    final contents = [for (final message in widget.messages) message.content];
    final text = contents.length < 1024
        ? _joinMessages(contents)
        : await compute(_joinMessages, contents);
    await Clipboard.setData(ClipboardData(text: text));
  }

  Widget _contextMenu(BuildContext context, SelectableRegionState region) =>
      AppTextSelectionMenu.buildRegionWithActions(
        context,
        region,
        onSelectAll: () {
          region.selectAll();
          _allSelected = widget.hasUnloadedMessages();
          region.hideToolbar();
        },
        onCopy: _allSelected && widget.hasUnloadedMessages()
            ? () {
                unawaited(_copyAll());
                region.hideToolbar();
              }
            : null,
      );

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      SelectAllTextIntent: _HistorySelectAllAction(
        () => _allSelected = widget.hasUnloadedMessages(),
      ),
      CopySelectionTextIntent: _HistoryCopyAction(
        () => _allSelected && widget.hasUnloadedMessages(),
        _copyAll,
      ),
    },
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey != LogicalKeyboardKey.controlLeft &&
            event.logicalKey != LogicalKeyboardKey.controlRight &&
            event.logicalKey != LogicalKeyboardKey.shiftLeft &&
            event.logicalKey != LogicalKeyboardKey.shiftRight &&
            event.logicalKey != LogicalKeyboardKey.keyC &&
            event.logicalKey != LogicalKeyboardKey.keyA) {
          _allSelected = false;
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kPrimaryMouseButton) _allSelected = false;
        },
        child: SelectionArea(
          focusNode: widget.focusNode,
          onSelectionChanged: (content) {
            final previous = hasSelection;
            hasSelection = content != null && content.plainText.isNotEmpty;
            if (!hasSelection) _allSelected = false;
            if (previous != hasSelection) widget.onSelectionChanged?.call();
          },
          contextMenuBuilder: _contextMenu,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

String _joinMessages(List<String> contents) => contents.join('\n\n');

class _HistorySelectAllAction extends Action<SelectAllTextIntent> {
  _HistorySelectAllAction(this.onSelectAll);

  final VoidCallback onSelectAll;

  @override
  Object? invoke(SelectAllTextIntent intent) {
    final result = callingAction?.invoke(intent);
    onSelectAll();
    return result;
  }
}

class _HistoryCopyAction extends Action<CopySelectionTextIntent> {
  _HistoryCopyAction(this.allSelected, this.copyAll);

  final bool Function() allSelected;
  final Future<void> Function() copyAll;

  @override
  Object? invoke(CopySelectionTextIntent intent) =>
      allSelected() ? copyAll() : callingAction?.invoke(intent);
}
