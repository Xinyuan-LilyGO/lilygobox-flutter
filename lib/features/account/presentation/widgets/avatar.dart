/*
 * @Description: 统一账号头像展示，加载失败时回退到本地人物图标。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 14:22:16
 * @LastEditTime: 2026-10-03 14:22:16
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/theme/definition.dart';
import '../../domain/models.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.theme,
    this.user,
    this.radius = 24,
  });
  final AppTheme theme;
  final GithubUser? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Symbols.person_rounded,
      fill: 1,
      size: radius * 1.3,
      color: theme.textColorSecondary,
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: ColoredBox(
          color: theme.sidebarIconBackgroundColor,
          child: user?.avatarUrl == null
              ? fallback
              : Image.network(
                  user!.avatarUrl.toString(),
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, error, stack) => fallback,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : fallback,
                ),
        ),
      ),
    );
  }
}
