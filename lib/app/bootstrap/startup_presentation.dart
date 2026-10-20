import 'package:flutter/material.dart';

/// 启动遮罩在应用窗口内部显示，标题栏和缩放命中区域始终保留。
class StartupPresentation extends InheritedWidget {
  const StartupPresentation({
    super.key,
    required this.visible,
    required this.opacity,
    required super.child,
  });

  final bool visible;
  final Animation<double> opacity;

  static StartupPresentation? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StartupPresentation>();

  @override
  bool updateShouldNotify(StartupPresentation oldWidget) =>
      visible != oldWidget.visible;
}
