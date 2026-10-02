/*
 * @Description: 绘制首页空状态的设备插画，适配深浅主题与显示缩放。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 01:00:00
 * @LastEditTime: 2026-10-02 22:01:29
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/definition.dart';

class HomeDeviceIllustration extends StatelessWidget {
  const HomeDeviceIllustration({
    super.key,
    required this.theme,
    this.connectionIcon = Symbols.link_rounded,
  });

  final AppTheme theme;
  final IconData connectionIcon;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 208,
        height: 168,
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _DevicePainter(theme))),
            // 使用与应用一致的 Google 图标字体，保持缩放时的清晰度。
            Positioned(
              left: 80,
              top: 65,
              width: 48,
              height: 48,
              child: Icon(
                connectionIcon,
                size: 44,
                weight: 400,
                opticalSize: 48,
                color: theme.adaptiveColor(
                  dark: theme.baseTertiary,
                  light: theme.textColorPrimary.withValues(alpha: 0.65),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicePainter extends CustomPainter {
  const _DevicePainter(this.theme);

  final AppTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 208, size.height / 168);
    final accent = theme.basePrimary;
    final paint = Paint()..isAntiAlias = true;
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(35, 42, 138, 101),
      const Radius.circular(17),
    );
    canvas.drawRRect(body, paint..color = theme.primary);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(43, 50, 122, 78),
        const Radius.circular(11),
      ),
      paint
        ..color = Color.alphaBlend(
          accent.withValues(alpha: 0.22),
          theme.primary,
        ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(95, 134, 18, 3),
        const Radius.circular(2),
      ),
      paint..color = theme.textColorTertiary.withValues(alpha: 0.4),
    );
    canvas.drawCircle(
      const Offset(169, 38),
      20,
      paint..color = theme.secondary,
    );
    canvas.drawCircle(const Offset(169, 38), 16, paint..color = accent);
    paint
      ..color = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : const Color(0xFF191919)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(163, 38), const Offset(175, 38), paint);
    canvas.drawLine(const Offset(169, 32), const Offset(169, 44), paint);
  }

  @override
  bool shouldRepaint(covariant _DevicePainter oldDelegate) =>
      oldDelegate.theme != theme;
}
