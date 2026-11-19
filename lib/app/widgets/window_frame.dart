/*
 * @Description: 绘制窗口圆角与阴影，将页面及弹层统一裁剪在窗口内部。
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/definition.dart';
import '../../core/widgets/window_shadow.dart';
import '../../core/window/desktop_window.dart';

class AppWindowFrame extends StatefulWidget {
  const AppWindowFrame({
    super.key,
    required this.theme,
    required this.isMaximized,
    required this.child,
    this.showShadow = true,
    this.window,
  });

  final AppTheme theme;
  final bool isMaximized;
  final Widget child;
  final bool showShadow;
  final Window? window;

  @override
  State<AppWindowFrame> createState() => _AppWindowFrameState();
}

class _AppWindowFrameState extends State<AppWindowFrame> {
  static const _channel = MethodChannel('lilygobox/window_layout');
  static _AppWindowFrameState? _channelOwner;
  Window? _window;
  ListenerId? _windowListener;
  bool _snapped = false;
  bool? _opaqueSurface;
  int _request = 0;
  bool get _windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_windows) {
      _channelOwner = this;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'layoutChanged' && call.arguments is bool) {
          ++_request;
          final snapped = call.arguments as bool;
          _setSnapped(snapped);
        }
      });
      _window = widget.window ?? currentDesktopWindow();
      _syncNativeSurface();
      _windowListener = _window?.addListener((event) {
        if (event is WindowMovedEvent ||
            event is WindowResizedEvent ||
            event is WindowRestoredEvent ||
            event is WindowMaximizedEvent) {
          unawaited(_refreshLayout());
        }
      });
      unawaited(_refreshLayout());
    }
  }

  @override
  void didUpdateWidget(AppWindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMaximized != widget.isMaximized) _syncNativeSurface();
  }

  void _syncNativeSurface() {
    final window = _window;
    final opaque = widget.isMaximized || _snapped;
    if (window == null || _opaqueSurface == opaque) return;
    _opaqueSurface = opaque;
    window.backgroundColor =
        (opaque ? widget.theme.primary.withAlpha(255) : Colors.transparent)
            .toNative();
  }

  void _setSnapped(bool snapped) {
    if (!mounted || _snapped == snapped) return;
    setState(() => _snapped = snapped);
    _syncNativeSurface();
  }

  Future<void> _refreshLayout() async {
    final request = ++_request;
    try {
      final snapped = await _channel.invokeMethod<bool>('isSnapped') ?? false;
      if (request == _request) _setSnapped(snapped);
    } on MissingPluginException {
      // 其他平台和不包含原生通道的测试环境保持普通窗口外观。
    } on PlatformException catch (error) {
      debugPrint('Cannot read window snap state: ${error.code}');
    }
  }

  @override
  void dispose() {
    if (identical(_channelOwner, this)) {
      _channelOwner = null;
      _channel.setMethodCallHandler(null);
    }
    if (_windowListener case final listener?) _window?.removeListener(listener);
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
            boxShadow: isMaximized || !widget.showShadow
                ? []
                : appWindowShadows,
          ),
          child: ClipRRect(
            // 仅圆角窗口需要离屏遮罩；最大化或贴靠时的
            // 矩形窗口不应分配全屏 saveLayer。
            clipBehavior: isMaximized
                ? Clip.hardEdge
                : Clip.antiAliasWithSaveLayer,
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
