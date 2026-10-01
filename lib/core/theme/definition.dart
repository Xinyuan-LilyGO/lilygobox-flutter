/*
 * @Description: 定义应用主题类型、配色字段及主题名称的本地化映射。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-01 16:54:38
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';

enum ThemeType {
  dark, // 黑色格调
  light, // 亮色格调
}

class AppTheme {
  final ThemeType type;
  final String nameKey;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color textColorPrimary;
  final Color textColorSecondary;
  final Color textColorTertiary;
  final Color primaryTextHoverColor;
  final Color primaryTextSelectedColor;
  final Color secondaryTextHoverColor;
  final Color secondaryTextHoverColorAlt;
  final Color secondaryTextSelectedColor;
  final Color secondaryTextBackgroundColor;
  final Color tertiaryTextBackgroundColor;
  final Color tertiaryTextHoverColor;
  final Color tertiaryTextHighlightColor;
  final Color tertiaryTextSplashColor;
  final Color appTitleTextColor;
  final Color inactiveTextColor;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Color iconHoverColor;
  final Color iconHighlightColor;
  final Color iconSplashColor;
  final Color inactiveIconColor;
  final Color sidebarIconColor;
  final Color sidebarHoverIconColor;
  final Color sidebarHoverIconColor2;
  final Color sidebarIconBackgroundColor;
  final Color sidebarIndicatorColor;
  final Color dividerColor;
  final Color dividerColorNormal;
  final Color basePrimary;
  final Color baseSecondary;
  final Color baseTertiary;

  const AppTheme({
    required this.type,
    required this.nameKey,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.textColorPrimary,
    required this.textColorSecondary,
    required this.textColorTertiary,
    required this.primaryTextHoverColor,
    required this.primaryTextSelectedColor,
    required this.secondaryTextBackgroundColor,
    required this.secondaryTextHoverColor,
    required this.secondaryTextHoverColorAlt,
    required this.secondaryTextSelectedColor,
    required this.tertiaryTextBackgroundColor,
    required this.tertiaryTextHoverColor,
    required this.tertiaryTextHighlightColor,
    required this.tertiaryTextSplashColor,
    required this.appTitleTextColor,
    required this.inactiveTextColor,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.iconHoverColor,
    required this.iconHighlightColor,
    required this.iconSplashColor,
    required this.inactiveIconColor,
    required this.sidebarIconColor,
    required this.sidebarHoverIconColor,
    required this.sidebarHoverIconColor2,
    required this.sidebarIconBackgroundColor,
    required this.sidebarIndicatorColor,
    required this.dividerColor,
    required this.dividerColorNormal,
    required this.basePrimary,
    required this.baseSecondary,
    required this.baseTertiary,
  });

  String getName(AppLocalizations appLocalizations) {
    switch (nameKey) {
      case 'theme_dark':
        return appLocalizations.themeDark;
      case 'theme_light':
        return appLocalizations.themeLight;
      default:
        return nameKey;
    }
  }
}
