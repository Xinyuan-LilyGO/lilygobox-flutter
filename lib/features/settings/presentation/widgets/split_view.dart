/*
 * @Description: 构建可拖动且不折叠的设置导航、移动端分类导航。
 * @Author: LILYGO_L
 * @Date: 2025-10-31 17:01:16
 * @LastEditTime: 2026-10-04 13:01:33
 * @License: GPL 3.0
 */

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/storage/preferences.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../../account/presentation/widgets/avatar.dart';
import '../../../account/state/provider.dart';
import 'about_content.dart';
import 'content_layout.dart';
import 'general_content.dart';
import 'language_and_region_content.dart';
import 'personalization_content.dart';
import 'profile_content.dart';

enum _SettingsCategory { appearance, language, general }

class SettingsSplitView extends StatefulWidget {
  const SettingsSplitView({super.key});
  @override
  State<SettingsSplitView> createState() => _SettingsSplitViewState();
}

class _SettingsSplitViewState extends State<SettingsSplitView> {
  _SettingsCategory _category = _SettingsCategory.appearance;
  bool _about = false;
  bool _profile = true;
  bool _mobileDetail = false;
  double _sidebarWidth = 212;
  double _dragStartX = 0;
  double _dragStartWidth = 212;

  void _close() => context.read<AppNavigationProvider>().closeSettings();

  void _resizeSidebar(double width) {
    setState(() => _sidebarWidth = width);
    context.read<AppPreferences?>()?.setValue('settingsSidebarWidth', width);
  }

  void _select(bool about, {_SettingsCategory? category}) => setState(() {
    _about = about;
    _profile = false;
    if (category != null) _category = category;
    _mobileDetail = true;
  });

