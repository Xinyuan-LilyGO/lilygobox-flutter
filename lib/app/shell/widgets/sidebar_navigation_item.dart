/*
 * @Description: 构建图标与文字组合的侧栏导航项及选中指示条。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-02 14:08:15
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/provider.dart';
import '../../../core/widgets/menu_item_surface.dart';

/// 图标与文字共用整行命中区域，长设备名不会撑开侧栏。
class SidebarNavigationItem extends StatelessWidget {
  const SidebarNavigationItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isSelected = false,
    this.disableWhenSelected = true,
    this.iconColor,
    this.iconFill,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isSelected;
  final bool disableWhenSelected;
  final Color? iconColor;
  final double? iconFill;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: MenuItemSurface(
              theme: theme,
              isSelected: isSelected,
              disableWhenSelected: disableWhenSelected,
              onPressed: onPressed,
              child: SizedBox(
                height: 36,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Icon(
                      icon,
                      size: 20,
                      weight: 400,
                      fill: iconFill,
                      color:
                          iconColor ??
                          (isSelected
                              ? theme.basePrimary
                              : theme.sidebarIconColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: theme.textColorPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
          if (isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SidebarSelectionGlowPainter(theme.basePrimary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 侧栏灯管与选中行左缘的扩散光；不参与布局和点击命中。
class _SidebarSelectionGlowPainter extends CustomPainter {
  const _SidebarSelectionGlowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, -16, size.width + 16, size.height + 32));
    final tube = RRect.fromRectAndRadius(
      Rect.fromLTWH(-8, (size.height - 30) / 2, 12, 30),
      const Radius.circular(6),
    );
    final source = HSLColor.fromColor(color);
    final luminous = source.withSaturation(.55).withLightness(.66).toColor();
    final lowerShadow = tube.inflate(2);
    canvas.drawRRect(
      lowerShadow,
      Paint()
        ..color = luminous.withValues(alpha: .28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawRRect(
      tube.inflate(1),
      Paint()
        ..color = luminous.withValues(alpha: .5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      tube,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            luminous,
            source.withSaturation(.55).withLightness(.61).toColor(),
          ],
        ).createShader(tube.outerRect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SidebarSelectionGlowPainter oldDelegate) =>
      color != oldDelegate.color;
}
