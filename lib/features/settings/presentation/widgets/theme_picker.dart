/*
 * @Description: 使用浅色和深色预览卡片直接选择主题，并展示选中状态。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/menu_item_surface.dart';

/// 用应用缩略图直接选择主题，沿用设置选项的交互效果。
class ThemePicker extends StatelessWidget {
  const ThemePicker({
    super.key,
    required this.theme,
    required this.themes,
    required this.value,
    required this.onChanged,
  });

  final AppTheme theme;
  final List<AppTheme> themes;
  final ThemeType value;
  final ValueChanged<ThemeType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final type in [ThemeType.light, ThemeType.dark])
          _buildChoice(context, themes.firstWhere((item) => item.type == type)),
      ],
    );
  }

  Widget _buildChoice(BuildContext context, AppTheme preview) {
    final selected = value == preview.type;
    final label = preview.getName(context.l10n);

    return SizedBox(
      width: 114,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: label,
            child: MenuItemSurface(
              key: ValueKey('theme-choice-${preview.type.name}'),
              theme: theme,
              isSelected: selected,
              onPressed: () => onChanged(preview.type),
              border: Border.all(
                color: selected
                    ? theme.basePrimary
                    : theme.dividerColor.withValues(alpha: 0.28),
                width: selected ? 2 : 1,
              ),
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 74,
                  child: Ink(
                    color: preview.secondary,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          height: double.infinity,
                          child: Ink(color: preview.primary),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _previewLine(preview.basePrimary),
                              const SizedBox(height: 8),
                              _previewLine(preview.tertiary),
                              const SizedBox(height: 8),
                              _previewLine(preview.tertiary),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? theme.textColorPrimary
                    : theme.textColorTertiary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewLine(Color color) => SizedBox(
    width: 54,
    height: 7,
    child: Ink(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}
