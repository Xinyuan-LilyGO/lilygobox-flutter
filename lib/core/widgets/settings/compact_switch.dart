import 'package:material_ui/material_ui.dart';

import '../../theme/definition.dart';
import '../../theme/material_palette.dart';

class CompactSettingSwitch extends StatelessWidget {
  const CompactSettingSwitch({
    super.key,
    required this.controlKey,
    required this.theme,
    required this.surface,
    required this.value,
    required this.onChanged,
  });

  final Key controlKey;
  final AppTheme theme;
  final Color surface;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 28,
    child: FittedBox(
      child: Switch(
        key: controlKey,
        value: value,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        activeTrackColor: theme.basePrimary,
        inactiveTrackColor: theme.selectControlColorForSurface(surface),
        activeThumbColor: theme.materialColors.onPrimary,
        inactiveThumbColor: theme.materialColors.onPrimary,
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        onChanged: onChanged,
      ),
    ),
  );
}
