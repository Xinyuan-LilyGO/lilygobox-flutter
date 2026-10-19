import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/theme/provider.dart';
import '../../domain/device_control.dart';

/// 与设备状态栏一致：低电量优先红色，其次充电绿色，否则使用主题文字色。
class DeviceBatteryStatus extends StatelessWidget {
  const DeviceBatteryStatus({super.key, required this.battery});

  final DeviceBatteryState? battery;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final status = battery;
    final foreground = status == null
        ? theme.textColorTertiary
        : theme.textColorPrimary;
    final fill = status == null
        ? foreground
        : status.percent < 20
        ? theme.materialColors.error
        : status.charging
        ? theme.batteryFillColor
        : foreground;
    final percent = status == null ? '—%' : '${status.percent}%';
    return Semantics(
      label:
          '${status?.charging == true ? context.l10n.deviceDashboardCharging : context.l10n.deviceDashboardBattery} $percent',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 18,
              child: CustomPaint(
                painter: _BatteryStatusPainter(
                  percent: status?.percent ?? 0,
                  outline: foreground,
                  fill: fill,
                  charging: status?.charging ?? false,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(percent, style: TextStyle(fontSize: 12, color: foreground)),
          ],
        ),
      ),
    );
  }
}

class _BatteryStatusPainter extends CustomPainter {
  const _BatteryStatusPainter({
    required this.percent,
    required this.outline,
    required this.fill,
    required this.charging,
  });

  final int percent;
  final Color outline;
  final Color fill;
  final bool charging;

