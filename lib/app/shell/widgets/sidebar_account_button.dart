/*
 * @Description: 展示侧栏账号入口及等宽浮动菜单卡片，管理展开收起动画。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-03 23:41:53
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/provider.dart';
import '../../../core/widgets/menu_item_surface.dart';
import '../../../core/widgets/popup_menu_surface.dart';
import '../../../features/account/presentation/confirm_sign_out.dart';
import '../../../features/account/presentation/widgets/avatar.dart';
import '../../../features/account/state/provider.dart';
import '../../navigation/provider.dart';

class SidebarAccountButton extends StatefulWidget {
  const SidebarAccountButton({super.key});

  @override
  State<SidebarAccountButton> createState() => _SidebarAccountButtonState();
}

class _SidebarAccountButtonState extends State<SidebarAccountButton>
    with SingleTickerProviderStateMixin {
  final _menuController = MenuController();
  late final AnimationController _animation;
  late final CurvedAnimation _curve;
  VoidCallback? _hideOverlay;
  VoidCallback? _afterClose;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 150),
    )..addStatusListener(_onAnimationStatus);
    _curve = CurvedAnimation(
      parent: _animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _finishClose();
    }
  }

  void _finishClose() {
    final hide = _hideOverlay;
    final afterClose = _afterClose;
    _hideOverlay = null;
    _afterClose = null;
    hide?.call();
    if (mounted) afterClose?.call();
  }

  void _open(Offset? position, VoidCallback showOverlay) {
    // 快速反向点击时从当前动画进度继续，不让旧的关闭请求移除新菜单。
    _hideOverlay = null;
    _afterClose = null;
    showOverlay();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
  }

  void _close(VoidCallback hideOverlay) {
    _hideOverlay = hideOverlay;
    if (_animation.isDismissed) {
      _finishClose();
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 0;
    } else {
      _animation.reverse();
    }
  }

  @override
  void dispose() {
    _afterClose = null;
    _hideOverlay = null;
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }

  Widget _buildMenu(BuildContext context, RawMenuOverlayInfo info) {
    final theme = context.watch<ThemeProvider>().themeData;
    final account = context.watch<AccountProvider?>();
    return Positioned(
      left: info.anchorRect.left,
      bottom: info.overlaySize.height - info.anchorRect.top + 8,
      width: info.anchorRect.width,
      child: TapRegion(
        groupId: info.tapRegionGroupId,
        onTapOutside: (_) => _menuController.close(),
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _menuController.close();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) => IgnorePointer(
              ignoring: _animation.status == AnimationStatus.reverse,
              child: ExcludeFocus(
                excluding: _animation.status == AnimationStatus.reverse,
                child: child!,
              ),
            ),
            child: FadeTransition(
              key: const ValueKey('account-menu-fade'),
              opacity: _curve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.14),
                  end: Offset.zero,
                ).animate(_curve),
                child: ScaleTransition(
                  alignment: Alignment.bottomCenter,
                  scale: Tween<double>(begin: 0.96, end: 1).animate(_curve),
                  child: PopupMenuSurface(
                    key: const ValueKey('account-menu-card'),
                    theme: theme,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _menuItem(
                          theme: theme,
                          icon: Symbols.settings_rounded,
                          label: context.l10n.settings,
                          onPressed: () {
                            final navigation = context
                                .read<AppNavigationProvider>();
                            _afterClose = () =>
                                navigation.setPage(AppPage.settings);
                            _menuController.close();
                          },
                        ),
                        if (account?.user != null)
                          _menuItem(
                            key: const ValueKey('account-menu-sign-out'),
                            theme: theme,
                            icon: Symbols.logout_rounded,
                            label: context.l10n.githubSignOut,
                            onPressed: account!.busy
                                ? null
                                : () {
                                    // 菜单收起后使用入口的上下文，避免访问已移除的浮层。
                                    _afterClose = () => unawaited(
                                      confirmAccountSignOut(
                                        this.context,
                                        theme: theme,
                                      ),
                                    );
                                    _menuController.close();
                                  },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem({
    Key? key,
    required AppTheme theme,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) => MenuItemSurface(
    key: key,
    theme: theme,
    backgroundColor: PopupMenuSurface.backgroundColorFor(theme),
    hoverColor: theme.adaptiveColor(
      dark: theme.secondaryTextHoverColorAlt,
      light: theme.primaryTextHoverColor,
    ),
    borderRadius: BorderRadius.circular(6),
    onPressed: onPressed,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 30),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              fill: 1,
              color: theme.textColorSecondary,
              weight: 400,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: theme.textColorPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final user = context.watch<AccountProvider?>()?.user;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: RawMenuAnchor(
        controller: _menuController,
        onOpenRequested: _open,
        onCloseRequested: _close,
        overlayBuilder: _buildMenu,
        child: MenuItemSurface(
          key: const ValueKey('account-menu-trigger'),
          theme: theme,
          onPressed: () {
            if (_animation.status.isForwardOrCompleted) {
              _menuController.close();
            } else {
              _menuController.open();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                AccountAvatar(theme: theme, user: user, radius: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user?.displayName ?? context.l10n.profile,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textColorPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user == null
                            ? context.l10n.notSignedIn
                            : '@${user.login}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textColorTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Symbols.unfold_more,
                  size: 18,
                  color: theme.textColorTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
