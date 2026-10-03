/*
 * @Description: 按需创建并保留已访问页面，切换时暂停隐藏页面动画并隔离键盘焦点。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 20:29:43
 * @LastEditTime: 2026-10-03 20:29:43
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

class RetainedPageStack extends StatefulWidget {
  const RetainedPageStack({
    super.key,
    required this.pages,
    required this.activeKey,
  });
  final Map<Object, Widget> pages;
  final Object activeKey;

  @override
  State<RetainedPageStack> createState() => _RetainedPageStackState();
}

class _RetainedPageStackState extends State<RetainedPageStack>
    with SingleTickerProviderStateMixin {
  final Set<Object> _visited = {};
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );

  @override
  void didUpdateWidget(RetainedPageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.removeWhere((key) => !widget.pages.containsKey(key));
    if (oldWidget.activeKey != widget.activeKey) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _fade.value = 1;
      } else {
        _fade.forward(from: 0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.activeKey);
    final keys = widget.pages.keys.toList();
    return FadeTransition(
      opacity: _fade,
      child: IndexedStack(
        sizing: StackFit.expand,
        index: keys.indexOf(widget.activeKey),
        children: [
          for (final key in keys)
            TickerMode(
              key: ValueKey(key),
              enabled: key == widget.activeKey,
              child: ExcludeFocus(
                excluding: key != widget.activeKey,
                child: _visited.contains(key)
                    ? widget.pages[key]!
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }
}
