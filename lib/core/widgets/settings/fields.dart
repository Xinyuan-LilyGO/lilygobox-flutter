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
    this.contentPadding,
  });

  final AppTheme theme;
  final String value;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final EdgeInsetsGeometry? contentPadding;

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
        decoration: _inputDecoration(
          theme,
          contentPadding: contentPadding,
          // 提示框沿用搜索框的无边框底色，聚焦时显示紫色轮廓。
          disableHover: context.findAncestorWidgetOfExactType<Dialog>() != null,
        ),
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

InputDecoration _inputDecoration(
  AppTheme theme, {
  EdgeInsetsGeometry? contentPadding,
  bool disableHover = false,
}) {
  return InputDecoration(
    isDense: true,
    filled: true,
    hoverColor: disableHover ? Colors.transparent : null,
    fillColor: disableHover
        ? theme.secondary
        : theme.primary.withValues(alpha: 0.74),
    contentPadding:
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
    // 明确禁用边框，避免保存期间回退为 Material 默认下划线。
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4.0),
      borderSide: BorderSide.none,
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4.0),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4.0),
      borderSide: disableHover
          ? BorderSide.none
          : BorderSide(color: theme.dividerColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4.0),
      borderSide: BorderSide(
        color: disableHover ? theme.basePrimary : theme.dividerColorNormal,
      ),
    ),
  );
}
