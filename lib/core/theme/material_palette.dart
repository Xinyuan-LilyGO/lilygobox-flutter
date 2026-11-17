/*
 * @Description: 集中维护原有灰阶与紫色配色，并提供 Material 3 语义角色映射。
 */
import 'package:material_ui/material_ui.dart';

import 'definition.dart';

/// 保留产品原有颜色种类；Material 3 负责角色组织，不替换品牌和灰阶。
class MaterialPalette {
  static final Map<ThemeType, AppTheme> _themes = {
    ThemeType.dark: AppTheme(
      type: ThemeType.dark,
      nameKey: 'theme_dark',
      // 暗色主背景微幅提亮，让全局侧栏与顶部栏更清晰地区分于窗口外层。
      primary: const Color.fromARGB(255, 35, 35, 35),
      secondary: const Color.fromARGB(255, 60, 60, 60),
      tertiary: const Color.fromARGB(255, 70, 70, 70),
      textColorPrimary: const Color.fromARGB(255, 230, 230, 230),
      textColorSecondary: const Color.fromARGB(255, 220, 220, 220),
      textColorTertiary: const Color.fromARGB(255, 150, 150, 150),
      // 悬停保持较弱的灰阶反馈，选中使用更明确的实色层级。
      primaryTextHoverColor: const Color.fromARGB(255, 52, 52, 52),
      primaryTextSelectedColor: const Color.fromARGB(255, 64, 64, 64),
      secondaryTextBackgroundColor: const Color.fromARGB(255, 60, 60, 60),
      secondaryTextHoverColor: const Color.fromARGB(255, 72, 72, 72),
      secondaryTextHoverColorAlt: const Color.fromARGB(255, 98, 98, 98),
      secondaryTextSelectedColor: const Color.fromARGB(255, 112, 112, 112),
      tertiaryTextBackgroundColor: const Color.fromARGB(255, 40, 40, 40),
      tertiaryTextHoverColor: const Color.fromARGB(255, 66, 66, 66),
      tertiaryTextHighlightColor: const Color.fromARGB(255, 80, 80, 80),
      tertiaryTextSplashColor: const Color.fromARGB(255, 60, 60, 60),
      tertiarySurfaceButtonBackgroundColor: const Color(0xFF363636),
      tertiarySurfaceButtonHoverColor: const Color(0xFF404040),
      tertiarySurfaceButtonPressedColor: const Color(0xFF4A4A4A),
      tertiarySurfaceButtonHighlightColor: const Color.fromARGB(
        97,
        255,
        255,
        255,
      ),
      tertiarySurfaceButtonSplashColor: const Color.fromARGB(
        128,
        255,
        255,
        255,
      ),
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
      // 全局分割线在深色承载背景上保留清晰、克制的灰阶对比。
      dividerColor: const Color(0xFF505050),
      dividerColorNormal: const Color.fromARGB(255, 126, 109, 202),
      basePrimary: const Color.fromARGB(255, 126, 109, 202),
      baseSecondary: const Color.fromARGB(255, 126, 109, 202),
      baseTertiary: const Color.fromARGB(255, 145, 127, 221),
    ),
    ThemeType.light: AppTheme(
      type: ThemeType.light,
      nameKey: 'theme_light',
      primary: const Color(0xFFF5F5F5),
      secondary: const Color(0xFFE6E6E6),
      tertiary: const Color(0xFFD0D0D0),
      textColorPrimary: const Color.fromARGB(255, 25, 25, 25),
      textColorSecondary: const Color.fromARGB(255, 35, 35, 35),
      textColorTertiary: const Color.fromARGB(255, 105, 105, 105),
      primaryTextHoverColor: const Color.fromARGB(255, 223, 223, 223),
      // 浅色主题用较小的灰阶差距，避免选中块显得过重。
      primaryTextSelectedColor: const Color.fromARGB(255, 204, 204, 204),
      secondaryTextBackgroundColor: const Color.fromARGB(255, 190, 190, 190),
      secondaryTextHoverColor: const Color.fromARGB(255, 206, 206, 206),
      secondaryTextHoverColorAlt: const Color.fromARGB(255, 180, 180, 180),
      secondaryTextSelectedColor: const Color.fromARGB(255, 184, 184, 184),
      tertiaryTextBackgroundColor: const Color.fromARGB(255, 160, 160, 160),
      tertiaryTextHoverColor: const Color.fromARGB(255, 180, 180, 180),
      tertiaryTextHighlightColor: const Color.fromARGB(100, 200, 200, 200),
      tertiaryTextSplashColor: const Color.fromARGB(100, 210, 210, 210),
      tertiarySurfaceButtonBackgroundColor: const Color(0xFFC6C6C6),
      tertiarySurfaceButtonHoverColor: const Color(0xFFB8B8B8),
      tertiarySurfaceButtonPressedColor: const Color(0xFFAAAAAA),
      tertiarySurfaceButtonHighlightColor: const Color.fromARGB(48, 0, 0, 0),
      tertiarySurfaceButtonSplashColor: const Color.fromARGB(72, 0, 0, 0),
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
      dividerColor: const Color(0xFFD0D0D0),
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
      outlineVariant: theme.dividerColor,
      inverseSurface: isDark ? lightSurface : darkSurface,
      onInverseSurface: isDark ? darkSurface : lightSurface,
      inversePrimary: isDark
          ? const Color(0xFF7963C6)
          : const Color(0xFF7E6DCA),
      surfaceTint: Colors.transparent,
      error: isDark ? const Color(0xFFD6555A) : const Color(0xFFDC4242),
      onError: Colors.white,
    );
  }

