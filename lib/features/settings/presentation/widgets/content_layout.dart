/*
 * @Description: 统一应用设置的紧凑内容布局、设置字段和局部深浅配色。
 */

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/dialog_style.dart';

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

  static const contentWidth = 760.0;
  static const pagePadding = EdgeInsets.fromLTRB(24, 22, 24, 32);

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: pagePadding,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsContentHeader(
              theme: theme,
              title: title,
              description: description,
            ),
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// 普通设置页面与延迟构建的模型服务列表共用的标题。
class SettingsContentHeader extends StatelessWidget {
  const SettingsContentHeader({
    super.key,
    required this.theme,
    required this.title,
    required this.description,
  });
  final AppTheme theme;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
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
      const SizedBox(height: 14),
      Divider(height: 1, color: SettingsColors(theme).divider),
      const SizedBox(height: 14),
    ],
  );
}

/// 无边框设置分组，保持与存储管理页面一致的表面样式。
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.theme,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  final AppTheme theme;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: theme.primary,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class SettingsSection extends StatelessWidget {
  static const contentPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 10,
  );
  const SettingsSection({
    super.key,
    required this.theme,
    required this.title,
    required this.description,
    this.child,
    this.trailing,
    this.stacked = false,
  });
  final AppTheme theme;
  final String title;
  final String description;
  final Widget? child;
  final Widget? trailing;
  final bool stacked;

  @override
  Widget build(BuildContext context) => SettingsPanel(
    theme: theme,
    padding: contentPadding,
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (stacked || constraints.maxWidth < 560) {
          return SettingsField(
            theme: theme,
            title: title,
            description: description,
            trailing: trailing,
            child: child,
          );
        }
        return Row(
          children: [
            Expanded(
              child: Column(
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
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: theme.textColorTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null || child != null) ...[
              const SizedBox(width: 20),
              if (trailing != null)
                trailing!
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: child,
                ),
            ],
          ],
        );
      },
    ),
  );
}

class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.theme,
    required this.title,
    required this.description,
    this.child,
    this.trailing,
  });
  final AppTheme theme;
  final String title;
  final String description;
  final Widget? child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(title, style: AppDialogStyle.fieldTitleStyle(theme)),
          ),
          if (trailing case final action?) ...[
            const SizedBox(width: 8),
            action,
          ],
        ],
      ),
      if (description.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(description, style: AppDialogStyle.descriptionStyle(theme)),
      ],
      if (child case final control?) ...[const SizedBox(height: 8), control],
    ],
  );
}
