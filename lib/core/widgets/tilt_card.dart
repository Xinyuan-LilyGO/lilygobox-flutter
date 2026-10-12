/*
 * @Description: 为可进入页面的卡片提供轻微鼠标倾斜与离开回正效果。
 * @Author: LILYGO_L
 * @Date: 2026-10-12 00:00:00
 * @LastEditTime: 2026-10-12 00:00:00
 * @License: GPL 3.0
 */

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 内容随卡片整体倾斜，布局和点击区域保持稳定。
class TiltCard extends StatefulWidget {
  const TiltCard({super.key, required this.child});

  final Widget child;

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> {
  static const _maxAngle = 8 * math.pi / 180;
  Offset _target = Offset.zero;

  /// 根据未变换的卡片区域计算偏移，避免边缘倾斜引起悬停抖动。
  void _followPointer(PointerHoverEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    final position = box.globalToLocal(event.position);
    final next = Offset(
      (position.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0),
      (position.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0),
    );
    if ((_target - next).distance < .01) return;
    setState(() => _target = next);
  }

  /// 鼠标离开后平滑回正，不改变卡片尺寸或内部文字的位置。
  void _resetTilt(PointerExitEvent event) {
    if (_target == Offset.zero) return;
    setState(() => _target = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onHover: _followPointer,
      onExit: _resetTilt,
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(
          begin: Offset.zero,
          end: reduceMotion ? Offset.zero : _target,
        ),
        duration: reduceMotion
            ? Duration.zero
            : Duration(milliseconds: _target == Offset.zero ? 220 : 100),
        curve: Curves.easeOutCubic,
        // 鼠标移动仅重绘变换，复用卡片内容，不重建整个页面。
        child: RepaintBoundary(child: widget.child),
        builder: (context, offset, child) => Transform(
          alignment: Alignment.center,
          transformHitTests: false,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0007)
            // 鼠标所在一侧向内下陷，另一侧抬起。
            ..rotateX(offset.dy * _maxAngle)
            ..rotateY(-offset.dx * _maxAngle),
          child: child,
        ),
      ),
    );
  }
}
