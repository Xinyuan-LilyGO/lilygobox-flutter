/*
 * @Description: 校验并执行用户已确认的应用设置工具调用。
 */

import '../../../app/shell/state/provider.dart';
import '../../../core/l10n/language_provider.dart';
import '../../../core/layout/split_view_provider.dart';
import '../../../core/storage/preferences.dart';
import '../../../core/theme/provider.dart';

class SettingsToolHandler {
  const SettingsToolHandler({
    required this.preferences,
    required this.theme,
    required this.language,
    required this.shell,
    required this.splitView,
  });

  final AppPreferences preferences;
  final ThemeProvider theme;
  final LanguageProvider language;
  final AppShellProvider shell;
  final SplitViewProvider splitView;

  Future<String> execute(String name, Map<String, Object?> arguments) async {
    switch (name) {
      case 'set_theme':
        final value = arguments['theme'];
        if (value is! String || !['dark', 'light'].contains(value)) {
          throw const FormatException('Invalid theme');
        }
        theme.setTheme(ThemeType.values.byName(value));
      case 'set_language':
        final value = arguments['language'];
        if (value is! String || !['auto', 'en', 'zh'].contains(value)) {
          throw const FormatException('Invalid language');
        }
        language.changeLanguage(value);
      case 'set_font':
        final value = arguments['font'];
        if (value is! String ||
            !['system', 'inter', 'googleSansFlex', 'roboto'].contains(value)) {
          throw const FormatException('Invalid font');
        }
        theme.setFontChoice(value);
      case 'set_sidebar_visibility':
        final visible = arguments['visible'];
        if (visible is! bool) throw const FormatException('Invalid visibility');
        if (shell.isSidebarVisible != visible) shell.toggleSidebar();
      case 'set_sidebar_width':
        final width = _number(arguments['width'], 180, 360);
        shell.resizeSidebar(width, maxWidth: AppShellProvider.maxSidebarWidth);
      case 'set_content_split_width':
        splitView.updateSplitWidth(_number(arguments['width'], 100, 1200));
      case 'set_settings_sidebar_width':
        final width = _number(arguments['width'], 176, 300);
        preferences.setValue('settingsSidebarWidth', width);
      default:
        throw const FormatException('Unsupported setting action');
    }
    return 'Setting updated.';
  }

  double _number(Object? value, double min, double max) {
    if (value is! num || !value.isFinite || value < min || value > max) {
      throw const FormatException('Invalid numeric value');
    }
    return value.toDouble();
  }
}
