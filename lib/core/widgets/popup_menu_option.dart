import 'dart:math' as math;

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/definition.dart';
import '../theme/material_palette.dart';
import 'dialog_style.dart';
import 'menu_item_surface.dart';

const popupMenuOptionSpacing = 6.0;
const popupMenuOptionsTrailingInset = 20.0;

Widget buildPopupMenuOption({
  required Key key,
  required AppTheme theme,
  required Widget leading,
  required String title,
  required String description,
  required bool selected,
  required VoidCallback onPressed,
  Color? backgroundColor,
  bool next = false,
  bool uniformHeight = false,
}) => MenuItemSurface(
  key: key,
  theme: theme,
  isSelected: selected,
  disableWhenSelected: false,
  backgroundColor: backgroundColor ?? theme.popupSurfaceColor,
  selectedColor: theme.primaryTextHoverColor,
  hoverColor: theme.basePrimary,
  foregroundColor: selected
      ? theme.type == ThemeType.light
            ? Colors.black
            : theme.materialColors.onPrimary
      : theme.textColorSecondary,
  hoverForegroundColor: theme.materialColors.onPrimary,
  borderRadius: BorderRadius.circular(6),
  onPressed: onPressed,
  child: Builder(
    builder: (context) {
      final normal = theme.textColorSecondary;
      final foreground = DefaultTextStyle.of(context).style.color ?? normal;
      final highlighted = theme.materialColors.onPrimary;
      double distance(Color first, Color second) =>
          math.pow(first.r - second.r, 2).toDouble() +
          math.pow(first.g - second.g, 2).toDouble() +
          math.pow(first.b - second.b, 2).toDouble();
      final total = distance(normal, highlighted);
      final progress = total == 0
          ? 0.0
          : math.sqrt(distance(normal, foreground) / total).clamp(0.0, 1.0);
      final titleStyle = AppDialogStyle.fieldTitleStyle(theme)
          .copyWith(color: foreground);
      final descriptionStyle = AppDialogStyle.descriptionStyle(theme).copyWith(
        color: Color.lerp(theme.textColorTertiary, highlighted, progress),
      );
      StrutStyle? strut(TextStyle style) => uniformHeight
          ? StrutStyle.fromTextStyle(
              DefaultTextStyle.of(context).style.merge(style),
              height: 1.4,
              forceStrutHeight: true,
            )
          : null;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                    strutStyle: strut(titleStyle),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: descriptionStyle,
                    strutStyle: strut(descriptionStyle),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 17,
              child: selected
                  ? const Icon(Symbols.check_rounded, size: 17)
                  : null,
            ),
            if (next) ...[
              const SizedBox(width: 4),
              const SizedBox(
                width: 17,
                child: Icon(Symbols.chevron_right_rounded, size: 16),
              ),
            ],
          ],
        ),
      );
    },
  ),
);