  void _openProfile() => setState(() {
    _profile = true;
    _about = false;
    _mobileDetail = true;
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final colors = SettingsColors(theme);
    final preferences = context.watch<AppPreferences?>();
    final savedWidth =
        preferences?.doubleValue('settingsSidebarWidth', 212, 176, 300) ??
        _sidebarWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;
        final maxSidebar = math.max(
          176.0,
          math.min(300.0, constraints.maxWidth * 0.4),
        );
        final width = savedWidth.clamp(176.0, maxSidebar).toDouble();
        void back() {
          if (mobile && _mobileDetail) {
            setState(() => _mobileDetail = false);
          } else {
            _close();
          }
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) back();
          },
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): back},
            child: Focus(
              autofocus: true,
              child: mobile
                  ? (_mobileDetail
                        ? _content(theme, colors, mobile: true, onBack: back)
                        : _sidebar(theme, colors, mobile: true))
                  : Stack(
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              key: const ValueKey('settings-sidebar'),
                              width: width,
                              child: _sidebar(theme, colors),
                            ),
                            Expanded(
                              child: _content(
                                theme,
                                colors,
                                mobile: false,
                                onBack: back,
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          left: width - 4,
                          top: 0,
                          bottom: 0,
                          child: Semantics(
                            label: context.l10n.resizeSettingsSidebar,
                            value: width.round().toString(),
                            increasedValue: (width + 8)
                                .clamp(176, maxSidebar)
                                .round()
                                .toString(),
                            decreasedValue: (width - 8)
                                .clamp(176, maxSidebar)
                                .round()
                                .toString(),
                            onIncrease: () => _resizeSidebar(
                              (width + 8).clamp(176, maxSidebar).toDouble(),
                            ),
                            onDecrease: () => _resizeSidebar(
                              (width - 8).clamp(176, maxSidebar).toDouble(),
                            ),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeLeftRight,
                              child: GestureDetector(
                                key: const ValueKey('settings-resize-handle'),
                                behavior: HitTestBehavior.translucent,
                                onHorizontalDragStart: (details) {
                                  _dragStartX = details.globalPosition.dx;
                                  _dragStartWidth = width;
                                },
                                onHorizontalDragUpdate: (details) =>
                                    _resizeSidebar(
                                      (_dragStartWidth +
                                              details.globalPosition.dx -
                                              _dragStartX)
                                          .clamp(176, maxSidebar)
                                          .toDouble(),
                                    ),
                                child: const SizedBox(width: 8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _sidebar(
    AppTheme theme,
    SettingsColors colors, {
    bool mobile = false,
  }) {
    final l10n = context.l10n;
    final user = context.watch<AccountProvider?>()?.user;
    final categories = {
      _SettingsCategory.appearance: (
        l10n.personalization,
        Symbols.palette_rounded,
      ),
      _SettingsCategory.language: (
        l10n.languageAndRegion,
        Symbols.language_rounded,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(right: BorderSide(color: colors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: MenuItemSurface(
                    key: const ValueKey('settings-profile'),
                    theme: theme,
                    isSelected: _profile && !mobile,
                    backgroundColor: colors.sidebar,
                    hoverColor: colors.hover,
                    onPressed: _openProfile,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          AccountAvatar(theme: theme, user: user, radius: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.displayName ?? l10n.profile,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textColorPrimary,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  user == null
                                      ? l10n.notSignedIn
                                      : '@${user.login}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: theme.textColorTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (mobile) ...[
                  const SizedBox(width: 4),
                  AppTooltip(
                    message: l10n.back,
                    verticalOffset: 16,
                    child: _iconButton(theme, Symbols.close_rounded, _close),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: colors.divider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
              children: [
                _sectionTitle(theme, l10n.basic),
                _navigationItem(
                  theme,
                  colors,
                  Symbols.tune_rounded,
                  l10n.general,
                  !_profile &&
                      !_about &&
                      _category == _SettingsCategory.general &&
                      !mobile,
                  () => _select(false, category: _SettingsCategory.general),
                  const ValueKey('settings-category-general'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 14,
                  ),
                  child: Divider(height: 1, color: colors.divider),
                ),
                _sectionTitle(theme, l10n.application),
                for (final entry in categories.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _navigationItem(
                      theme,
                      colors,
                      entry.value.$2,
                      entry.value.$1,
                      !_profile && !_about && _category == entry.key && !mobile,
                      () => _select(false, category: entry.key),
                      ValueKey('settings-category-${entry.key.name}'),
                    ),
                  ),
                _navigationItem(
                  theme,
                  colors,
                  Symbols.info_rounded,
                  l10n.about,
                  _about && !mobile,
                  () => _select(true),
                  const ValueKey('settings-about'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(AppTheme theme, String title) => Padding(
    padding: const EdgeInsets.only(left: 10, bottom: 10),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: theme.textColorTertiary,
      ),
    ),
  );

  Widget _navigationItem(
    AppTheme theme,
    SettingsColors colors,
    IconData icon,
    String title,
    bool selected,
    VoidCallback onPressed,
    Key key,
  ) => MenuItemSurface(
    key: key,
    theme: theme,
    isSelected: selected,
    onPressed: onPressed,
    backgroundColor: colors.sidebar,
    hoverColor: colors.hover,
    borderRadius: BorderRadius.circular(7),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            fill: 1,
            size: 16,
            color: selected ? theme.textColorPrimary : theme.textColorTertiary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? theme.textColorPrimary
                    : theme.textColorTertiary,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _content(
    AppTheme theme,
    SettingsColors colors, {
    required bool mobile,
    required VoidCallback onBack,
  }) {
    final l10n = context.l10n;
    final titles = {
      _SettingsCategory.appearance: l10n.personalization,
      _SettingsCategory.language: l10n.languageAndRegion,
      _SettingsCategory.general: l10n.general,
    };
    final page = _profile
        ? ProfileContent(theme: theme)
        : _about
        ? AboutContent(theme: theme)
        : switch (_category) {
            _SettingsCategory.appearance => PersonalizationContent(
              theme: theme,
            ),
            _SettingsCategory.language => LanguageAndRegionContent(
              theme: theme,
            ),
            _SettingsCategory.general => GeneralSettingsContent(theme: theme),
          };
    final content = KeyedSubtree(
      key: ValueKey(
        _profile
            ? 'profile'
            : _about
            ? 'about'
            : _category.name,
      ),
      child: page,
    );
    return ColoredBox(
      color: colors.content,
      child: mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 18, 8),
                  child: Row(
                    children: [
                      AppTooltip(
                        message: l10n.back,
                        verticalOffset: 16,
                        child: _iconButton(
                          theme,
                          Symbols.arrow_back_rounded,
                          onBack,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _profile
                              ? l10n.profile
                              : _about
                              ? l10n.about
                              : titles[_category]!,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textColorPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: content),
              ],
            )
          : Stack(
              children: [
                Positioned.fill(child: content),
                Positioned(
                  top: 18,
                  right: 18,
                  child: AppTooltip(
                    message: l10n.closeSettings,
                    verticalOffset: 16,
                    child: _iconButton(theme, Symbols.close_rounded, _close),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _iconButton(AppTheme theme, IconData icon, VoidCallback onPressed) =>
      TitleBarIconButton(
        theme: theme,
        isFocused: true,
        icon: icon,
        size: 28,
        iconSize: 18,
        onPressed: onPressed,
      );
}
