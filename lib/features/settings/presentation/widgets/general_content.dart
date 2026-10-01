/*
 * @Description: 提供通用设置分类的页面布局。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/settings/widgets.dart';

class GeneralSettingsContent extends StatelessWidget {
  const GeneralSettingsContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return SettingsPageLayout(
      theme: theme,
      title: context.l10n.general,
      children: const [],
    );
  }
}
