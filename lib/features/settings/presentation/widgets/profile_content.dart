/*
 * @Description: 展示个人中心未登录状态和账号入口，明确提示账号功能尚未开放。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 20:56:44
 * @LastEditTime: 2026-10-02 20:56:44
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import 'content_layout.dart';

class ProfileContent extends StatelessWidget {
  const ProfileContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = SettingsColors(theme);
    return SettingsContentLayout(
      theme: theme,
      title: l10n.profile,
      description: l10n.profileDescription,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: colors.control,
              child: Icon(
                Symbols.person_rounded,
                fill: 1,
                size: 30,
                color: theme.textColorSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.notSignedIn,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.accountUnavailable,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: theme.textColorTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _accountAction(context, l10n.signIn, primary: true),
            _accountAction(context, l10n.createAccount, primary: false),
          ],
        ),
      ],
    );
  }

  Widget _accountAction(
    BuildContext context,
    String label, {
    required bool primary,
  }) {
    final colors = SettingsColors(theme);
    final background = primary ? theme.basePrimary : colors.control;
    final foreground =
        primary &&
            ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : theme.textColorPrimary;
    return MenuItemSurface(
      key: ValueKey(primary ? 'profile-sign-in' : 'profile-create-account'),
      theme: theme,
      backgroundColor: background,
      hoverColor: primary
          ? Color.alphaBlend(foreground.withValues(alpha: 0.1), background)
          : colors.hover,
      onPressed: () {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.accountUnavailable)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
