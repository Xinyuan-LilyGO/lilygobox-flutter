import 'dart:ui' as ui;

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../context_menu/text_selection_menu.dart';
import '../../theme/definition.dart';
import '../search_clear_button.dart';

/// 与紧凑模型选择器的搜索框保持一致，包括清空按钮的反馈。
class SettingSearchField extends StatelessWidget {
  const SettingSearchField({
    super.key,
    required this.theme,
    required this.controller,
    required this.hintText,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    required this.onClear,
  });
  final AppTheme theme;
  final TextEditingController controller;
  final String hintText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TextField(
    contextMenuBuilder: AppTextSelectionMenu.build,
    selectionWidthStyle: ui.BoxWidthStyle.tight,
    controller: controller,
    enabled: enabled,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    style: TextStyle(fontSize: 13, color: theme.textColorPrimary),
    cursorColor: theme.basePrimary,
    decoration: InputDecoration(
      isDense: true,
      hintText: hintText,
      hintStyle: TextStyle(color: theme.textColorTertiary),
      filled: true,
      fillColor: theme.primary,
      hoverColor: Colors.transparent,
      prefixIcon: Padding(
        padding: const EdgeInsetsDirectional.only(start: 6, top: 6, bottom: 6),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            Symbols.search,
            size: 18,
            color: theme.textColorSecondary,
          ),
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 36),
      suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      suffixIcon: controller.text.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.all(6),
              child: SearchClearButton(
                theme: theme,
                onPressed: enabled ? onClear : null,
              ),
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: theme.basePrimary),
      ),
    ),
  );
}
