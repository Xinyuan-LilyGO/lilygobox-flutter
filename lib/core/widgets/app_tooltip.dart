/*
 * @Description: 统一悬停提示的间距与延迟，隐藏页面时清理提示浮层。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 17:16:37
 * @LastEditTime: 2026-10-01 17:19:32
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

/// 共用悬停提示，文案由调用处提供本地化文本。
class AppTooltip extends StatefulWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
    this.verticalOffset,
  });

  static const Duration waitDuration = Duration(milliseconds: 500);

  final String message;
  final Widget child;
  final double? verticalOffset;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  // 提示重建时保留按钮自身状态，避免影响点击反馈及内部控件。
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final active =
        TickerMode.of(context) &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TooltipVisibility.of(context);
    return Tooltip(
      // 隐藏页面会停止 Ticker，不能等待 Tooltip 淡出后再移除浮层。
      // 更换提示状态可立即释放浮层和待显示计时器，返回页面时重新计时。
      key: ValueKey(active),
      message: active ? widget.message : '',
      waitDuration: AppTooltip.waitDuration,
      ignorePointer: true,
      verticalOffset: (widget.verticalOffset ?? 24) + 4,
      child: KeyedSubtree(key: _childKey, child: widget.child),
    );
  }
}
