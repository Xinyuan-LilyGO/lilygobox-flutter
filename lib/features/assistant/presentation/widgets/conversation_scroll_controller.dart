import 'package:flutter/widgets.dart';

/// 打开历史时默认定位最新消息；已有有效阅读位置则恢复该位置。
class ConversationScrollController extends ScrollController {
  bool get initiallyFollowsLatest =>
      !hasClients ||
      (position as _ConversationScrollPosition).initiallyFollowsLatest;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _ConversationScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _ConversationScrollPosition extends ScrollPositionWithSingleContext {
  _ConversationScrollPosition({
    required super.physics,
    required super.context,
    ScrollPosition? oldPosition,
  }) : super(oldPosition: oldPosition) {
    if (oldPosition != null && oldPosition.hasPixels) {
      _initialPositionResolved = true;
      initiallyFollowsLatest =
          oldPosition.hasContentDimensions && oldPosition.extentAfter <= 1;
    }
  }

  double? _savedOffset;
  bool _initialPositionResolved = false;
  bool initiallyFollowsLatest = true;

  @override
  void restoreScrollOffset() {
    if (hasPixels) return;
    final saved = PageStorage.maybeOf(context.storageContext)
        ?.readState(context.storageContext);
    // 视口布局前拒绝格式错误或非有限的位置值。
    if (saved is num && saved.isFinite) {
      _savedOffset = saved.toDouble();
      correctPixels(_savedOffset!);
    }
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (!_initialPositionResolved) {
      _initialPositionResolved = true;
      final saved = _savedOffset;
      final valid =
          saved != null && saved >= minScrollExtent && saved <= maxScrollExtent;
      final target = valid ? saved : maxScrollExtent;
      initiallyFollowsLatest = maxScrollExtent - target <= 1;
      if (pixels != target) {
        // 聊天布局已包含完整滚动范围；提交尺寸之前设置
        // 首次绘制位置，无需额外等待一帧。
        correctPixels(target);
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
