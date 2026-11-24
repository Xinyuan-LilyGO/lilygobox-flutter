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
    this.windowSemantics = false,
  }) : super(mainAxisSize: MainAxisSize.min);

  final int firstIndex;
  final ValueChanged<List<ChatMessageGeometry>>? onLayout;
  final bool windowSemantics;

  ScrollPosition? _semanticsPosition(BuildContext context) => windowSemantics
      ? Scrollable.maybeOf(context, axis: Axis.vertical)?.position
      : null;

  @override
  RenderFlex createRenderObject(BuildContext context) => _RenderChatMessageList(
    crossAxisAlignment: crossAxisAlignment,
    textDirection: Directionality.maybeOf(context),
    firstIndex: firstIndex,
    onLayout: onLayout,
    semanticsPosition: _semanticsPosition(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderFlex renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _RenderChatMessageList)
      ..firstIndex = firstIndex
      ..onLayout = onLayout
      ..semanticsPosition = _semanticsPosition(context);
  }
}

typedef ChatMessageGeometry = ({int index, double top, double bottom});

class _RenderChatMessageList extends RenderFlex {
  _RenderChatMessageList({
    required super.crossAxisAlignment,
    required this._firstIndex,
    super.textDirection,
    this.onLayout,
    this._semanticsPosition,
  }) : super(direction: Axis.vertical, mainAxisSize: MainAxisSize.min);

  final _children = <(RenderBox, Offset, double)>[];
  ValueChanged<List<ChatMessageGeometry>>? onLayout;
  int _firstIndex;
  bool _layoutCacheReady = false;
  ScrollPosition? _semanticsPosition;

  set semanticsPosition(ScrollPosition? value) {
    if (identical(value, _semanticsPosition)) return;
    if (attached) _semanticsPosition?.removeListener(markNeedsSemanticsUpdate);
    _semanticsPosition = value;
    if (attached) _semanticsPosition?.addListener(markNeedsSemanticsUpdate);
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _semanticsPosition?.addListener(markNeedsSemanticsUpdate);
  }

  @override
  void detach() {
    _semanticsPosition?.removeListener(markNeedsSemanticsUpdate);
    super.detach();
  }

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
    _layoutCacheReady = true;
    onLayout?.call(geometry);
  }

  @override
  void markNeedsLayout() {
    _layoutCacheReady = false;
    super.markNeedsLayout();
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

  bool _childrenAreReady() {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (!child.attached || !identical(child.parent, this) || !child.hasSize) {
        return false;
      }
    }
    return true;
  }

  Rect? _viewportBounds({required bool stopAtRepaintBoundary}) {
    Rect? visible;
    for (var ancestor = parent; ancestor != null; ancestor = ancestor.parent) {
      if (ancestor is RenderAbstractViewport) {
        final transform = getTransformTo(ancestor);
        final determinant = transform.determinant();
        if (!determinant.isFinite || determinant.abs() < 1e-8) {
          return null;
        }
        final bounds = MatrixUtils.inverseTransformRect(
          transform,
          ancestor.paintBounds,
        );
        if (!bounds.top.isFinite ||
            !bounds.bottom.isFinite ||
            !bounds.left.isFinite ||
            !bounds.right.isFinite) {
          return null;
        }
        visible = visible?.intersect(bounds) ?? bounds;
      }
      if (stopAtRepaintBoundary && ancestor.isRepaintBoundary) break;
    }
    return visible;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final visible = _layoutCacheReady && _semanticsPosition != null
        ? _viewportBounds(stopAtRepaintBoundary: false)
        : null;
    if (visible == null || visible.isEmpty) {
      super.visitChildrenForSemantics(visitor);
      return;
    }
    final range = visible.inflate(visible.height);
    for (
      var index = _firstChildAfter(range.top);
      index < _children.length;
      index++
    ) {
      final (child, childOffset, _) = _children[index];
      if (childOffset.dy >= range.bottom) break;
      visitor(child);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_layoutCacheReady) {
      if (_childrenAreReady()) super.paint(context, offset);
      return;
    }
    final visible = _viewportBounds(stopAtRepaintBoundary: true);
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
    if (!_layoutCacheReady) {
      return _childrenAreReady()
          ? super.hitTestChildren(result, position: position)
          : false;
    }
    final index = _firstChildAfter(position.dy);
    if (index == _children.length) return false;
    final (child, offset, _) = _children[index];
    if (position.dy < offset.dy ||
        position.dy > offset.dy + child.size.height) {
      return false;
    }
    return result.addWithPaintOffset(
      offset: offset,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }
}
