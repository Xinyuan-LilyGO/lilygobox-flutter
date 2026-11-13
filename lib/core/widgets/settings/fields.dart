/*
 * @Description: 提供设置项文本输入框、只读字段及输入框装饰。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-11-13 17:42:49
 */

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../context_menu/text_selection_menu.dart';
import '../../theme/definition.dart';
import '../../theme/material_palette.dart';
import '../app_scroll_behavior.dart';
import '../dialog_style.dart';
import '../empty_line_selection.dart';

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
    return EmptyLineSelection(
      child: SizedBox(
        height: 32.0,
        child: TextFormField(
          contextMenuBuilder: AppTextSelectionMenu.build,
          selectionWidthStyle: ui.BoxWidthStyle.tight,
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
            context,
            theme,
            contentPadding: contentPadding,
            // 提示框保留无边框样式，聚焦时显示紫色轮廓。
            disableHover:
                context.findAncestorWidgetOfExactType<Dialog>() != null,
          ),
        ),
      ),
    );
  }
}

/// 使用设置页统一的输入框外观编辑控制器管理的文本。
class SettingControlledTextField extends StatelessWidget {
  const SettingControlledTextField({
    super.key,
    required this.theme,
    required this.controller,
    this.onChanged,
    this.enabled = true,
    this.obscureText = false,
    this.autofocus = false,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.contentPadding,
    this.suffixIcon,
    this.maxLength,
    this.inputFormatters,
  });

  final AppTheme theme;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool obscureText;
  final bool autofocus;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;
  final EdgeInsetsGeometry? contentPadding;
  final Widget? suffixIcon;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    Widget field(ScrollController? scroll) => TextField(
      scrollController: scroll,
      contextMenuBuilder: AppTextSelectionMenu.build,
      selectionWidthStyle: ui.BoxWidthStyle.tight,
      controller: controller,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      autofocus: autofocus,
      keyboardType:
          keyboardType ?? (maxLines > 1 ? TextInputType.multiline : null),
      autocorrect: false,
      enableSuggestions: false,
      onChanged: onChanged,
      cursorColor: theme.dividerColorNormal,
      style: TextStyle(
        color: theme.textColorPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration:
          _inputDecoration(
            context,
            theme,
            contentPadding: maxLines > 1
                ? _multilinePadding(contentPadding)
                : contentPadding,
            disableHover: true,
          ).copyWith(
            suffixIcon: suffixIcon,
            suffixIconConstraints: suffixIcon == null
                ? null
                : const BoxConstraints(minWidth: 32),
            counterText: maxLength == null ? null : '',
          ),
    );
    return EmptyLineSelection(
      child: maxLines > 1
          ? _SettingTextScrollRegion(builder: field)
          : field(null),
    );
  }

  EdgeInsetsGeometry _multilinePadding(EdgeInsetsGeometry? padding) {
    final resolved =
        (padding ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 8))
            .resolve(TextDirection.ltr);
    return resolved.copyWith(right: resolved.right + 14);
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
  BuildContext context,
  AppTheme theme, {
  EdgeInsetsGeometry? contentPadding,
  bool disableHover = false,
}) {
  final dialog = context.findAncestorWidgetOfExactType<Dialog>();
  final surface =
      AppDialogScope.maybeOf(context)?.surfaceColor ??
      dialog?.backgroundColor ??
      (dialog != null
          ? AppDialogStyle.backgroundColor(theme)
          : theme.secondary);
  return InputDecoration(
    isDense: true,
    filled: true,
    hoverColor: disableHover ? Colors.transparent : null,
    fillColor: theme.selectControlColorForSurface(surface),
    contentPadding:
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
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

/// 滚动条以完整输入框为承载区，正文的独立通道不挤动滑块。
class _SettingTextScrollRegion extends StatefulWidget {
  const _SettingTextScrollRegion({required this.builder});
  final Widget Function(ScrollController) builder;

  @override
  State<_SettingTextScrollRegion> createState() =>
      _SettingTextScrollRegionState();
}

class _SettingTextScrollRegionState extends State<_SettingTextScrollRegion> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollbarTheme(
    data: ScrollbarTheme.of(context).copyWith(
      crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
      mainAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
    ),
    child: Scrollbar(controller: _scroll, child: widget.builder(_scroll)),
  );
}
