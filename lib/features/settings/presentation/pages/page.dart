/*
 * @Description: 构建应用设置页面的背景与设置分栏内容。
 */

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/provider.dart';
import '../widgets/split_view.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context).themeData;

    return ColoredBox(
      color: theme.primary,
      child: ClipRRect(
        // 设置页覆盖在主窗口内容区内，左上角要与其他页面保持同样的圆角。
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: const SettingsSplitView(),
      ),
    );
  }
}
