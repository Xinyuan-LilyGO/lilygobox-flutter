/*
 * @Description: 设备概览卡片布局，统一信息层级、控制区和自适应间距。
 * @Author: LILYGO_L
 * @Date: 2026-10-08 13:48:30
 * @LastEditTime: 2026-10-13 12:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/card_shadow.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/tilt_card.dart';
import '../../domain/device_control.dart';
import 'device_battery_colors.dart';
import 'device_battery_estimate.dart';
import 'device_wifi_signal.dart';

/// 根据可用空间组织卡片；同行高度由内容决定，不使用固定卡片尺寸。
class DeviceDashboard extends StatelessWidget {
  const DeviceDashboard({
    super.key,
    required this.theme,
    required this.name,
    this.model,
    required this.status,
    required this.online,
    required this.description,
    required this.connecting,
    required this.brightness,
    required this.volume,
    required this.vibration,
    required this.screenOn,
    required this.soundOn,
    required this.vibrationOn,
    required this.rotation,
    required this.onBrightness,
    required this.onVolume,
    required this.onVibration,
    required this.onScreen,
    required this.onSound,
    required this.onVibrationEnabled,
    required this.onRotation,
    required this.onInformation,
    required this.onBattery,
    this.controlState,
    this.controlsReady = false,
    this.lockTimeoutSeconds = 300,
    this.onLockTimeout,
  });

  final AppTheme theme;
  final String name;
  final String? model;
  final String status;
  final bool online;
  final String description;
  final bool connecting;
  final double brightness;
  final double volume;
  final double vibration;
  final bool screenOn;
  final bool soundOn;
  final bool vibrationOn;
  final int rotation;
  final int lockTimeoutSeconds;
  final ValueChanged<int>? onLockTimeout;
  final ValueChanged<double> onBrightness;
  final ValueChanged<double> onVolume;
  final ValueChanged<double> onVibration;
  final ValueChanged<bool> onScreen;
  final ValueChanged<bool> onSound;
  final ValueChanged<bool> onVibrationEnabled;
  final ValueChanged<int> onRotation;
  final VoidCallback onInformation;
  final VoidCallback onBattery;
  final DeviceControlState? controlState;
  final bool controlsReady;

  bool _supports(DeviceControlField field) =>
      online && controlsReady && (controlState?.supports(field) ?? false);

  Color get tint =>
      Color.alphaBlend(theme.basePrimary.withValues(alpha: .12), theme.primary);

  Text _text(
    String value, {
    double size = 13,
    bool muted = false,
    bool bold = false,
    Color? color,
  }) => Text(
    value,
    style: TextStyle(
      fontSize: size,
      height: 1.3,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      color:
          color ?? (muted ? theme.textColorTertiary : theme.textColorPrimary),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < 620 ||
            MediaQuery.textScalerOf(context).scale(14) > 21;
        final gap = narrow ? 12.0 : 16.0;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(l10n.deviceDetails, size: narrow ? 24 : 28, bold: true),
            const SizedBox(height: 7),
            _text(l10n.deviceDashboardSubtitle, size: 12, muted: true),
          ],
        );
        final statusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: theme.primary,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online
                      ? theme.adaptiveColor(
                          dark: const Color(0xFF83B69A),
                          light: const Color(0xFF438063),
                        )
                      : connecting
                      ? theme.baseTertiary
                      : theme.textColorTertiary,
                ),
              ),
              const SizedBox(width: 7),
              _text(status, size: 12),
              Container(
                height: 12,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: theme.materialColors.outlineVariant,
              ),
              Icon(
                deviceWifiIconForRssi(controlState?.wifiRssi, online: online),
                fill: online ? null : 1,
                size: 17,
                color: theme.textColorTertiary,
              ),
              const SizedBox(width: 6),
              _text(
                'Wi-Fi',
                size: 12,
                color: online ? null : theme.textColorTertiary,
              ),
            ],
          ),
        );
        final badge = online
            ? statusBadge
            : AppTooltip(
                message: description,
                verticalOffset: 16,
                child: statusBadge,
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (narrow)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 14), badge],
              )
            else
              Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 24),
                  badge,
                ],
              ),
            const SizedBox(height: 20),
            if (!narrow && constraints.maxWidth >= 900)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 28, child: _device(context)),
                    SizedBox(width: gap),
                    Expanded(flex: 32, child: _battery(context)),
                    SizedBox(width: gap),
                    Expanded(flex: 40, child: _soundAndHaptics(context)),
                  ],
                ),
              )
            else ...[
              _pair(narrow, gap, _device(context), _battery(context)),
              SizedBox(height: gap),
              _soundAndHaptics(context),
            ],
            SizedBox(height: gap),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                // 屏幕显示移至下方，沿用原下方卡片宽度。
                width: !narrow && constraints.maxWidth >= 900
                    ? ((constraints.maxWidth - gap) / 2).clamp(0.0, 440.0)
                    : constraints.maxWidth,
                child: _display(
                  context,
                  (!narrow && constraints.maxWidth >= 900
                          ? ((constraints.maxWidth - gap) / 2).clamp(0.0, 440.0)
                          : constraints.maxWidth) -
                      40,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 卡片同排对齐底边，窄窗口和大字体下改为自然高度的单列。
  Widget _pair(bool narrow, double gap, Widget left, Widget right) => narrow
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            SizedBox(height: gap),
            right,
          ],
        )
      : IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              SizedBox(width: gap),
              Expanded(child: right),
            ],
          ),
        );

  Widget _surface({
    required Widget child,
    bool enabled = true,
    bool allowNavigationWhenDisabled = false,
    VoidCallback? onTap,
    Key? key,
    Color? color,
    Color? feedbackColor,
    bool useDefaultFeedback = false,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    // 离线仅禁用交互并降低内容强调度，保留数值、图形和原有布局。
    child = Semantics(
      enabled: enabled,
      child: ExcludeFocus(
        excluding: !enabled,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Opacity(opacity: enabled ? 1 : .4, child: child),
        ),
      ),
    );
    // 设备信息和电池详情属于只读信息，离线时仍可打开查看。
    if (!enabled && !allowNavigationWhenDisabled) onTap = null;
    final radius = BorderRadius.circular(20);
    // 特色卡片可能与全局主题明暗相反，点击波纹按实际底色选择对比色。
    final feedback =
        feedbackColor ??
        ((color ?? theme.primary).computeLuminance() < .3
            ? Colors.white
            : theme.basePrimary);
    if (onTap == null) {
      return CardShadow(
        theme: theme,
        borderRadius: radius,
        child: Container(
          key: key,
          decoration: BoxDecoration(
            color: color ?? theme.primary,
            borderRadius: radius,
          ),
          padding: padding,
          child: child,
        ),
      );
    }
    return TiltCard(
      child: CardShadow(
        theme: theme,
        borderRadius: radius,
        child: Semantics(
          button: true,
          child: MenuItemSurface(
            key: key,
            theme: theme,
            onPressed: onTap,
            backgroundColor: color ?? theme.primary,
            hoverColor: color ?? theme.primary,
            splashColor: useDefaultFeedback
                ? null
                : feedback.withValues(alpha: .22),
            highlightColor: useDefaultFeedback
                ? null
                : feedback.withValues(alpha: .09),
            borderRadius: radius,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }

  Widget _title(String title, {Color? color}) =>
      _text(title, size: 16, bold: true, color: color);

  Widget _device(BuildContext context) {
    final colors = DeviceIdentityColors(theme);
    final foreground = colors.foreground;
    final muted = colors.muted;
    return _surface(
      enabled: online,
      allowNavigationWhenDisabled: true,
      key: const ValueKey('device-card-information'),
      onTap: onInformation,
      color: online ? colors.background : colors.offlineBackground,
      feedbackColor: foreground,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(context.l10n.deviceDashboardMyDevice, color: foreground),
              const SizedBox(height: 12),
              // 居中的媒体槽位预留给设备图片，暂时使用 Blur On 图标。
              Center(
                child: SizedBox(
                  width: 104,
                  height: 104,
                  child: Icon(Symbols.blur_on, size: 80, color: muted),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: _text(name, size: 20, bold: true, color: foreground),
              ),
              const SizedBox(height: 6),
              Center(
                child: _text(
                  model ?? context.l10n.deviceDashboardIdentity,
                  size: 13,
                  muted: true,
                  color: muted,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
          _text(context.l10n.deviceDashboardViewInfo, size: 12, color: muted),
        ],
      ),
    );
  }

  /// 电池使用普通卡片底色，图形独立适配亮暗主题并限宽，避免随窗口拉成长条。
  Widget _battery(BuildContext context) {
    final colors = DeviceBatteryColors(theme);
    return _surface(
      enabled: online,
      key: const ValueKey('device-card-battery'),
      onTap: onBattery,
      allowNavigationWhenDisabled: true,
      color: colors.background,
      useDefaultFeedback: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (controlState?.battery?.charging == true) ...[
                    Icon(
                      Symbols.bolt,
                      fill: 1,
                      size: 22,
                      color: colors.foreground,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      controlState?.battery?.charging == true
                          ? context.l10n.deviceDashboardCharging
                          : controlState?.battery != null
                          ? context.l10n.deviceDashboardBattery
                          : context.l10n.deviceBatteryUnknown,
                      style: TextStyle(
                        color: colors.foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: deviceBatteryHeadingGap),
              DeviceBatteryEstimate(
                battery: controlState?.battery,
                color: colors.foreground,
              ),
              const SizedBox(height: deviceBatteryGraphicGap),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 276),
                  child: DeviceBatteryGraphic(
                    theme: theme,
                    progress: (controlState?.battery?.percent ?? 0) / 100,
                    height: 116,
                    colors: colors,
                  ),
                ),
              ),
              const SizedBox(height: deviceBatteryGraphicGap),
            ],
          ),
          Text(
            context.l10n.deviceDashboardViewBattery,
            style: TextStyle(color: colors.muted, fontSize: 12, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _iconTile(IconData icon, {bool accent = false}) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: accent ? tint : theme.secondary.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Icon(
      icon,
      fill: 1,
      size: 21,
      color: accent ? theme.basePrimary : theme.textColorPrimary,
    ),
  );

  Widget _percentage(int? value) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: value == null ? '—' : '$value',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
        if (value != null)
          const TextSpan(text: ' %', style: TextStyle(fontSize: 12)),
      ],
    ),
    style: TextStyle(color: theme.textColorPrimary),
  );

  /// 图标、名称与数值共用一条基线，滑条紧随其下，减少控制区的纵向留白。
  Widget _control(BuildContext context, {required bool brightnessControl}) {
    final icon = brightnessControl
        ? Symbols.brightness_6
        : soundOn
        ? Symbols.volume_up
        : Symbols.volume_off;
    final value = brightnessControl ? brightness : volume;
    final title = brightnessControl
        ? context.l10n.deviceBrightness
        : context.l10n.deviceDashboardSound;
    // 熄屏只控制显示电源；静音只禁用调节，保留原音量及其显示值。
    final enabled =
        _supports(
          brightnessControl
              ? DeviceControlField.brightness
              : DeviceControlField.volume,
        ) &&
        (brightnessControl || soundOn);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (brightnessControl)
              _iconTile(icon)
            else
              _toggleIcon(
                icon,
                soundOn,
                soundOn ? context.l10n.deviceMute : context.l10n.deviceUnmute,
                () => onSound(!soundOn),
              ),
            const SizedBox(width: 10),
            Expanded(child: _text(title, size: 16, bold: true)),
            const SizedBox(width: 12),
            Opacity(
              // 离线由外层卡片统一变灰，局部禁用仅在在线时叠加。
              opacity: !online || enabled ? 1 : .4,
              child: _percentage((value * 100).round()),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DashboardSlider(
          theme: theme,
          value: value,
          icon: brightnessControl ? Symbols.brightness_6 : Symbols.volume_up,
          label: title,
          onChanged: enabled
              ? brightnessControl
                    ? onBrightness
                    : onVolume
              : null,
        ),
      ],
    );
  }

  /// 声音与触感采用与屏幕控制一致的内容布局，不嵌套额外卡片。
  Widget _soundAndHaptics(BuildContext context) => _surface(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
    enabled:
        _supports(DeviceControlField.volume) ||
        _supports(DeviceControlField.hapticStrength),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _text(context.l10n.deviceSoundAndHaptics, size: 16, bold: true),
        const SizedBox(height: 20),
        _control(context, brightnessControl: false),
        const SizedBox(height: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _toggleIcon(
                  vibrationOn ? Symbols.vibration : Symbols.mobile_off,
                  vibrationOn,
                  vibrationOn
                      ? context.l10n.deviceDisableVibration
                      : context.l10n.deviceEnableVibration,
                  () => onVibrationEnabled(!vibrationOn),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _text(
                    context.l10n.deviceVibrationIntensity,
                    size: 16,
                    bold: true,
                  ),
                ),
                const SizedBox(width: 12),
                Opacity(
                  opacity: !online || vibrationOn ? 1 : .4,
                  child: _percentage((vibration * 100).round()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DashboardSlider(
              theme: theme,
              value: vibration,
              icon: Symbols.vibration,
              label: context.l10n.deviceVibrationIntensity,
              onChanged:
                  _supports(DeviceControlField.hapticStrength) && vibrationOn
                  ? onVibration
                  : null,
            ),
          ],
        ),
      ],
    ),
  );

  /// 左侧图标同时表示开关状态，提示和语义提供明确的操作名称。
  Widget _toggleIcon(
    IconData icon,
    bool enabled,
    String label,
    VoidCallback onTap,
  ) => AppTooltip(
    message: label,
    child: Semantics(
      label: label,
      toggled: enabled,
      button: true,
      child: MenuItemSurface(
        theme: theme,
        onPressed:
            _supports(
              icon == Symbols.vibration || icon == Symbols.mobile_off
                  ? DeviceControlField.hapticEnabled
                  : icon == Symbols.volume_up || icon == Symbols.volume_off
                  ? DeviceControlField.soundEnabled
                  : DeviceControlField.screenEnabled,
            )
            ? onTap
            : null,
        backgroundColor: theme.secondary.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, fill: 1, size: 21, color: theme.textColorPrimary),
        ),
      ),
    ),
  );

  Widget _display(BuildContext context, double contentWidth) => _surface(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
    enabled: _supports(DeviceControlField.brightness),
    child: Builder(
      builder: (context) {
        final heading = Row(
          children: [
            _toggleIcon(
              screenOn
                  ? Symbols.desktop_windows
                  : Symbols.desktop_access_disabled,
              screenOn,
              screenOn
                  ? context.l10n.deviceScreenTurnOff
                  : context.l10n.deviceScreenTurnOn,
              () => onScreen(!screenOn),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _text(context.l10n.deviceScreenDisplay, size: 15, bold: true),
                  const SizedBox(height: 4),
                  _text(
                    screenOn
                        ? context.l10n.deviceDashboardScreenOn
                        : context.l10n.deviceDashboardScreenOff,
                    size: 11,
                    muted: true,
                  ),
                ],
              ),
            ),
          ],
        );
        final options = Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              theme.secondary.withValues(alpha: .6),
              theme.primary,
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              for (final angle in [0, 90, 180, 270]) ...[
                if (angle != 0) const SizedBox(width: 4),
                Expanded(
                  child: MenuItemSurface(
                    theme: theme,
                    isSelected: rotation == angle,
                    onPressed: _supports(DeviceControlField.rotation)
                        ? () => onRotation(angle)
                        : null,
                    // 用实际底色参与渐变，避免透明黑色插值时先变暗再变亮。
                    backgroundColor: Color.alphaBlend(
                      theme.secondary.withValues(alpha: .6),
                      theme.primary,
                    ),
                    hoverColor: theme.secondaryTextHoverColor,
                    selectedColor: theme.basePrimary,
                    borderRadius: BorderRadius.circular(7),
                    child: Semantics(
                      selected: rotation == angle,
                      button: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 3,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            RotatedBox(
                              quarterTurns: angle ~/ 90,
                              child: Icon(
                                Symbols.smartphone,
                                size: 17,
                                color: rotation == angle
                                    ? theme.materialColors.onPrimary
                                    : theme.textColorTertiary,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: _text(
                                  '$angle°',
                                  size: 12,
                                  bold: rotation == angle,
                                  color: rotation == angle
                                      ? theme.materialColors.onPrimary
                                      : theme.textColorTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
        final rotationControl = ConstrainedBox(
          // 限制桌面选项区宽度，避免四个角度随卡片拉伸成大块。
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _text(
                context.l10n.deviceDashboardRotation,
                size: 12,
                muted: true,
              ),
              const SizedBox(height: 6),
              options,
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: 18),
            _lockTimeoutControl(context, contentWidth),
            const SizedBox(height: 18),
            Align(alignment: Alignment.centerLeft, child: rotationControl),
            const SizedBox(height: 24),
            _control(context, brightnessControl: true),
          ],
        );
      },
    ),
  );

  /// 按实际文字宽度切换一行或两行，完整展示锁屏选项并收紧背景。
  Widget _lockTimeoutControl(BuildContext context, double contentWidth) {
    final enabled =
        _supports(DeviceControlField.lockTimeoutSeconds) &&
        onLockTimeout != null;
    final background = Color.alphaBlend(
      theme.secondary.withValues(alpha: .6),
      theme.primary,
    );
    final labels = [
      for (final seconds in deviceLockTimeoutOptions)
        seconds == 0
            ? context.l10n.deviceAutoLockNever
            : seconds < 60
            ? context.l10n.deviceAutoLockSeconds(seconds)
            : context.l10n.deviceAutoLockMinutes(seconds ~/ 60),
    ];
    double minimumWidth = 0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout();
      if (painter.width + 16 > minimumWidth) minimumWidth = painter.width + 16;
      painter.dispose();
    }
    final columns = minimumWidth * 7 + 24 <= contentWidth ? 7 : 4;
    final groupWidth = (minimumWidth * columns + (columns - 1) * 3 + 6).clamp(
      0.0,
      contentWidth,
    );
    final width = (groupWidth - 6 - (columns - 1) * 3) / columns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(context.l10n.deviceAutoLock, size: 12, muted: true),
        const SizedBox(height: 6),
        Container(
          width: groupWidth,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (
                int start = 0;
                start < deviceLockTimeoutOptions.length;
                start += columns
              ) ...[
                if (start > 0) const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final seconds
                        in deviceLockTimeoutOptions
                            .skip(start)
                            .take(columns)) ...[
                      if (seconds != deviceLockTimeoutOptions[start])
                        const SizedBox(width: 3),
                      SizedBox(
                        width: width,
                        child: MenuItemSurface(
                          key: ValueKey('device-auto-lock-$seconds'),
                          theme: theme,
                          isSelected: enabled && lockTimeoutSeconds == seconds,
                          onPressed: enabled
                              ? () => onLockTimeout!(seconds)
                              : null,
                          backgroundColor: background,
                          hoverColor: theme.secondaryTextHoverColor,
                          selectedColor: theme.basePrimary,
                          borderRadius: BorderRadius.circular(7),
                          child: Semantics(
                            selected: enabled && lockTimeoutSeconds == seconds,
                            button: true,
                            enabled: enabled,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Center(
                                heightFactor: 1,
                                child: _text(
                                  seconds == 0
                                      ? context.l10n.deviceAutoLockNever
                                      : seconds < 60
                                      ? context.l10n.deviceAutoLockSeconds(
                                          seconds,
                                        )
                                      : context.l10n.deviceAutoLockMinutes(
                                          seconds ~/ 60,
                                        ),
                                  size: 12,
                                  bold:
                                      enabled && lockTimeoutSeconds == seconds,
                                  color:
                                      enabled && lockTimeoutSeconds == seconds
                                      ? theme.materialColors.onPrimary
                                      : theme.textColorTertiary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 自绘电池外框与电量填充，正极左侧平直、右侧圆润并与主体分离。
class DeviceBatteryGraphic extends StatelessWidget {
  const DeviceBatteryGraphic({
    super.key,
    required this.theme,
    required this.progress,
    this.height = 52,
    this.colors,
  });
  final AppTheme theme;
  final double progress;
  final double height;
  final DeviceBatteryColors? colors;

  @override
  Widget build(BuildContext context) {
    final palette = colors ?? DeviceBatteryColors(theme);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        painter: _BatteryGlowPainter(
          progress: progress.clamp(0.0, 1.0),
          fill: palette.fillFor(progress),
          empty: palette.empty,
        ),
      ),
    );
  }
}

/// 先画底层，再叠加扩散光、近缘光和高亮主体，避免光晕被底色遮挡。
class _BatteryGlowPainter extends CustomPainter {
  const _BatteryGlowPainter({
    required this.progress,
    required this.fill,
    required this.empty,
  });

  final double progress;
  final Color fill;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final inset = size.height * .045 + 1.5;
    final body = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(inset),
      Radius.circular(size.height * .16),
    );
    canvas.drawRRect(body, Paint()..color = empty);
    if (progress > 0) {
      final fillRect = Rect.fromLTWH(
        body.left,
        body.top,
        body.width * progress,
        body.height,
      );
      final fillPath = Path.combine(
        PathOperation.intersect,
        Path()..addRRect(body),
        Path()..addRect(fillRect),
      );
      // 提高明度时保留饱和度，避免混入大量白色后变成粉绿色。
      final source = HSLColor.fromColor(fill);
      final luminous = source.withSaturation(.72).withLightness(.58).toColor();
      if (progress >= .1) {
        canvas.drawPath(
          fillPath,
          Paint()
            ..color = luminous.withValues(alpha: .35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
        );
        canvas.drawPath(
          fillPath,
          Paint()
            ..color = luminous.withValues(alpha: .65)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              progress >= .1 ? luminous : fill,
              progress >= .1
                  ? source.withSaturation(.72).withLightness(.53).toColor()
                  : fill,
            ],
          ).createShader(fillRect),
      );
      if (progress >= .1) {
        canvas.save();
        canvas.clipPath(fillPath);
        canvas.drawPath(
          fillPath,
          Paint()
            ..color = luminous.withValues(alpha: .5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_BatteryGlowPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      fill != oldDelegate.fill ||
      empty != oldDelegate.empty;
}

/// 原生 Slider 保留键盘、拖动及语义，视觉层采用 Android 快捷设置胶囊轨道。
class _DashboardSlider extends StatelessWidget {
  const _DashboardSlider({
    required this.theme,
    required this.value,
    required this.icon,
    required this.label,
    required this.onChanged,
  });
  final AppTheme theme;
  final double value;
  final IconData icon;
  final String label;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: SizedBox(
      height: 36,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _QuickSettingsTrackPainter(
                  theme,
                  value,
                  icon,
                  onChanged != null,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 36,
                trackShape: const RectangularSliderTrackShape(),
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbShape: SliderComponentShape.noThumb,
                overlayShape: SliderComponentShape.noOverlay,
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Slider(
                value: value,
                padding: EdgeInsets.zero,
                onChanged: onChanged,
                semanticFormatterCallback: (value) =>
                    '${(value * 100).round()}%',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 以胶囊填充和末端内嵌图标呈现快捷设置滑条，交互仍交给原生 Slider。
class _QuickSettingsTrackPainter extends CustomPainter {
  const _QuickSettingsTrackPainter(
    this.theme,
    this.value,
    this.icon,
    this.enabled,
  );

  final AppTheme theme;
  final double value;
  final IconData icon;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    // 禁用时轨道和内部图标一起淡化，图标形状仍表示原本调节的功能。
    Color trackColor(Color color) => enabled
        ? color
        : Color.alphaBlend(color.withValues(alpha: .4), theme.primary);
    // 未填充区域是居中的细线，只有已填充部分使用完整高度的胶囊。
    final track = Rect.fromLTWH(0, (size.height - 4) / 2, size.width, 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(2)),
      Paint()
        ..color = trackColor(
          Color.alphaBlend(
            theme.basePrimary.withValues(alpha: .13),
            theme.secondary,
          ),
        ),
    );
    // 最低值也保留一枚圆形端点，容纳图标；填充末端随数值连续移动。
    final minimum = size.height.clamp(0.0, size.width);
    final width = minimum + (size.width - minimum) * value.clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, size.height), radius),
      Paint()..color = trackColor(theme.basePrimary),
    );
    final text = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 18,
          color: enabled
              ? theme.materialColors.onPrimary
              : theme.inactiveIconColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(width - size.height / 2, size.height / 2);
    // 图标跟随数值转动一圈，与拖动同步，不额外延迟滑条响应。
    canvas.rotate(value.clamp(0.0, 1.0) * 6.283185307179586);
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    canvas.restore();
    text.dispose();
  }

  @override
  bool shouldRepaint(_QuickSettingsTrackPainter oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.value != value ||
      oldDelegate.icon != icon ||
      oldDelegate.enabled != enabled;
}
