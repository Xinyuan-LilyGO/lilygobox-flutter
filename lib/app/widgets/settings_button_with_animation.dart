import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

// 设置按钮的动画版本
class SettingsButtonWithAnimation extends StatefulWidget {
  const SettingsButtonWithAnimation({
    super.key,
    required this.onPressed,
    required this.isFocused,
    required this.theme,
  });

  final VoidCallback onPressed;
  final bool isFocused;
  final dynamic theme;

  @override
  State<SettingsButtonWithAnimation> createState() =>
      _SettingsButtonWithAnimationState();
}

class _SettingsButtonWithAnimationState
    extends State<SettingsButtonWithAnimation> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const double settingsButtonDiameter = 24.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        width: settingsButtonDiameter,
        height: settingsButtonDiameter,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            splashFactory: InkRipple.splashFactory,
            borderRadius: BorderRadius.circular(settingsButtonDiameter / 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: _isHovered
                    ? widget.theme.appTitleBarIconBackgroundColor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(settingsButtonDiameter / 2),
              ),
              child: Center(
                child: Icon(
                  Symbols.settings,
                  size: 16.0,
                  color: widget.isFocused
                      ? widget.theme.iconColor
                      : widget.theme.inactiveIconColor,
                  fill: 1,
                  weight: 400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
