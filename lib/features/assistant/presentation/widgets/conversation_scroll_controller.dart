import 'package:flutter/widgets.dart';

import '../../../../core/widgets/app_scroll_behavior.dart';

/// 打开历史时默认定位最新消息；已有有效阅读位置则恢复该位置。
class ConversationScrollController extends WindowedScrollController {
  ConversationScrollController({this.pinToLatest});

  final bool Function()? pinToLatest;

  bool get _shouldPinToLatest =>
      !hasUnloadedAfter && (pinToLatest?.call() ?? false);

  double get scrollVelocity =>
      hasClients && position is _ConversationScrollPosition
      ? (position as _ConversationScrollPosition).scrollVelocity
      : 0;

  void correctForHistoryChange(double correction) {
    if (!hasClients || positions.length != 1) return;
    final current = position;
    if (current is! _ConversationScrollPosition || !current.hasPixels) return;
    if (current.pinsLatest) return;
    AppScrollBehavior.correctForContentChange(current, correction);
  }

  void saveHistoryOffset() {
    if (!hasClients || positions.length != 1) return;
    final current = position;
    if (current is _ConversationScrollPosition) {
      current.saveCorrectedOffset();
    }
  }

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
    shouldPinToLatest: () => _shouldPinToLatest,
  );
}

class _ConversationScrollPosition extends ScrollPositionWithSingleContext {
  _ConversationScrollPosition({
    required super.physics,
    required super.context,
    required this.shouldPinToLatest,
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
  final bool Function() shouldPinToLatest;

  bool get pinsLatest => _initialPositionResolved && shouldPinToLatest();

  double get scrollVelocity => activity?.velocity ?? 0;

  void saveCorrectedOffset() => saveScrollOffset();

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
    } else if (pinsLatest && pixels != maxScrollExtent) {
      correctPixels(maxScrollExtent);
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }

  @override
  bool correctForNewDimensions(
    ScrollMetrics oldPosition,
    ScrollMetrics newPosition,
  ) => pinsLatest || super.correctForNewDimensions(oldPosition, newPosition);
}
