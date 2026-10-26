/*
 * @Description: 统一应用设置的紧凑内容布局、设置字段和局部深浅配色。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 19:41:48
 * @LastEditTime: 2026-10-02 22:01:29
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';

class SettingsColors {
  const SettingsColors(this.theme);
  final AppTheme theme;
  Color get sidebar => theme.settingsSidebarColor;
  Color get content => theme.secondary;
  Color get control => theme.materialColors.surfaceContainerHigh;
  Color get hover => theme.settingsHoverColor;
  Color get divider => theme.materialColors.outlineVariant;
}

class SettingsContentLayout extends StatelessWidget {
  const SettingsContentLayout({
    super.key,
    required this.theme,
    required this.title,
    required this.description,
    required this.children,
  });
  final AppTheme theme;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
    child: Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: theme.textColorPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: theme.textColorTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Divider(height: 1, color: SettingsColors(theme).divider),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    ),
  );
}

class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.theme,
    required this.title,
    required this.description,
    required this.child,
    this.trailing,
  });
  final AppTheme theme;
  final String title;
  final String description;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: theme.textColorPrimary,
        ),
      ),
      const SizedBox(height: 3),
      Row(
        children: [
          Flexible(
            fit: trailing == null ? FlexFit.tight : FlexFit.loose,
            child: Text(
              description,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.textColorTertiary,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
      const SizedBox(height: 12),
      child,
    ],
  );
}
