/*
 * @Description: 保留隐藏页面状态，暂停向其分发主题过渡帧并在显示时同步当前配色。
 */

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'provider.dart';

/// 避免隐藏但保留的页面在主题动画的每一帧都重建。
///
/// 共享 provider 仍是状态来源，操作仍会传递给它。
/// 仅延后继承通知和 Material 主题帧的更新；保持
/// 相同的子控件和 provider 类型，可保留页面 State 和滚动位置。
class ThemeUpdateScope extends StatefulWidget {
  const ThemeUpdateScope({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<ThemeUpdateScope> createState() => _ThemeUpdateScopeState();
}

class _ThemeUpdateScopeState extends State<ThemeUpdateScope> {
  CapturedThemes? _pausedThemes;
  bool _notifyTheme = false;
  ({ThemeProvider source, AppTheme palette, ThemeType type, String fontChoice})?
  _publishedTheme;

  @override
  Widget build(BuildContext context) {
    final source = context.watch<ThemeProvider?>();
    final snapshot = source == null
        ? null
        : (
            source: source,
            palette: source.themeData,
            type: source.currentTheme,
            fontChoice: source.fontChoice,
          );
    _notifyTheme = widget.active && snapshot != _publishedTheme;
    // 同时捕获继承的 Material、文字、图标及选区主题。
    // 否则这些依赖仍可能重建隐藏页面中的 Text，
    // 即使该页面的 ThemeProvider 通知已暂停。
    Theme.of(context);
    DefaultTextStyle.of(context);
    IconTheme.of(context);
    DefaultSelectionStyle.of(context);
    if (widget.active) {
      _pausedThemes = null;
      _publishedTheme = snapshot;
    }
    final themes = widget.active
        ? InheritedTheme.capture(from: context, to: null)
        : _pausedThemes ??= InheritedTheme.capture(from: context, to: null);
    return themes.wrap(
      source == null
          ? widget.child
          : InheritedProvider<ThemeProvider>.value(
              value: source,
              // 上层作用域已经监听，避免在这里再次订阅
              // ChangeNotifier，以免绕过暂停机制。
              updateShouldNotify: (_, _) => _notifyTheme,
              child: widget.child,
            ),
    );
  }
}
