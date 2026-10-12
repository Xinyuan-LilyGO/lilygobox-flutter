/*
 * @Description: 统一主页与设备页面卡片的柔和阴影，适配明暗主题。
 * @Author: LILYGO_L
 * @Date: 2026-10-12 00:00:00
 * @LastEditTime: 2026-10-12 00:00:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../theme/definition.dart';

/// 只绘制卡片外部阴影，不改变底色、尺寸或点击反馈。
class CardShadow extends StatelessWidget {
  const CardShadow({
    super.key,
    required this.theme,
    required this.borderRadius,
    required this.child,
  });

  final AppTheme theme;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: borderRadius,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: theme
                .adaptiveColor(
                  dark: const Color(0x52000000),
                  light: const Color(0x18000000),
                )
                .a,
          ),
          blurRadius: 18,
          spreadRadius: -3,
          offset: Offset.zero,
        ),
      ],
    ),
    child: child,
  );
}
