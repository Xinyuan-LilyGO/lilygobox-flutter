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

import '../../../core/context_menu/right_click_menu.dart';
import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/provider.dart';
import '../../../core/widgets/menu_item_surface.dart';
import '../../../core/widgets/popup_menu_transition.dart';
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
  VoidCallback? _hideOverlay;
  VoidCallback? _afterClose;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: PopupMenuTransition.duration,
      reverseDuration: PopupMenuTransition.duration,
    )..addStatusListener(_onAnimationStatus);
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
            child: PopupMenuTransition(
              fadeKey: const ValueKey('account-menu-fade'),
              animation: _animation,
              alignment: Alignment.bottomLeft,
              child: RightClickMenuBuilder.buildMenuPanel(
                key: const ValueKey('account-menu-card'),
                theme: theme,
                width: info.anchorRect.width,
                menuItems: [
                  RightClickMenuItem(
                    icon: Symbols.settings_rounded,
                    label: context.l10n.settings,
                    onTap: () {
                      final navigation = context.read<AppNavigationProvider>();
                      _afterClose = () => navigation.setPage(AppPage.settings);
                      _menuController.close();
                    },
                  ),
                  if (account?.user != null)
                    RightClickMenuItem(
                      key: const ValueKey('account-menu-sign-out'),
                      icon: Symbols.logout_rounded,
                      label: context.l10n.githubSignOut,
                      isEnabled: !account!.busy,
                      onTap: () {
                        // 菜单收起后使用入口上下文，避免访问已移除的浮层。
                        _afterClose = () => unawaited(
                          confirmAccountSignOut(this.context, theme: theme),
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
    );
  }

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
