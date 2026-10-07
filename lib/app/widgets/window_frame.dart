/*
 * @Description: 绘制窗口圆角与阴影，将页面及弹层统一裁剪在窗口内部。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-03 23:41:53
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../core/theme/definition.dart';
import '../../core/widgets/window_shadow.dart';

class AppWindowFrame extends StatelessWidget {
  const AppWindowFrame({
    super.key,
    required this.theme,
    required this.isMaximized,
    required this.child,
  });

  final AppTheme theme;
  final bool isMaximized;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
            boxShadow: isMaximized ? [] : appWindowShadows,
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
