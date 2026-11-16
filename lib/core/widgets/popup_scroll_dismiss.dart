import 'package:material_ui/material_ui.dart';

/// 滚动导致触发控件移动时，关闭锚定的弹出菜单。
///
/// 仅监听触发控件的祖先滚动容器；浮层内部的内容
/// 应能正常滚动，而不会关闭弹出菜单。
class PopupScrollDismiss {
  PopupScrollDismiss({required this.onScroll});

  final VoidCallback onScroll;
  final _positions = <ScrollPosition>{};

  void attach(BuildContext context) {
    detach();
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        if (_positions.add(position)) position.addListener(onScroll);
      }
      return true;
    });
  }

  void detach() {
    for (final position in _positions) {
      position.removeListener(onScroll);
    }
    _positions.clear();
  }
}
