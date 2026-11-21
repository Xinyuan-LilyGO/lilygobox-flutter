import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/widgets/menu_item_surface.dart';

class ModelBrandIcon extends StatelessWidget {
  const ModelBrandIcon({super.key, required this.model, this.menuHoverColor});

  final String? model;
  final Color? menuHoverColor;

  static final _deepSeek = RegExp(r'(?:^|[^a-z0-9])deepseek(?:$|[^a-z0-9])');
  static final _openAi = RegExp(
    r'(?:^|[^a-z0-9])(?:openai|gpt-\d+|o[1-4]|codex)(?:$|[^a-z0-9])',
  );

  @override
  Widget build(BuildContext context) {
    final id = model?.toLowerCase() ?? '';
    final brand = switch (id) {
      _ when _deepSeek.hasMatch(id) => 'deepseek',
      _ when _openAi.hasMatch(id) => 'openai',
      _ => null,
    };
    const size = 16.0;
    if (brand == null) return const Icon(Symbols.blur_on, size: size, fill: 1);
    final artworkSize = brand == 'openai' ? 14.0 : size;
    final color = switch (brand) {
      'deepseek'
          when menuHoverColor != null && MenuItemSurface.isHoveredOf(context) =>
        menuHoverColor,
      'deepseek' => null,
      _ =>
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
    };
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: SvgPicture.asset(
          'assets/images/model_brands/$brand.svg',
          key: ValueKey('ai-model-brand-$brand'),
          width: artworkSize,
          height: artworkSize,
          colorFilter: color == null
              ? null
              : ColorFilter.mode(color, BlendMode.srcIn),
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
