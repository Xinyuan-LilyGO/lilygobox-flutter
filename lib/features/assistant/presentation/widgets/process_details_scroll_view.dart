import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/widgets/app_scroll_behavior.dart';

/// 用时详情独立跟随最新进度；用户向上查看时暂停，不影响聊天主滚动区。
class ProcessDetailsScrollView extends StatefulWidget {
  const ProcessDetailsScrollView({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<ProcessDetailsScrollView> createState() =>
      _ProcessDetailsScrollViewState();
}

class _ProcessDetailsScrollViewState extends State<ProcessDetailsScrollView> {
  final _scroll = ScrollController();
  bool _followLatest = true;
  bool _followPending = false;
  int _followVersion = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) _scrollToEnd();
  }

  @override
  void didUpdateWidget(ProcessDetailsScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 最后一次更新也跟随到完成、失败或停止状态；历史详情初次打开仍从顶部阅读。
    if (widget.active || oldWidget.active) _scrollToEnd();
  }

  void _pauseFollow({bool cancelAnimation = false}) {
    final wasPending = _followPending;
    _followLatest = false;
    _followVersion++;
    _followPending = false;
    // 只终止仍在运行的跟随，避免反复 jumpTo 打断用户自己的平滑滚轮。
    if (cancelAnimation && wasPending && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.offset);
    }
  }

  bool _handleScroll(Notification notification) {
    if (notification is AppUserScrollNotification) {
      if (_scroll.hasClients &&
          identical(notification.position, _scroll.position) &&
          notification.delta < 0) {
        _pauseFollow(cancelAnimation: true);
      }
      return false;
    }
    if (notification is! ScrollNotification &&
        notification is! ScrollMetricsNotification) {
      return false;
    }
    final metrics = notification is ScrollNotification
        ? notification.metrics
        : (notification as ScrollMetricsNotification).metrics;
    final depth = notification is ScrollNotification
        ? notification.depth
        : (notification as ScrollMetricsNotification).depth;
    // 思考项内的长代码等嵌套滚动不能改变外层详情的跟随状态。
    if (metrics.axis != Axis.vertical || depth != 0) return false;
    if ((notification is UserScrollNotification &&
            notification.direction == ScrollDirection.forward) ||
        (notification is ScrollUpdateNotification &&
            (notification.scrollDelta ?? 0) < 0)) {
      _pauseFollow();
    } else if (notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0) > 0 &&
        metrics.extentAfter <= 1) {
      _followLatest = true;
    }
    if (notification is ScrollMetricsNotification &&
        widget.active &&
        metrics.extentAfter > 1) {
      _scrollToEnd();
    }
    return false;
  }

  void _scrollToEnd() {
    if (!_followLatest || _followPending) return;
    _followPending = true;
    final version = ++_followVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // 与主聊天一致：等待布局后平滑跟随，并校正动画期间新增的内容高度。
        for (var attempt = 0; attempt < 8; attempt++) {
          if (!mounted ||
              !_scroll.hasClients ||
              !_followLatest ||
              version != _followVersion) {
            return;
          }
          if (_scroll.position.extentAfter <= 1) return;
          final target = _scroll.position.maxScrollExtent;
          if (MediaQuery.disableAnimationsOf(context)) {
            _scroll.jumpTo(target);
          } else {
            await _scroll.animateTo(
              target,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
          if (!mounted ||
              !_scroll.hasClients ||
              !_followLatest ||
              version != _followVersion) {
            return;
          }
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted ||
              !_scroll.hasClients ||
              !_followLatest ||
              version != _followVersion) {
            return;
          }
          if (_scroll.position.extentAfter <= 1) return;
        }
      } finally {
        if (version == _followVersion) _followPending = false;
      }
    });
  }

  @override
  void dispose() {
    _followVersion++;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationListener<Notification>(
    onNotification: _handleScroll,
    child: Scrollbar(
      controller: _scroll,
      child: ScrollConfiguration(
        behavior: const AppScrollBehavior(scrollbars: false),
        child: SingleChildScrollView(
          key: const ValueKey('ai-process-details-scroll'),
          controller: _scroll,
          primary: false,
          padding: const EdgeInsetsDirectional.only(end: 20),
          child: widget.child,
        ),
      ),
    ),
  );
}
