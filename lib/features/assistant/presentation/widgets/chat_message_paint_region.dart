import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 保留完整的消息布局与选区，同时跳过视口外的绘制层，
/// 适用于一次性完成布局的聊天历史。
class ChatMessagePaintRegion extends SingleChildRenderObjectWidget {
  const ChatMessagePaintRegion({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderChatMessagePaintRegion();
}

class _RenderChatMessagePaintRegion extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport != null) {
      // 使用视口坐标变换判断可见范围；合成的
      // ClipRect 层不一定会在录制画布上设置裁剪区域。
      final bounds = MatrixUtils.transformRect(
        getTransformTo(viewport),
        paintBounds,
      );
      if (!bounds.overlaps(viewport.paintBounds)) return;
    }
    super.paint(context, offset);
  }
}
