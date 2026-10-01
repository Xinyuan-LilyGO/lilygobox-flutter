/*
 * @Description: 实现主侧栏拖动调宽、折叠展开动画及连续拖动接管。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/provider.dart';

/// 主导航的拖动区域独立于内容页分栏，避免两种宽度互相影响。
class ResizableSidebar extends StatefulWidget {
  const ResizableSidebar({
    super.key,
    required this.sidebar,
    required this.content,
  });

  final Widget sidebar;
  final Widget content;

  @override
  State<ResizableSidebar> createState() => _ResizableSidebarState();
}

class _ResizableSidebarState extends State<ResizableSidebar> {
  static const double _dragTargetWidth = 6;
  double _dragStartX = 0;
  double _dragStartWidth = 0;
  double _dragWidth = 0;
  bool _isDragging = false;
  bool _animateDragTransition = false;

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<AppShellProvider>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = (constraints.maxWidth * .4)
            .clamp(
              AppShellProvider.minSidebarWidth,
              AppShellProvider.maxSidebarWidth,
            )
            .toDouble();
        final expandedWidth = math.min(shell.sidebarWidth, maxWidth);
        final targetWidth = _isDragging && !_animateDragTransition
            ? _dragWidth
            : shell.isSidebarVisible
            ? expandedWidth
            : 0.0;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: targetWidth, end: targetWidth),
          duration:
              (_isDragging && !_animateDragTransition) ||
                  MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : _animateDragTransition
              ? const Duration(milliseconds: 160)
              : const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          onEnd: () {
            if (_animateDragTransition) {
              // 一次折叠/展开完成后，同一次按住拖动也要恢复即时调整宽度。
              setState(() => _animateDragTransition = false);
            }
          },
          builder: (context, width, child) => Stack(
            children: [
              Row(
                children: [
                  SizedBox(
                    key: const ValueKey('sidebar-panel'),
                    width: width,
                    child: ClipRect(
                      child: Offstage(
                        offstage: width <= 0,
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: math.max(width, expandedWidth),
                          maxWidth: math.max(width, expandedWidth),
                          // 动画只裁剪可见宽度，不挤压文字，也不销毁侧栏状态。
                          // 反向拖动时外层仍可能较宽，内容必须覆盖整个可见区域。
                          child: IgnorePointer(
                            ignoring: !shell.isSidebarVisible,
                            child: ExcludeFocus(
                              excluding: !shell.isSidebarVisible,
                              child: widget.sidebar,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: widget.content),
                ],
              ),
              // 与 ResizableSplitView 一样使用覆盖式命中区域，不占内容宽度。
              Positioned(
                left: math.max(0, width - _dragTargetWidth / 2),
                top: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    key: const ValueKey('sidebar-resize-handle'),
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragDown: (details) {
                      _dragStartX = details.globalPosition.dx;
                      _dragStartWidth = width;
                      setState(() {
                        // 从屏幕上的实际宽度接管，不能沿用展开动画的目标宽度。
                        _dragWidth = width;
                        _isDragging = true;
                        _animateDragTransition = false;
                      });
                    },
                    onHorizontalDragEnd: (_) =>
                        setState(() => _isDragging = false),
                    onHorizontalDragCancel: () =>
                        setState(() => _isDragging = false),
                    onHorizontalDragUpdate: (details) {
                      // 使用未钳制的总位移，达到最小宽度后仍能继续向左折叠。
                      final wasVisible = shell.isSidebarVisible;
                      shell.resizeSidebar(
                        _dragStartWidth +
                            details.globalPosition.dx -
                            _dragStartX,
                        maxWidth: maxWidth,
                      );
                      // 仅越过阈值时播放过渡；展开后继续拖动立即跟手。
                      // 折叠中的后续事件仍保留收缩动画，避免突然跳到零。
                      setState(() {
                        _dragWidth = shell.isSidebarVisible
                            ? math.min(shell.sidebarWidth, maxWidth)
                            : 0;
                        if (wasVisible != shell.isSidebarVisible) {
                          _animateDragTransition = true;
                        } else if (shell.isSidebarVisible) {
                          _animateDragTransition = false;
                        }
                      });
                    },
                    child: const SizedBox(width: _dragTargetWidth),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
