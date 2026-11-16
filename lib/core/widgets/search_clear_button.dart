import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/language_provider.dart';
import '../theme/definition.dart';
import 'app_tooltip.dart';
import 'menu_item_surface.dart';

/// 共用的紧凑搜索操作，采用应用标准的悬停过渡。
class SearchClearButton extends StatelessWidget {
  const SearchClearButton({
    super.key,
    required this.theme,
    required this.onPressed,
  });
  final AppTheme theme;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.homeClearSearch;
    return AppTooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        enabled: onPressed != null,
        child: MenuItemSurface(
          theme: theme,
          onPressed: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(
              Symbols.close,
              size: 14,
              color: theme.textColorSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
