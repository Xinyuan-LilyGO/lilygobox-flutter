/*
 * @Description: 组合设置说明、控件和重置入口，支持窄窗口布局。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../theme/definition.dart';
import '../menu_item_surface.dart';
import 'more_button.dart';

/// 带说明、控件和重置入口的设置项，窄窗口下自动换行。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.theme,
    required this.title,
    required this.description,
    required this.control,
    this.modified = false,
    this.showMoreButton = true,
    this.controlWidth = 210.0,
    this.onReset,
  });

  final AppTheme theme;
  final String title;
  final String description;
  final Widget control;
  final bool modified;
  final bool showMoreButton;
  final double controlWidth;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final borderColor = theme.dividerColor.withValues(alpha: 0.24);

    return Container(
      constraints: const BoxConstraints(minHeight: 68.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: MenuItemSurface.animationDuration,
              curve: MenuItemSurface.animationCurve,
              width: 2.0,
              color: modified ? theme.dividerColorNormal : Colors.transparent,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 720.0;
                final controlGroup = _SettingsControlGroup(
                  theme: theme,
                  control: control,
                  controlWidth: controlWidth,
                  showMoreButton: showMoreButton,
                  onReset: onReset,
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingText(
                        theme: theme,
                        title: title,
                        description: description,
                      ),
                      const SizedBox(height: 10.0),
                      controlGroup,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _SettingText(
                        theme: theme,
                        title: title,
                        description: description,
                      ),
                    ),
                    const SizedBox(width: 30.0),
                    controlGroup,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingText extends StatelessWidget {
  const _SettingText({
    required this.theme,
    required this.title,
    required this.description,
  });

  final AppTheme theme;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.textColorPrimary,
            fontSize: 15.0,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4.0),
        Text(
          description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.textColorSecondary,
            fontSize: 13.0,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SettingsControlGroup extends StatelessWidget {
  const _SettingsControlGroup({
    required this.theme,
    required this.control,
    required this.controlWidth,
    required this.showMoreButton,
    required this.onReset,
  });

  final AppTheme theme;
  final Widget control;
  final double controlWidth;
  final bool showMoreButton;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: controlWidth, child: control),
        if (showMoreButton) ...[
          const SizedBox(width: 14.0),
          SettingMoreButton(theme: theme, onReset: onReset),
        ],
      ],
    );
  }
}
