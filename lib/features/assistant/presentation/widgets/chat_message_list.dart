import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays out every child for an exact scroll range, but only visits the visible
/// portion when painting. Children remain available to the shared selection.
class ChatMessageList extends Column {
  const ChatMessageList({
    super.key,
    super.children,
    super.crossAxisAlignment,
    this.firstIndex = 0,
    this.onLayout,
  }) : super(mainAxisSize: MainAxisSize.min);

  final int firstIndex;
  final ValueChanged<List<ChatMessageGeometry>>? onLayout;

  @override
  RenderFlex createRenderObject(BuildContext context) => _RenderChatMessageList(
    crossAxisAlignment: crossAxisAlignment,
    textDirection: Directionality.maybeOf(context),
    firstIndex: firstIndex,
    onLayout: onLayout,
  );

  @override
  void updateRenderObject(BuildContext context, RenderFlex renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _RenderChatMessageList)
      ..firstIndex = firstIndex
      ..onLayout = onLayout;
  }
}

typedef ChatMessageGeometry = ({int index, double top, double bottom});

class _RenderChatMessageList extends RenderFlex {
  _RenderChatMessageList({
    required super.crossAxisAlignment,
    required this._firstIndex,
    super.textDirection,
    this.onLayout,
  }) : super(direction: Axis.vertical, mainAxisSize: MainAxisSize.min);

  final _children = <(RenderBox, Offset, double)>[];
  ValueChanged<List<ChatMessageGeometry>>? onLayout;
  int _firstIndex;

  set firstIndex(int value) {
    if (_firstIndex == value) return;
    _firstIndex = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    _children.clear();
    final geometry = <ChatMessageGeometry>[];
    var index = _firstIndex;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final offset = (child.parentData! as FlexParentData).offset;
      final bottom = offset.dy + child.size.height;
      if (child.size.height != 0) _children.add((child, offset, bottom));
      if (onLayout != null) {
        geometry.add((index: index, top: offset.dy, bottom: bottom));
      }
      index++;
    }
    onLayout?.call(geometry);
  }

  int _firstChildAfter(double top) {
    var low = 0;
    var high = _children.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_children[middle].$3 <= top) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    Rect? visible;
    for (var ancestor = parent; ancestor != null; ancestor = ancestor.parent) {
      if (ancestor is RenderAbstractViewport) {
        final bounds = MatrixUtils.inverseTransformRect(
          getTransformTo(ancestor),
          ancestor.paintBounds,
        );
        visible = visible?.intersect(bounds) ?? bounds;
      }
      if (ancestor.isRepaintBoundary) break;
    }
    if (visible == null) {
      super.paint(context, offset);
      return;
    }
    for (
      var index = _firstChildAfter(visible.top);
      index < _children.length;
      index++
    ) {
      final (child, childOffset, _) = _children[index];
      if (childOffset.dy >= visible.bottom) break;
      context.paintChild(child, offset + childOffset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final index = _firstChildAfter(position.dy);
    if (index == _children.length) return false;
    final (child, offset, _) = _children[index];
    return result.addWithPaintOffset(
      offset: offset,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }
}
