/*
 * @Description: 共享设备风格的胶囊滑条，支持连续调节及固定等级点。
 * @Author: LILYGO_L
 * @Date: 2026-11-10 11:58:09
 * @LastEditTime: 2026-11-10 13:53:32
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/definition.dart';
import '../theme/material_palette.dart';
import 'interaction_decoration.dart';

/// 原生 Slider 保留键盘、拖动及语义，视觉层采用 Android 快捷设置胶囊轨道。
class AppCapsuleSlider extends StatelessWidget {
  const AppCapsuleSlider({
    super.key,
    required this.theme,
    required this.value,
    required this.icon,
    required this.label,
    required this.onChanged,
    this.divisions,
    this.semanticFormatter,
    this.onChangeEnd,
    this.snapToDivisions = false,
  });
  final AppTheme theme;
  final double value;
  final IconData icon;
  final String label;
  final ValueChanged<double>? onChanged;
  final int? divisions;
  final String Function(double)? semanticFormatter;
  final ValueChanged<double>? onChangeEnd;
  final bool snapToDivisions;

  @override
  Widget build(BuildContext context) => snapToDivisions && divisions != null
      ? _SnappingCapsuleSlider(configuration: this)
      : Semantics(
          label: label,
          child: SizedBox(
            height: 36,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CapsuleTrackPainter(
                        theme,
                        value,
                        icon,
                        onChanged != null,
                        divisions,
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
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: value,
                      padding: EdgeInsets.zero,
                      onChanged: onChanged,
                      onChangeEnd: onChangeEnd,
                      divisions: divisions,
                      semanticFormatterCallback:
                          semanticFormatter ??
                          (value) => '${(value * 100).round()}%',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
}

/// 拖动位置连续跟随鼠标，仅在松手后向最近节点吸附。
class _SnappingCapsuleSlider extends StatefulWidget {
  const _SnappingCapsuleSlider({required this.configuration});
  final AppCapsuleSlider configuration;

  @override
  State<_SnappingCapsuleSlider> createState() => _SnappingCapsuleSliderState();
}

class _SnappingCapsuleSliderState extends State<_SnappingCapsuleSlider>
    with SingleTickerProviderStateMixin {
  late final _position = AnimationController(
    vsync: this,
    value: widget.configuration.value,
  );
  final _focus = FocusNode();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = _handleKey;
  }

  AppCapsuleSlider get config => widget.configuration;
  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  void _moveTo(double value) {
    if (_reduced) {
      _position.value = value;
    } else {
      _position.animateTo(
        value,
        duration: InteractionDecoration.animationDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _SnappingCapsuleSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pressed && oldWidget.configuration.value != config.value) {
      _moveTo(config.value);
    }
  }

  void _commit(double raw) {
    final steps = config.divisions!;
    final value = (raw * steps).round() / steps;
    setState(() => _pressed = false);
    _moveTo(value);
    config.onChanged?.call(value);
    config.onChangeEnd?.call(value);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (config.onChanged == null ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if ([
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
    ].contains(key)) {
      final direction =
          key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowDown
          ? -1
          : 1;
      _step(direction);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _step(int direction) {
    _commit((config.value + direction / config.divisions!).clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _focus.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: config.label,
    slider: true,
    value: config.semanticFormatter?.call(config.value),
    increasedValue: config.semanticFormatter?.call(
      (config.value + 1 / config.divisions!).clamp(0, 1),
    ),
    decreasedValue: config.semanticFormatter?.call(
      (config.value - 1 / config.divisions!).clamp(0, 1),
    ),
    onIncrease: config.onChanged == null ? null : () => _step(1),
    onDecrease: config.onChanged == null ? null : () => _step(-1),
    child: ExcludeSemantics(
      child: SizedBox(
        height: 36,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _pressed ? 1 : 0),
                  duration: _reduced
                      ? Duration.zero
                      : InteractionDecoration.animationDuration,
                  builder: (context, pressed, _) => AnimatedBuilder(
                    animation: _position,
                    builder: (context, _) => CustomPaint(
                      key: const ValueKey('capsule-snap-track'),
                      painter: _CapsuleTrackPainter(
                        config.theme,
                        _position.value,
                        config.icon,
                        config.onChanged != null,
                        config.divisions,
                        circleThumb: true,
                        pressed: pressed,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackShape: const _SnappingTrackShape(),
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbShape: SliderComponentShape.noThumb,
                  overlayShape: SliderComponentShape.noOverlay,
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: AnimatedBuilder(
                  animation: _position,
                  builder: (context, _) => Slider(
                    value: _position.value,
                    padding: EdgeInsets.zero,
                    focusNode: _focus,
                    onChangeStart: config.onChanged == null
                        ? null
                        : (_) {
                            _focus.requestFocus();
                            _position.stop();
                            setState(() => _pressed = true);
                          },
                    onChanged: config.onChanged == null
                        ? null
                        : (value) {
                            _position.value = value;
                            config.onChanged!(value);
                          },
                    onChangeEnd: config.onChanged == null ? null : _commit,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 轨道与圆点中心对齐，整条胶囊（含两端）均可点击。
class _SnappingTrackShape extends RectangularSliderTrackShape {
  const _SnappingTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) => Rect.fromLTWH(
    offset.dx + 18,
    offset.dy + (parentBox.size.height - 4) / 2,
    (parentBox.size.width - 36).clamp(0.0, double.infinity),
    4,
  );
}

/// 以胶囊填充和末端内嵌图标呈现快捷设置滑条，交互仍交给原生 Slider。
class _CapsuleTrackPainter extends CustomPainter {
  const _CapsuleTrackPainter(
    this.theme,
    this.value,
    this.icon,
    this.enabled,
    this.divisions, {
    this.circleThumb = false,
    this.pressed = 0,
  });

  final AppTheme theme;
  final double value;
  final IconData icon;
  final bool enabled;
  final int? divisions;
  final bool circleThumb;
  final double pressed;

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
    if (divisions case final steps? when steps > 0) {
      for (var index = 0; index <= steps; index++) {
        final x = size.height / 2 + (size.width - size.height) * index / steps;
        canvas.drawCircle(
          Offset(x, size.height / 2),
          2,
          Paint()
            ..color = trackColor(
              x < width
                  ? theme.materialColors.onPrimary.withValues(alpha: .65)
                  : theme.textColorTertiary,
            ),
        );
      }
    }
    if (circleThumb) {
      canvas.drawCircle(
        Offset(width - size.height / 2, size.height / 2),
        7 + 3 * pressed,
        Paint()..color = trackColor(theme.materialColors.onPrimary),
      );
      return;
    }
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
  bool shouldRepaint(_CapsuleTrackPainter oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.value != value ||
      oldDelegate.icon != icon ||
      oldDelegate.enabled != enabled ||
      oldDelegate.divisions != divisions ||
      oldDelegate.circleThumb != circleThumb ||
      oldDelegate.pressed != pressed;
}