  static const lightSurface = Color(0xFFF5F5F5);
  static const darkSurface = Color(0xFF191919);
}

/// 语义颜色与既有 AppTheme.lerp 使用同一进度，保留平滑主题切换。
extension MaterialThemeRoles on AppTheme {
  /// 下拉控件从承载背景派生底色，亮色主题降低对比并随主题切换平滑过渡。
  Color selectControlColorForSurface(Color surface) =>
      Color.lerp(surface, textColorPrimary, .12 - .06 * lightProgress)!;

  /// 设置页普通按钮、下拉控件和服务卡片共用的表面底色。
  Color get settingsControlBackgroundColor =>
      selectControlColorForSurface(secondary);

  ButtonStateColors buttonColorsForSurface(Color surface) =>
      ButtonStateColors.forSurface(surface);
  ButtonStateColors get buttonStateColors => ButtonStateColors(
    background: primary,
    hover: iconBackgroundColor,
    pressed: iconHighlightColor,
    selected: primaryTextSelectedColor,
  );

  /// 第三层背景卡片上的文字操作按钮，复用对应层级的主题状态色。
  ButtonStateColors get tertiarySurfaceButtonColors => ButtonStateColors(
    background: tertiarySurfaceButtonBackgroundColor,
    hover: tertiarySurfaceButtonHoverColor,
    pressed: tertiarySurfaceButtonPressedColor,
    selected: tertiarySurfaceButtonPressedColor,
  );

  /// 页面内小型图标操作按钮使用的高对比底色。
  /// 深色取最深表面，浅色取现有亮色图标按钮背景，避免控件变暗或融入页面。
  Color get deepestControlColor =>
      adaptiveColor(dark: primary, light: iconBackgroundColor);

  /// 队列与内层文字输入区共用底色，交互色由这个实际背景派生。
  Color get assistantQueueSurfaceColor => primary;

  /// 为任意控件背景生成不会与背景融为一体的交互层。
  /// 颜色随背景明暗反向偏移，避免每个组件重复维护一套灰阶。
  Color interactionHoverColor(Color background) {
    final isLight = background.computeLuminance() > .5;
    return Color.lerp(
      background,
      isLight ? Colors.black : Colors.white,
      isLight ? .1 : .18,
    )!;
  }

