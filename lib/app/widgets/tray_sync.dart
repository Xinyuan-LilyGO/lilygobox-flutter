/*
 * @Description: 将当前主题与本地化菜单文字同步到系统托盘。
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/language_provider.dart';
import '../../core/theme/provider.dart';
import '../../core/window/provider.dart';

class TraySync extends StatelessWidget {
  const TraySync({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final l10n = context.l10n;
    unawaited(
      context.read<WindowProvider>().configureTray({
        'show': l10n.trayShowWindow,
        'exit': l10n.trayExit,
        'theme': theme.type.name,
        'reduceMotion': MediaQuery.disableAnimationsOf(context),
      }),
    );
    return child;
  }
}
