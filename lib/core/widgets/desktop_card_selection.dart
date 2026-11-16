/*
 * @Description: 桌面卡片列表选择与键盘操作，隔离输入框的文字快捷键。
 */
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 选区遵循当前可见项的顺序，由调用方负责重建。
class DesktopCardSelection {
  final Set<String> selected = {};
  String? anchor;

  void select(
    String id,
    List<String> visibleIds, {
    bool control = false,
    bool shift = false,
  }) {
    final index = visibleIds.indexOf(id);
    if (index < 0) return;
    final start = anchor == null ? -1 : visibleIds.indexOf(anchor!);
    if (shift && start >= 0) {
      if (!control) selected.clear();
      selected.addAll(
        visibleIds.sublist(
          start < index ? start : index,
          (start > index ? start : index) + 1,
        ),
      );
    } else {
      if (control) {
        if (!selected.remove(id)) selected.add(id);
      } else {
        selected
          ..clear()
          ..add(id);
      }
      anchor = id;
    }
  }

  void selectAll(Iterable<String> ids) {
    final visible = ids.toList();
    selected
      ..clear()
      ..addAll(visible);
    if (!visible.contains(anchor)) anchor = visible.firstOrNull;
  }

  void clear() {
    selected.clear();
    anchor = null;
  }

  void retain(Iterable<String> ids) {
    final visible = ids.toSet();
    selected.retainAll(visible);
    if (!visible.contains(anchor)) anchor = null;
  }
}

/// 快捷键仅作用于列表的焦点子树，文本编辑器除外。
class DesktopCardSelectionRegion extends StatelessWidget {
  const DesktopCardSelectionRegion({
    super.key,
    required this.focusNode,
    required this.selection,
    required this.ids,
    required this.onChanged,
    required this.onDelete,
    required this.child,
    this.enabled = true,
  });

  final FocusNode focusNode;
  final DesktopCardSelection selection;
  final List<String> ids;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;
  final Widget child;
  final bool enabled;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
    final primaryContext = FocusManager.instance.primaryFocus?.context;
    if (primaryContext?.findAncestorStateOfType<EditableTextState>() != null) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed) return KeyEventResult.ignored;
    if ((keyboard.isControlPressed || keyboard.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
      selection.selectAll(ids);
      onChanged();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        selection.selected.isNotEmpty) {
      selection.clear();
      onChanged();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isShiftPressed &&
        selection.selected.isNotEmpty &&
        onDelete != null) {
      onDelete!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => _DesktopCardSelectionScope(
    region: this,
    child: Focus(focusNode: focusNode, onKeyEvent: _handleKey, child: child),
  );
}

/// 卡片及其操作共用点击分组，点击周围空白处清除选区。
class DesktopCardSelectionTarget extends StatelessWidget {
  const DesktopCardSelectionTarget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final region = context
        .dependOnInheritedWidgetOfExactType<_DesktopCardSelectionScope>()!
        .region;
    return TapRegion(
      groupId: region.selection,
      onTapOutside: (_) {
        // 上层确认框关闭前，由其独占鼠标输入。
        if (!region.enabled ||
            ModalRoute.of(context)?.isCurrent == false ||
            region.selection.selected.isEmpty) {
          return;
        }
        region.selection.clear();
        region.onChanged();
      },
      child: child,
    );
  }
}

class _DesktopCardSelectionScope extends InheritedWidget {
  const _DesktopCardSelectionScope({
    required this.region,
    required super.child,
  });

  final DesktopCardSelectionRegion region;

  @override
  bool updateShouldNotify(_DesktopCardSelectionScope oldWidget) =>
      oldWidget.region != region;
}
