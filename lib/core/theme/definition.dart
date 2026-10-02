/*
 * @Description: 定义应用主题类型、配色字段及主题名称的本地化映射。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-02 22:01:29
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
  final double? _lightProgress;

  double get lightProgress =>
      _lightProgress ?? (type == ThemeType.light ? 1 : 0);

  // 局部深浅配色也使用全局进度，不能按 type 突然切换。
  Color adaptiveColor({required Color dark, required Color light}) =>
      Color.lerp(dark, light, lightProgress)!;
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
    double? lightProgress,
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
  }) : _lightProgress = lightProgress;

  static AppTheme lerp(AppTheme begin, AppTheme end, double progress) {
    if (progress <= 0) return begin;
    if (progress >= 1) return end;
    return AppTheme(
      type: end.type,
      nameKey: end.nameKey,
      lightProgress:
          begin.lightProgress +
          (end.lightProgress - begin.lightProgress) * progress,
      primary: Color.lerp(begin.primary, end.primary, progress)!,
      secondary: Color.lerp(begin.secondary, end.secondary, progress)!,
      tertiary: Color.lerp(begin.tertiary, end.tertiary, progress)!,
      textColorPrimary: Color.lerp(
        begin.textColorPrimary,
        end.textColorPrimary,
        progress,
      )!,
      textColorSecondary: Color.lerp(
        begin.textColorSecondary,
        end.textColorSecondary,
        progress,
      )!,
      textColorTertiary: Color.lerp(
        begin.textColorTertiary,
        end.textColorTertiary,
        progress,
      )!,
      primaryTextHoverColor: Color.lerp(
        begin.primaryTextHoverColor,
        end.primaryTextHoverColor,
        progress,
      )!,
      primaryTextSelectedColor: Color.lerp(
        begin.primaryTextSelectedColor,
        end.primaryTextSelectedColor,
        progress,
      )!,
      secondaryTextHoverColor: Color.lerp(
        begin.secondaryTextHoverColor,
        end.secondaryTextHoverColor,
        progress,
      )!,
      secondaryTextHoverColorAlt: Color.lerp(
        begin.secondaryTextHoverColorAlt,
        end.secondaryTextHoverColorAlt,
        progress,
      )!,
      secondaryTextSelectedColor: Color.lerp(
        begin.secondaryTextSelectedColor,
        end.secondaryTextSelectedColor,
        progress,
      )!,
      secondaryTextBackgroundColor: Color.lerp(
        begin.secondaryTextBackgroundColor,
        end.secondaryTextBackgroundColor,
        progress,
      )!,
      tertiaryTextBackgroundColor: Color.lerp(
        begin.tertiaryTextBackgroundColor,
        end.tertiaryTextBackgroundColor,
        progress,
      )!,
      tertiaryTextHoverColor: Color.lerp(
        begin.tertiaryTextHoverColor,
        end.tertiaryTextHoverColor,
        progress,
      )!,
      tertiaryTextHighlightColor: Color.lerp(
        begin.tertiaryTextHighlightColor,
        end.tertiaryTextHighlightColor,
        progress,
      )!,
      tertiaryTextSplashColor: Color.lerp(
        begin.tertiaryTextSplashColor,
        end.tertiaryTextSplashColor,
        progress,
      )!,
      appTitleTextColor: Color.lerp(
        begin.appTitleTextColor,
        end.appTitleTextColor,
        progress,
      )!,
      inactiveTextColor: Color.lerp(
        begin.inactiveTextColor,
        end.inactiveTextColor,
        progress,
      )!,
      iconColor: Color.lerp(begin.iconColor, end.iconColor, progress)!,
      iconBackgroundColor: Color.lerp(
        begin.iconBackgroundColor,
        end.iconBackgroundColor,
        progress,
      )!,
      iconHoverColor: Color.lerp(
        begin.iconHoverColor,
        end.iconHoverColor,
        progress,
      )!,
      iconHighlightColor: Color.lerp(
        begin.iconHighlightColor,
        end.iconHighlightColor,
        progress,
      )!,
      iconSplashColor: Color.lerp(
        begin.iconSplashColor,
        end.iconSplashColor,
        progress,
      )!,
      inactiveIconColor: Color.lerp(
        begin.inactiveIconColor,
        end.inactiveIconColor,
        progress,
      )!,
      sidebarIconColor: Color.lerp(
        begin.sidebarIconColor,
        end.sidebarIconColor,
        progress,
      )!,
      sidebarHoverIconColor: Color.lerp(
        begin.sidebarHoverIconColor,
        end.sidebarHoverIconColor,
        progress,
      )!,
      sidebarHoverIconColor2: Color.lerp(
        begin.sidebarHoverIconColor2,
        end.sidebarHoverIconColor2,
        progress,
      )!,
      sidebarIconBackgroundColor: Color.lerp(
        begin.sidebarIconBackgroundColor,
        end.sidebarIconBackgroundColor,
        progress,
      )!,
      sidebarIndicatorColor: Color.lerp(
        begin.sidebarIndicatorColor,
        end.sidebarIndicatorColor,
        progress,
      )!,
      dividerColor: Color.lerp(begin.dividerColor, end.dividerColor, progress)!,
      dividerColorNormal: Color.lerp(
        begin.dividerColorNormal,
        end.dividerColorNormal,
        progress,
      )!,
      basePrimary: Color.lerp(begin.basePrimary, end.basePrimary, progress)!,
      baseSecondary: Color.lerp(
        begin.baseSecondary,
        end.baseSecondary,
        progress,
      )!,
      baseTertiary: Color.lerp(begin.baseTertiary, end.baseTertiary, progress)!,
    );
  }

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
