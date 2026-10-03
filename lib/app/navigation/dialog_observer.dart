/*
 * @Description: 跟踪内容区弹出路由，在弹窗及退出动画期间锁定标题栏页面切换。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 23:56:45
 * @LastEditTime: 2026-10-03 23:56:45
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

class AppDialogObserver extends NavigatorObserver {
  final hasDialog = ValueNotifier(false);
  final Set<PopupRoute<dynamic>> _dialogs = {};
  bool _scheduled = false;
  bool _disposed = false;

  void _track(Route<dynamic>? route) {
    if (_disposed || route is! PopupRoute || !_dialogs.add(route)) return;
    _update();
    // 等遮罩退出动画结束才解锁，避免在仍可见时切换底层页面。
    route.completed.then((_) {
      if (_disposed) return;
      _dialogs.remove(route);
      _update();
    });
  }

  void _update() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    // Navigator 可能正在构建路由，延后通知以免在 build 中重建标题栏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) hasDialog.value = _dialogs.isNotEmpty;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _track(newRoute);

  void dispose() {
    _disposed = true;
    _dialogs.clear();
    hasDialog.dispose();
  }
}
