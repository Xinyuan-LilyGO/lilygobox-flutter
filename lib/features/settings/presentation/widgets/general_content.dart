/*
 * @Description: 提供通用设置分类的页面布局。
 * @Author: LILYGO_L
 * @Date: 2026-05-24 23:22:38
 * @LastEditTime: 2026-10-03 23:41:53
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/shell/state/provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/layout/split_view_provider.dart';
import '../../../../core/storage/preferences.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../data/application_configuration.dart';
import '../../data/application_configuration_file_service.dart';
import 'content_layout.dart';
import 'split_view.dart';

class GeneralSettingsContent extends StatelessWidget {
  const GeneralSettingsContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return SettingsContentLayout(
      theme: theme,
      title: context.l10n.general,
      description: context.l10n.generalSettingsDescription,
      children: [
        SettingsField(
          theme: theme,
          title: context.l10n.configurationTitle,
          description: context.l10n.configurationDescription,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppActionButton.settings(
                key: const ValueKey('export-configuration'),
                theme: theme,
                label: context.l10n.configurationExport,
                onPressed: () => _exportConfiguration(context),
              ),
              AppActionButton.settings(
                key: const ValueKey('import-configuration'),
                theme: theme,
                label: context.l10n.configurationImport,
                onPressed: () => _importConfiguration(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SettingsField(
          theme: theme,
          title: context.l10n.restoreDefaults,
          description: context.l10n.restoreDefaultsDescription,
          child: AppActionButton.settings(
            key: const ValueKey('restore-defaults'),
            theme: theme,
            label: context.l10n.restoreDefaults,
            onPressed: () => _confirmReset(context),
          ),
        ),
      ],
    );
  }

  Future<void> _exportConfiguration(BuildContext context) async {
    final l10n = context.l10n;
    try {
      final exported =
          await ApplicationConfigurationFileService.exportConfiguration(
            _captureConfiguration(context),
            fileTypeLabel: l10n.configurationFileType,
          );
      if (!context.mounted || !exported) return;
      _showMessage(context, l10n.configurationExportSucceeded);
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, l10n.configurationExportFailed);
    }
  }

  Future<void> _importConfiguration(BuildContext context) async {
    final l10n = context.l10n;
    ApplicationConfiguration configuration;
    try {
      final selected =
          await ApplicationConfigurationFileService.importConfiguration(
            fileTypeLabel: l10n.configurationFileType,
          );
      if (selected == null) return;
      if (!context.mounted) return;
      configuration = selected;
    } on FormatException {
      if (!context.mounted) return;
      _showMessage(context, l10n.configurationImportInvalid);
      return;
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, l10n.configurationImportFailed);
      return;
    }

    final confirmed = await showAppConfirmation(
      context: context,
      theme: theme,
      actionKey: 'import-configuration',
      title: l10n.configurationImportConfirmTitle,
      description: l10n.configurationImportConfirmDescription,
      confirmLabel: l10n.configurationImport,
    );
    if (!confirmed || !context.mounted) return;

    final previous = _captureConfiguration(context);
    _applyConfiguration(context, configuration);
    final preferences = context.read<AppPreferences?>();
    if (preferences != null && !await preferences.flush()) {
      if (context.mounted) {
        _applyConfiguration(context, previous);
        await preferences.flush();
      }
      if (!context.mounted) return;
      _showMessage(context, l10n.configurationImportFailed);
      return;
    }
    if (!context.mounted) return;
    _showMessage(context, l10n.configurationImportSucceeded);
  }

  ApplicationConfiguration _captureConfiguration(BuildContext context) {
    final preferences = context.read<AppPreferences?>();
    final themeProvider = context.read<ThemeProvider>();
    final shell = context.read<AppShellProvider>();
    return ApplicationConfiguration(
      theme: themeProvider.currentTheme.name,
      language: context.read<LanguageProvider>().languageCode,
      font: themeProvider.fontChoice,
      sidebarWidth: shell.sidebarWidth,
      sidebarVisible: shell.isSidebarVisible,
      splitWidth: context.read<SplitViewProvider>().splitWidth,
      settingsSidebarWidth:
          preferences?.doubleValue('settingsSidebarWidth', 176, 176, 300) ??
          176,
    );
  }

  void _applyConfiguration(
    BuildContext context,
    ApplicationConfiguration configuration,
  ) {
    final themeProvider = context.read<ThemeProvider>();
    themeProvider.setTheme(ThemeType.values.byName(configuration.theme));
    themeProvider.setFontChoice(configuration.font);
    context.read<LanguageProvider>().changeLanguage(configuration.language);

    final shell = context.read<AppShellProvider>();
    shell.resizeSidebar(
      configuration.sidebarWidth,
      maxWidth: configuration.sidebarWidth,
    );
    if (shell.isSidebarVisible != configuration.sidebarVisible) {
      shell.toggleSidebar();
    }
    context.read<SplitViewProvider>().updateSplitWidth(
      configuration.splitWidth,
    );
    context.read<AppPreferences?>()?.setValue(
      'settingsSidebarWidth',
      configuration.settingsSidebarWidth,
    );
  }

  void _showMessage(BuildContext context, String message) {
    showAppNotice(ScaffoldMessenger.of(context), message);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirmation(
      context: context,
      theme: theme,
      actionKey: 'restore-defaults',
      title: l10n.restoreDefaultsConfirmTitle,
      description: l10n.restoreDefaultsConfirmDescription,
      confirmLabel: l10n.restoreDefaults,
    );
    if (!confirmed || !context.mounted) return;
    // 仅重置明确的应用偏好，不清空设备列表或其他持久化数据。
    context.read<ThemeProvider>().setTheme(ThemeType.dark);
    context.read<LanguageProvider>().changeLanguage('en');
    context.read<AppShellProvider?>()?.resetLayout();
    context.read<SplitViewProvider?>()?.resetSplitWidth();
    context.read<AppPreferences?>()?.setValue(
      'settingsSidebarWidth',
      SettingsSplitView.minSidebarWidth,
    );
  }
}
