import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/window/window_provider.dart';

class WindowResizeOverlay extends StatelessWidget {
  const WindowResizeOverlay({super.key});

  static const double _resizeAreaSize = 5.0;

  @override
  Widget build(BuildContext context) {
    return Consumer<WindowProvider>(
      builder: (context, windowProvider, child) {
        if (windowProvider.isMaximized) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            _ResizeArea(
              left: 0,
              top: 0,
              bottom: 0,
              width: _resizeAreaSize,
              cursor: SystemMouseCursors.resizeLeftRight,
              edge: ResizeEdge.left,
            ),
            _ResizeArea(
              right: 0,
              top: 0,
              bottom: 0,
              width: _resizeAreaSize,
              cursor: SystemMouseCursors.resizeLeftRight,
              edge: ResizeEdge.right,
            ),
            _ResizeArea(
              left: 0,
              top: 0,
              right: 0,
              height: _resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpDown,
              edge: ResizeEdge.top,
            ),
            _ResizeArea(
              left: 0,
              bottom: 0,
              right: 0,
              height: _resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpDown,
              edge: ResizeEdge.bottom,
            ),
            _ResizeArea(
              left: 0,
              top: 0,
              width: _resizeAreaSize,
              height: _resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpLeftDownRight,
              edge: ResizeEdge.topLeft,
            ),
            _ResizeArea(
              right: 0,
              top: 0,
              width: _resizeAreaSize,
              height: _resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpRightDownLeft,
              edge: ResizeEdge.topRight,
            ),
            _ResizeArea(
              left: 0,
              bottom: 0,
              width: _resizeAreaSize,
              height: _resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpRightDownLeft,
              edge: ResizeEdge.bottomLeft,
            ),
            _ResizeArea(
              right: 0,
              bottom: 0,
              width: _resizeAreaSize,
              height: _resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpLeftDownRight,
              edge: ResizeEdge.bottomRight,
            ),
          ],
        );
      },
    );
  }
}

class _ResizeArea extends StatelessWidget {
  const _ResizeArea({
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
    required this.cursor,
    required this.edge,
  });

  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double? width;
  final double? height;
  final MouseCursor cursor;
  final ResizeEdge edge;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startResizing(edge),
          child: Container(
            width: width,
            height: height,
            color: Colors.transparent,
          ),
        ),
      ),
    );
  }
}
