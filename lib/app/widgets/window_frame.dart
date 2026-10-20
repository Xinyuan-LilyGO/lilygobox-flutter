/*
 * @Description: 绘制窗口圆角与阴影，将页面及弹层统一裁剪在窗口内部。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-20 10:05:51
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/definition.dart';
import '../../core/widgets/window_shadow.dart';

class AppWindowFrame extends StatefulWidget {
  const AppWindowFrame({
    super.key,
    required this.theme,
    required this.isMaximized,
    required this.child,
    this.showShadow = true,
  });

  final AppTheme theme;
  final bool isMaximized;
  final Widget child;
  final bool showShadow;

  @override
  State<AppWindowFrame> createState() => _AppWindowFrameState();
}

class _AppWindowFrameState extends State<AppWindowFrame> with WindowListener {
  static const _channel = MethodChannel('lilygobox/window_layout');
  bool _snapped = false;
  int _request = 0;
  bool get _windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_windows) {
      windowManager.addListener(this);
      unawaited(_refreshLayout());
    }
  }

  Future<void> _refreshLayout() async {
    final request = ++_request;
    try {
      final snapped = await _channel.invokeMethod<bool>('isSnapped') ?? false;
      if (mounted && request == _request && _snapped != snapped) {
        setState(() => _snapped = snapped);
      }
    } on MissingPluginException {
      // 其他平台和不包含原生通道的测试环境保持普通窗口外观。
    } on PlatformException catch (error) {
      debugPrint('Cannot read window snap state: ${error.code}');
    }
  }

  @override
  void onWindowMove() => unawaited(_refreshLayout());
  @override
  void onWindowMoved() => unawaited(_refreshLayout());
  @override
  void onWindowResize() => unawaited(_refreshLayout());
  @override
  void onWindowResized() => unawaited(_refreshLayout());
  @override
  void onWindowUnmaximize() => unawaited(_refreshLayout());

  @override
  void dispose() {
    if (_windows) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final child = widget.child;
    final isMaximized = widget.isMaximized || _snapped;
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final inset = (10 * ratio).ceilToDouble() / ratio;
        // 125% 等缩放下，矩形边界也要落到完整物理像素，避免底色与遮罩重复抗锯齿。
        final margin = isMaximized
            ? EdgeInsets.zero
            : EdgeInsets.fromLTRB(
                inset,
                inset,
                constraints.hasBoundedWidth
                    ? constraints.maxWidth -
                          ((constraints.maxWidth - 10) * ratio)
                                  .floorToDouble() /
                              ratio
                    : inset,
                constraints.hasBoundedHeight
                    ? constraints.maxHeight -
                          ((constraints.maxHeight - 10) * ratio)
                                  .floorToDouble() /
                              ratio
                    : inset,
              );
        return Container(
          margin: margin,
          decoration: BoxDecoration(
            borderRadius: isMaximized
                ? BorderRadius.zero
                : BorderRadius.circular(10),
            boxShadow: isMaximized || !widget.showShadow ? [] : appWindowShadows,
          ),
          child: ClipRRect(
            // 底色与遮罩先合成再裁剪，避免圆角抗锯齿边缘透出未变暗的底色。
            clipBehavior: Clip.antiAliasWithSaveLayer,
            borderRadius: isMaximized
                ? BorderRadius.zero
                : BorderRadius.circular(10),
            child: ColoredBox(color: theme.primary, child: child),
          ),
        );
      },
    );
  }
}
