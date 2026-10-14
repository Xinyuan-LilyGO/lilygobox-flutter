/*
 * @Description: 提供设置项文本输入框、只读字段及输入框装饰。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../context_menu/text_selection_menu.dart';
import '../../theme/definition.dart';

class SettingTextField extends StatelessWidget {
  const SettingTextField({
    super.key,
    required this.theme,
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.keyboardType,
    this.inputFormatters,
  });

  final AppTheme theme;
  final String value;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32.0,
      child: TextFormField(
        contextMenuBuilder: AppTextSelectionMenu.build,
        initialValue: value,
        enabled: enabled,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        cursorColor: theme.dividerColorNormal,
        style: TextStyle(
          color: theme.textColorPrimary,
          fontSize: 13.0,
          fontWeight: FontWeight.w600,
        ),
        decoration: _inputDecoration(theme),
      ),
    );
  }
}

class SettingReadOnlyField extends StatelessWidget {
  const SettingReadOnlyField({
    super.key,
    required this.theme,
    required this.value,
  });

  final AppTheme theme;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.0,
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.textColorSecondary,
          fontSize: 13.0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(AppTheme theme) {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: theme.primary.withValues(alpha: 0.74),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4.0),
      borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.28)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4.0),
      borderSide: BorderSide(color: theme.dividerColorNormal),
    ),
  );
}
