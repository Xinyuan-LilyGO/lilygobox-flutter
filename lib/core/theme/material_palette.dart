/*
 * @Description: 集中维护原有灰阶与紫色配色，并提供 Material 3 语义角色映射。
 * @Author: LILYGO_L
 * @Date: 2026-10-09 17:00:00
 * @LastEditTime: 2026-10-09 18:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';

import 'definition.dart';

/// 保留产品原有颜色种类；Material 3 负责角色组织，不替换品牌和灰阶。
class MaterialPalette {
  static final Map<ThemeType, AppTheme> _themes = {
    ThemeType.dark: AppTheme(
      type: ThemeType.dark,
      nameKey: 'theme_dark',
      primary: const Color.fromARGB(255, 25, 25, 25),
      secondary: const Color.fromARGB(255, 45, 45, 45),
      tertiary: const Color.fromARGB(255, 65, 65, 65),
      textColorPrimary: const Color.fromARGB(255, 230, 230, 230),
      textColorSecondary: const Color.fromARGB(255, 220, 220, 220),
      textColorTertiary: const Color.fromARGB(255, 150, 150, 150),
      // 悬停保持较弱的灰阶反馈，选中使用更明确的实色层级。
      primaryTextHoverColor: const Color.fromARGB(255, 38, 38, 38),
      primaryTextSelectedColor: const Color.fromARGB(255, 68, 68, 68),
      secondaryTextBackgroundColor: const Color.fromARGB(255, 60, 60, 60),
      secondaryTextHoverColor: const Color.fromARGB(255, 56, 56, 56),
      secondaryTextHoverColorAlt: const Color.fromARGB(255, 80, 80, 80),
      secondaryTextSelectedColor: const Color.fromARGB(255, 94, 94, 94),
      tertiaryTextBackgroundColor: const Color.fromARGB(255, 40, 40, 40),
      tertiaryTextHoverColor: const Color.fromARGB(255, 50, 50, 50),
      tertiaryTextHighlightColor: const Color.fromARGB(255, 80, 80, 80),
      tertiaryTextSplashColor: const Color.fromARGB(255, 60, 60, 60),
      appTitleTextColor: const Color.fromARGB(255, 215, 215, 215),
      inactiveTextColor: Colors.grey,
      iconColor: const Color.fromARGB(255, 215, 215, 215),
      iconBackgroundColor: const Color.fromARGB(255, 80, 80, 80),
      iconHoverColor: const Color.fromARGB(255, 120, 120, 120),
      iconHighlightColor: const Color.fromARGB(255, 130, 130, 130),
      iconSplashColor: const Color.fromARGB(255, 180, 180, 180),
      inactiveIconColor: Colors.grey,
      sidebarIconColor: const Color.fromARGB(255, 215, 215, 215),
      sidebarHoverIconColor: const Color.fromARGB(255, 120, 120, 120),
      sidebarHoverIconColor2: const Color.fromARGB(255, 100, 177, 76),
      sidebarIconBackgroundColor: const Color.fromARGB(255, 55, 55, 55),
      sidebarIndicatorColor: const Color.fromARGB(255, 200, 200, 200),
      dividerColor: const Color.fromARGB(255, 100, 100, 100),
      dividerColorNormal: const Color.fromARGB(255, 126, 109, 202),
      basePrimary: const Color.fromARGB(255, 126, 109, 202),
      baseSecondary: const Color.fromARGB(255, 126, 109, 202),
      baseTertiary: const Color.fromARGB(255, 145, 127, 221),
    ),
    ThemeType.light: AppTheme(
      type: ThemeType.light,
      nameKey: 'theme_light',
      primary: const Color(0xFFF5F5F5),
      secondary: const Color(0xFFE0E0E0),
      tertiary: const Color(0xFFBDBDBD),
      textColorPrimary: const Color.fromARGB(255, 25, 25, 25),
      textColorSecondary: const Color.fromARGB(255, 35, 35, 35),
      textColorTertiary: const Color.fromARGB(255, 105, 105, 105),
      primaryTextHoverColor: const Color.fromARGB(255, 223, 223, 223),
      // 浅色主题用较小的灰阶差距，避免选中块显得过重。
      primaryTextSelectedColor: const Color.fromARGB(255, 210, 210, 210),
      secondaryTextBackgroundColor: const Color.fromARGB(255, 190, 190, 190),
      secondaryTextHoverColor: const Color.fromARGB(255, 206, 206, 206),
      secondaryTextHoverColorAlt: const Color.fromARGB(255, 180, 180, 180),
      secondaryTextSelectedColor: const Color.fromARGB(255, 190, 190, 190),
      tertiaryTextBackgroundColor: const Color.fromARGB(255, 160, 160, 160),
      tertiaryTextHoverColor: const Color.fromARGB(255, 180, 180, 180),
      tertiaryTextHighlightColor: const Color.fromARGB(100, 200, 200, 200),
      tertiaryTextSplashColor: const Color.fromARGB(100, 210, 210, 210),
      appTitleTextColor: const Color.fromARGB(255, 50, 50, 50),
      inactiveTextColor: Colors.grey,
      iconColor: const Color.fromARGB(255, 40, 40, 40),
      iconBackgroundColor: const Color.fromARGB(255, 200, 200, 200),
      iconHoverColor: const Color.fromARGB(255, 180, 180, 180),
      iconHighlightColor: const Color.fromARGB(255, 160, 160, 160),
      iconSplashColor: const Color.fromARGB(255, 150, 150, 150),
      inactiveIconColor: Colors.grey,
      sidebarIconColor: const Color.fromARGB(255, 40, 40, 40),
      sidebarHoverIconColor: const Color.fromARGB(255, 170, 170, 170),
      sidebarHoverIconColor2: const Color.fromARGB(255, 125, 191, 105),
      sidebarIconBackgroundColor: const Color.fromARGB(255, 200, 200, 200),
      sidebarIndicatorColor: const Color.fromARGB(255, 40, 40, 40),
      dividerColor: const Color.fromARGB(255, 80, 80, 80),
      dividerColorNormal: const Color(0xFF7963C6),
      basePrimary: const Color(0xFF7963C6),
      baseSecondary: const Color(0xFF7963C6),
      baseTertiary: const Color(0xFF7963C6),
    ),
  };

  static final light = _colorScheme(_themes[ThemeType.light]!);
  static final dark = _colorScheme(_themes[ThemeType.dark]!);

  /// 现有组件继续使用原来的表面、文字和交互颜色。
  static AppTheme create(ThemeType type) => _themes[type]!;

  /// 内置 Material 控件使用语义角色，同时将所有常规表面固定为中性灰。
  static ColorScheme _colorScheme(AppTheme theme) {
    final isDark = theme.type == ThemeType.dark;
    final control = isDark ? const Color(0xFF242424) : const Color(0xFFEEEEEE);
    return ColorScheme.fromSeed(
      seedColor: theme.basePrimary,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: theme.basePrimary,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF40394F)
          : const Color(0xFFE2DDEB),
      onPrimaryContainer: theme.textColorPrimary,
      secondary: theme.baseSecondary,
      onSecondary: Colors.white,
      secondaryContainer: theme.secondaryTextSelectedColor,
      onSecondaryContainer: theme.textColorPrimary,
      tertiary: theme.baseTertiary,
      onTertiary: Colors.white,
      tertiaryContainer: theme.primaryTextSelectedColor,
      onTertiaryContainer: theme.textColorPrimary,
      surface: theme.primary,
      surfaceDim: isDark ? theme.primary : theme.tertiary,
      surfaceBright: isDark ? theme.tertiary : theme.primary,
      surfaceContainerLowest: theme.primary,
      surfaceContainerLow: theme.secondary,
      surfaceContainer: theme.secondaryTextBackgroundColor,
      surfaceContainerHigh: control,
      surfaceContainerHighest: theme.tertiary,
      onSurface: theme.textColorPrimary,
      onSurfaceVariant: theme.textColorTertiary,
      outline: theme.dividerColor,
      outlineVariant: theme.textColorPrimary.withValues(alpha: .07),
      inverseSurface: isDark ? lightSurface : darkSurface,
      onInverseSurface: isDark ? darkSurface : lightSurface,
      inversePrimary: isDark
          ? const Color(0xFF7963C6)
          : const Color(0xFF7E6DCA),
      surfaceTint: Colors.transparent,
      error: isDark ? const Color(0xFFB94A48) : const Color(0xFFBC3434),
      onError: Colors.white,
    );
  }

  static const lightSurface = Color(0xFFF5F5F5);
  static const darkSurface = Color(0xFF191919);
}

/// 语义颜色与既有 AppTheme.lerp 使用同一进度，保留平滑主题切换。
extension MaterialThemeRoles on AppTheme {
  /// 按控件实际底色选择悬停层级，避免主背景的悬停灰色融入二级背景。
  Color hoverColorForBackground(Color background) {
    final surface = Color.alphaBlend(background, primary);
    if (surface == primary) return primaryTextHoverColor;
    if (surface == secondary) return secondaryTextHoverColor;
    return Color.alphaBlend(textColorPrimary.withValues(alpha: .08), surface);
  }

  ColorScheme get materialColors => ColorScheme.lerp(
    MaterialPalette.dark,
    MaterialPalette.light,
    lightProgress,
  );

  /// 设置侧栏沿用原来的深灰与浅灰。
  Color get settingsSidebarColor => adaptiveColor(
    dark: const Color(0xFF141414),
    light: MaterialPalette.lightSurface,
  );

  /// 悬停弱于选中：深色用更暗的灰，浅色用更浅的灰，避免两种状态混淆。
  Color get settingsHoverColor => adaptiveColor(
    dark: const Color(0xFF262626),
    light: const Color(0xFFE5E5E5),
  );

  /// 浮层保留亮色白底与深色灰底，不应用种子色染色。
  Color get popupSurfaceColor => adaptiveColor(
    dark: Color.lerp(secondary, tertiary, .55)!,
    light: Colors.white,
  );

  /// 电池保留此前单独确认的紫色填充。
  Color get batteryFillColor => adaptiveColor(
    dark: const Color(0xFFB5A1F2),
    light: const Color(0xFF7962C3),
  );
}