  @override
  void paint(Canvas canvas, Size size) {
    // 设备字体使用 960 单位坐标，轮廓可见范围为 x=80..880、y=280..680。
    final scale = (size.width - 2) / 800;
    canvas.save();
    canvas.translate(1 - 80 * scale, size.height / 2 - 480 * scale);
    canvas.scale(scale);
    canvas.save();
    // 填充延伸到外框下方，避免内框和填充分别抗锯齿时露出背景细缝。
    canvas.clipPath(_batteryBodyPath());
    if (percent > 0) {
      canvas.drawRect(
        Rect.fromLTWH(
          80,
          280,
          40 + 635.3841 * percent.clamp(0, 100) / 100,
          400,
        ),
        Paint()..color = fill,
      );
    }
    canvas.restore();
    canvas.drawPath(_batteryOutlinePath(), Paint()..color = outline);
    if (charging) {
      canvas.save();
      canvas.translate(271.4532, 313.1764);
      canvas.scale(0.348877);
      canvas.drawPath(_chargingBoltPath(), Paint()..color = outline);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BatteryStatusPainter oldDelegate) =>
      percent != oldDelegate.percent ||
      outline != oldDelegate.outline ||
      fill != oldDelegate.fill ||
      charging != oldDelegate.charging;
}

// 路径提取自设备端 MaterialSymbolsRounded 字体；电池轴为 FILL=0、wght=200、opsz=24。
Path _batteryOutlinePath() => Path()
  ..moveTo(175.3841, 680.0015)
  ..quadraticBezierTo(135.6401, 680.0015, 107.8193, 652.1807)
  ..quadraticBezierTo(79.9985, 624.3599, 79.9985, 584.6159)
  ..lineTo(79.9985, 375.3841)
  ..quadraticBezierTo(79.9985, 335.6401, 107.8193, 307.8193)
  ..quadraticBezierTo(135.6401, 279.9985, 175.3841, 279.9985)
  ..lineTo(700.0000, 279.9985)
  ..quadraticBezierTo(739.7440, 279.9985, 767.5647, 307.8193)
  ..quadraticBezierTo(795.3855, 335.6401, 795.3855, 375.3841)
  ..lineTo(795.3855, 584.6159)
  ..quadraticBezierTo(795.3855, 624.3599, 767.5647, 652.1807)
  ..quadraticBezierTo(739.7440, 680.0015, 700.0000, 680.0015)
  ..close()
  ..moveTo(175.3841, 640.0000)
  ..lineTo(700.0000, 640.0000)
  ..quadraticBezierTo(723.5382, 640.0000, 739.4611, 624.0771)
  ..quadraticBezierTo(755.3841, 608.1542, 755.3841, 584.6159)
  ..lineTo(755.3841, 375.3841)
  ..quadraticBezierTo(755.3841, 351.8458, 739.4611, 335.9229)
  ..quadraticBezierTo(723.5382, 320.0000, 700.0000, 320.0000)
  ..lineTo(175.3841, 320.0000)
  ..quadraticBezierTo(151.8458, 320.0000, 135.9229, 335.9229)
  ..quadraticBezierTo(120.0000, 351.8458, 120.0000, 375.3841)
  ..lineTo(120.0000, 584.6159)
  ..quadraticBezierTo(120.0000, 608.1542, 135.9229, 624.0771)
  ..quadraticBezierTo(151.8458, 640.0000, 175.3841, 640.0000)
  ..close()
  ..moveTo(835.3855, 564.6159)
  ..lineTo(835.3855, 396.1533)
  ..lineTo(847.6935, 396.1533)
  ..quadraticBezierTo(861.4244, 396.1533, 870.7129, 405.4418)
  ..quadraticBezierTo(880.0015, 414.7303, 880.0015, 428.4612)
  ..lineTo(880.0015, 532.3080)
  ..quadraticBezierTo(880.0015, 546.0389, 870.7129, 555.3274)
  ..quadraticBezierTo(861.4244, 564.6159, 847.6935, 564.6159)
  ..close()
  ..moveTo(120.0000, 640.0000)
  ..quadraticBezierTo(120.0000, 640.0000, 120.0000, 624.0771)
  ..quadraticBezierTo(120.0000, 608.1542, 120.0000, 584.6159)
  ..lineTo(120.0000, 375.3841)
  ..quadraticBezierTo(120.0000, 351.8458, 120.0000, 335.9229)
  ..quadraticBezierTo(120.0000, 320.0000, 120.0000, 320.0000)
  ..lineTo(120.0000, 320.0000)
  ..quadraticBezierTo(120.0000, 320.0000, 120.0000, 335.9229)
  ..quadraticBezierTo(120.0000, 351.8458, 120.0000, 375.3841)
  ..lineTo(120.0000, 584.6159)
  ..quadraticBezierTo(120.0000, 608.1542, 120.0000, 624.0771)
  ..quadraticBezierTo(120.0000, 640.0000, 120.0000, 640.0000)
  ..close();

Path _batteryBodyPath() => Path()
  ..moveTo(175.3841, 680.0015)
  ..quadraticBezierTo(135.6401, 680.0015, 107.8193, 652.1807)
  ..quadraticBezierTo(79.9985, 624.3599, 79.9985, 584.6159)
  ..lineTo(79.9985, 375.3841)
  ..quadraticBezierTo(79.9985, 335.6401, 107.8193, 307.8193)
  ..quadraticBezierTo(135.6401, 279.9985, 175.3841, 279.9985)
  ..lineTo(700.0000, 279.9985)
  ..quadraticBezierTo(739.7440, 279.9985, 767.5647, 307.8193)
  ..quadraticBezierTo(795.3855, 335.6401, 795.3855, 375.3841)
  ..lineTo(795.3855, 584.6159)
  ..quadraticBezierTo(795.3855, 624.3599, 767.5647, 652.1807)
  ..quadraticBezierTo(739.7440, 680.0015, 700.0000, 680.0015)
  ..close();

Path _chargingBoltPath() => Path()
  ..moveTo(393.0000, 795.0000)
  ..lineTo(672.0000, 460.0000)
  ..lineTo(492.0000, 460.0000)
  ..lineTo(528.0000, 174.0000)
  ..lineTo(275.0000, 540.0000)
  ..lineTo(429.0000, 540.0000)
  ..close()
  ..moveTo(360.0000, 600.0000)
  ..lineTo(217.0000, 600.0000)
  ..quadraticBezierTo(199.0000, 600.0000, 190.5000, 584.0000)
  ..quadraticBezierTo(182.0000, 568.0000, 193.0000, 553.0000)
  ..lineTo(531.0000, 65.0000)
  ..quadraticBezierTo(539.0000, 54.0000, 551.0000, 50.0000)
  ..quadraticBezierTo(563.0000, 46.0000, 575.0000, 51.0000)
  ..quadraticBezierTo(587.0000, 56.0000, 594.0000, 67.0000)
  ..quadraticBezierTo(601.0000, 78.0000, 599.0000, 91.0000)
  ..lineTo(560.0000, 400.0000)
  ..lineTo(736.0000, 400.0000)
  ..quadraticBezierTo(755.0000, 400.0000, 763.0000, 417.0000)
  ..quadraticBezierTo(771.0000, 434.0000, 759.0000, 449.0000)
  ..lineTo(388.0000, 894.0000)
  ..quadraticBezierTo(380.0000, 904.0000, 367.5000, 907.0000)
  ..quadraticBezierTo(355.0000, 910.0000, 344.0000, 905.0000)
  ..quadraticBezierTo(333.0000, 900.0000, 326.5000, 889.0000)
  ..quadraticBezierTo(320.0000, 878.0000, 322.0000, 865.0000)
  ..close()
  ..moveTo(393.0000, 795.0000)
  ..lineTo(429.0000, 540.0000)
  ..lineTo(275.0000, 540.0000)
  ..lineTo(528.0000, 174.0000)
  ..lineTo(492.0000, 460.0000)
  ..lineTo(672.0000, 460.0000)
  ..close();