  Color interactionPressedColor(Color background) {
    final isLight = background.computeLuminance() > .5;
    return Color.lerp(
      background,
      isLight ? Colors.black : Colors.white,
      isLight ? .18 : .28,
    )!;
  }

  Color interactionSelectedColor(Color background) {
    final isLight = background.computeLuminance() > .5;
    return Color.lerp(
      background,
      isLight ? Colors.black : Colors.white,
      isLight ? .14 : .24,
    )!;
  }

  /// 按控件实际底色选择悬停层级，避免主背景的悬停灰色融入二级背景。
  Color hoverColorForBackground(Color background) {
    final surface = Color.alphaBlend(background, primary);
    if (surface == primary) return primaryTextHoverColor;
    if (surface == secondary) return secondaryTextHoverColor;
    return interactionHoverColor(surface);
  }

  ColorScheme get materialColors => ColorScheme.lerp(
    MaterialPalette.dark,
    MaterialPalette.light,
    lightProgress,
  );

  /// 紫色容器上的辅助内容单独配对，避免灰色文字发闷或对比度不足。
  Color get deviceAccentMutedColor => adaptiveColor(
    dark: const Color(0xFFBBB2CB),
    light: const Color(0xFF655D75),
  );

  /// 紫色容器上的连接方式强调色；不改变常规表面的品牌紫色。
  Color get deviceAccentForegroundColor => adaptiveColor(
    dark: const Color(0xFFC5B5EF),
    light: const Color(0xFF6445AA),
  );

  /// 设置侧栏与主界面导航和窗口顶部栏使用一致的主题背景色。
  Color get settingsSidebarColor => primary;

  /// 设置页搜索框在暗色背景上使用略亮的控件底色，亮色保持主背景白色。
  Color get settingsSearchBackgroundColor => adaptiveColor(
    dark: const Color(0xFF2A2A2A),
    light: primary,
  );

  /// 悬停提示和应用通知共用的反色背景颜色。
  Color get noticeBackgroundColor => materialColors.inverseSurface;

  /// 设置导航复用全局主表面的悬停色，避免独立灰阶低于侧栏底色。
  Color get settingsHoverColor => buttonColorsForSurface(primary).hover;

  /// 浮层使用亮色白底与暗色近黑底，不混入承载层灰色或种子色。
  Color get popupSurfaceColor =>
      adaptiveColor(dark: const Color(0xFF191919), light: Colors.white);

  /// 扩大权限的标题、说明与只读盾牌共用偏红橙色，亮色主题降低亮度。
  Color get permissionWarningColor => adaptiveColor(
    dark: const Color(0xFFE88B57),
    light: const Color(0xFFB85A2B),
  );

  /// 正常电量使用绿色，亮暗主题分别保持图形对比度。
  Color get batteryFillColor => adaptiveColor(
    dark: const Color(0xFF43E06A),
    light: const Color(0xFF43D96A),
  );
}

/// 应用共用背景上紧凑按钮的语义状态。
class ButtonStateColors {
  const ButtonStateColors({
    required this.background,
    required this.hover,
    required this.pressed,
    required this.selected,
  });

  final Color background;
  final Color hover;
  final Color pressed;
  final Color selected;

  factory ButtonStateColors.forSurface(Color surface) {
    final light = surface.computeLuminance() > .5;
    final contrast = light ? Colors.black : Colors.white;
    return ButtonStateColors(
      background: Color.lerp(surface, contrast, light ? .1 : .2)!,
      hover: light
          ? const Color(0xFFE5E5E5)
          : Color.lerp(surface, contrast, .10)!,
      pressed: Color.lerp(surface, contrast, light ? .28 : .25)!,
      selected: Color.lerp(surface, contrast, light ? .19 : .18)!,
    );
  }
}
