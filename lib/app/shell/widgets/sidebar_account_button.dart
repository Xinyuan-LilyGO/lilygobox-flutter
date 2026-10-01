/*
 * @Description: 展示侧栏底部账号入口和未登录状态，保留交互反馈。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/provider.dart';
import '../../../core/widgets/menu_item_surface.dart';

class SidebarAccountButton extends StatelessWidget {
  const SidebarAccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: MenuItemSurface(
        theme: theme,
        // 账号功能暂未接入，仅保留共用按钮的交互反馈。
        onPressed: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: theme.sidebarIconBackgroundColor,
                child: Icon(
                  Symbols.person,
                  size: 22,
                  color: theme.sidebarIconColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.accountSettings,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textColorPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.notSignedIn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textColorTertiary,
                        fontSize: 11,
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
    );
  }
}
