/*
 * @Description: 复用聊天的透明图标操作样式显示录音和朗读入口。
 */

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/definition.dart';
import '../../../core/theme/material_palette.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../core/widgets/title_bar_icon_button.dart';

class SpeechIconButton extends StatelessWidget {
  const SpeechIconButton({
    super.key,
    required this.theme,
    required this.surface,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.size = 25,
    this.iconSize = 16,
    this.iconColor,
  });

  final AppTheme theme;
  final Color surface;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => AppTooltip(
    message: label,
    child: Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      child: TitleBarIconButton(
        onPressed: onPressed,
        isFocused: true,
        theme: theme,
        icon: icon,
        size: size,
        iconSize: iconSize,
        backgroundColor: Colors.transparent,
        surfaceColor: surface,
        hoverColor: theme.interactionHoverColor(surface),
        iconColor: iconColor ?? theme.textColorSecondary,
      ),
    ),
  );
}
