/*
 * @Description: 为被选中的真实空行绘制窄高亮，不改变文本或选区。
 * @Author: LILYGO_L
 * @Date: 2026-11-13 17:42:49
 * @LastEditTime: 2026-11-13 17:42:49
 */

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 补充 tight 选区中零宽换行的视觉反馈，不注入占位字符。
class EmptyLineSelection extends SingleChildRenderObjectWidget {
  const EmptyLineSelection({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _EmptyLineSelectionRender();
}

Iterable<int> _selectedEmptyLines(String text, TextSelection selection) sync* {
  if (!selection.isValid || selection.isCollapsed) return;
  final end = selection.end.clamp(0, text.length);
  for (var i = selection.start.clamp(0, text.length); i < end; i++) {
    if (text.codeUnitAt(i) != 10) continue;
    final previous = i > 0 && text.codeUnitAt(i - 1) == 13 ? i - 2 : i - 1;
    if (previous < 0 || text.codeUnitAt(previous) == 10) yield i;
  }
}

Rect _marker(Rect line, TextDirection direction) {
  final width = (line.height * .22).clamp(3.0, 6.0);
  return Rect.fromLTWH(
    direction == TextDirection.rtl ? line.left - width : line.left,
    line.top,
    width,
    line.height,
  );
}

class _EmptyLinePainter extends RenderEditablePainter {
  @override
  void paint(Canvas canvas, Size size, RenderEditable editable) {
    final selection = editable.selection;
    final color = editable.selectionColor;
    if (selection == null || color == null || editable.obscureText) return;
    final paint = Paint()..color = color;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final offset in _selectedEmptyLines(editable.plainText, selection)) {
      final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
      canvas.drawRect(_marker(caret, editable.textDirection), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RenderEditablePainter? oldDelegate) => false;
}

class _EmptyLineSelectionRender extends RenderProxyBox {
  final _painter = _EmptyLinePainter();
  final _editables = <RenderEditable>{};

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    _editables.removeWhere((editable) => !editable.attached);
    void install(RenderObject object) {
      if (object is RenderEditable && object.foregroundPainter == null) {
        object.foregroundPainter = _painter;
        _editables.add(object);
      }
      object.visitChildren(install);
    }

    child?.visitChildren(install);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    void highlight(RenderObject object) {
      if (object is RenderParagraph && object.selectionColor != null) {
        // Flutter 公开只读的 selections 用于检查段落片段，避免干预选择协议。
        // ignore: invalid_use_of_visible_for_testing_member
        for (final selection in object.selections) {
          for (final position in _selectedEmptyLines(
            object.text.toPlainText(),
            selection,
          )) {
            final boxes = object.getBoxesForSelection(
              TextSelection(baseOffset: position, extentOffset: position + 1),
            );
            for (final box in boxes) {
              if (box.right != box.left) continue;
              final origin = object.localToGlobal(Offset.zero, ancestor: this);
              context.canvas.drawRect(
                _marker(box.toRect(), box.direction).shift(offset + origin),
                Paint()..color = object.selectionColor!,
              );
            }
          }
        }
      }
      object.visitChildren(highlight);
    }

    child?.visitChildren(highlight);
  }

  @override
  void detach() {
    for (final editable in _editables) {
      if (editable.attached &&
          identical(editable.foregroundPainter, _painter)) {
        editable.foregroundPainter = null;
      }
    }
    _editables.clear();
    super.detach();
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
