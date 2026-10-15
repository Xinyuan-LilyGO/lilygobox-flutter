/*
 * @Description: 在电池卡片中统一展示设备提供的预计充满或剩余使用时间。
 * @Author: LILYGO_L
 * @Date: 2026-10-13 00:00:00
 * @LastEditTime: 2026-10-13 00:00:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../domain/device_control.dart';

// 概览与电池状态卡片共用的纵向间距。
const deviceBatteryHeadingGap = 10.0;
const deviceBatteryGraphicGap = 16.0;

class DeviceBatteryEstimate extends StatelessWidget {
  const DeviceBatteryEstimate({
    super.key,
    required this.battery,
    required this.color,
  });

  final DeviceBatteryState? battery;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final charging = battery?.charging == true;
    final minutes = charging
        ? battery?.timeToFullMinutes
        : battery?.timeToEmptyMinutes;
    final duration = minutes == null
        ? '—'
        : minutes < 60
        ? l10n.deviceBatteryEstimateMinutes(minutes)
        : l10n.deviceBatteryDuration(minutes ~/ 60, minutes % 60);
    final percent = battery == null ? '—' : '${battery!.percent}%';
    final estimate = charging && minutes != null
        ? l10n.deviceBatteryEstimateToFull(duration)
        : minutes != null
        ? l10n.deviceBatteryEstimateRemaining(duration)
        : duration;
    final numberStyle = TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: color,
    );
    final estimateSpans = <TextSpan>[];
    var offset = 0;
    for (final match in RegExp(r'\d+').allMatches(estimate)) {
      estimateSpans.add(
        TextSpan(text: estimate.substring(offset, match.start)),
      );
      estimateSpans.add(TextSpan(text: match.group(0), style: numberStyle));
      offset = match.end;
    }
    estimateSpans.add(TextSpan(text: estimate.substring(offset)));
    return Semantics(
      label:
          '${l10n.deviceDashboardBattery} $percent, ${charging ? l10n.deviceBatteryTimeToFull : l10n.deviceBatteryTimeToEmpty} $duration',
      excludeSemantics: true,
      child: SizedBox(
        height: MediaQuery.textScalerOf(context).scale(44),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: percent, style: numberStyle),
              TextSpan(text: ' · ', style: numberStyle.copyWith(fontSize: 28)),
              ...estimateSpans,
            ],
          ),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w400,
            height: 1.2,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
