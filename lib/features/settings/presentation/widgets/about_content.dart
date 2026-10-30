/*
 * @Description: 展示应用版本、版权等关于信息。
 * @Author: LILYGO_L
 * @Date: 2025-11-17 11:28:26
 * @LastEditTime: 2026-10-02 20:42:05
 * @License: GPL 3.0
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_info/app_update_provider.dart';
import '../../../../core/app_info/app_update_service.dart';
import '../../../../core/app_info/package_info_provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/window/provider.dart';
import '../../../../generated/l10n/app_localizations.dart';
import 'content_layout.dart';

class AboutContent extends StatefulWidget {
  const AboutContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<AboutContent> createState() => _AboutContentState();
}

class _AboutContentState extends State<AboutContent> {
  @override
  Widget build(BuildContext context) {
    final packageInfoProvider = context.watch<PackageInfoProvider>();
    final updates = context.watch<AppUpdateProvider>();
    final version = appReleaseVersion(
      packageInfoProvider.version,
    ).replaceFirst(RegExp(r'^[vV]'), '');

    final copyrightYear = DateTime.now().year;
    final theme = widget.theme;

    return SettingsContentLayout(
      theme: theme,
      title: context.l10n.about,
      description: context.l10n.aboutSettingsDescription,
      children: [
        SettingsField(
          theme: theme,
          title: context.l10n.version,
          description: version,
          trailing: _UpdateStatusButton(
            theme: theme,
            checking: updates.checking,
            available: updates.update != null,
            failed: updates.failure != null,
            onPressed: () {
              // 与标题栏下载按钮保持一致：优先展示后台检查结果，
              // 没有缓存结果时由公共提示框显示检查状态并完成检查。
              showDialog<void>(
                context: context,
                builder: (dialogContext) => AppUpdateDialog(
                  theme: theme,
                  currentVersion: version,
                  initialUpdate: updates.update,
                ),
              );
            },
          ),
          child: const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        SettingsField(
          theme: theme,
          title: context.l10n.copyright,
          description:
              '${packageInfoProvider.appName} $copyrightYear LILYGO Corporation',
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.theme,
    required this.currentVersion,
    this.initialUpdate,
    this.initialFailure,
  });

  final AppTheme theme;
  final String currentVersion;
  final AppUpdate? initialUpdate;
  final AppUpdateFailureKind? initialFailure;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  AppUpdate? _update;
  AppUpdateFailureKind? _failure;
  File? _installer;
  bool _checking = true;
  bool _downloading = false;
  http.Client? _downloadClient;
  bool _downloadCancelled = false;
  bool _installing = false;
  int _downloadedBytes = 0;

  @override
  void dispose() {
    _downloadClient?.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _update = widget.initialUpdate;
    _failure = widget.initialUpdate == null ? null : widget.initialFailure;
    _checking = widget.initialUpdate == null;
    if (_checking) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    } else if (widget.initialUpdate case final update?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadCachedInstaller(update);
      });
    }
  }

  Future<void> _loadCachedInstaller(AppUpdate update) async {
    final installer = await const AppUpdateService().findCachedInstaller(
      update,
    );
    if (mounted && _update?.version == update.version) {
      setState(() => _installer = installer);
    }
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() {
      _checking = true;
      _failure = null;
      _update = null;
    });
    try {
      const service = AppUpdateService();
      final update = await service.check(currentVersion: widget.currentVersion);
      final cachedInstaller = update == null
          ? null
          : await service.findCachedInstaller(update);
      if (!mounted) return;
      setState(() {
        _update = update;
        _installer = cachedInstaller;
        _checking = false;
      });
    } on AppUpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error.kind;
        _checking = false;
      });
    } catch (error, stackTrace) {
      debugPrint('App update check failed unexpectedly: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _failure = AppUpdateFailureKind.unknown;
        _checking = false;
      });
    }
  }

  Future<void> _download() async {
    final update = _update;
    if (update == null || _downloading) return;
    setState(() {
      _downloading = true;
      _downloadedBytes = 0;
      _failure = null;
    });
    final client = http.Client();
    _downloadCancelled = false;
    _downloadClient = client;
    try {
      final installer = await AppUpdateService(client: client)
          .downloadInstaller(
            update,
            isCancelled: () => _downloadCancelled || !mounted,
            onProgress: (received, _) {
              if (mounted && !_downloadCancelled) {
                setState(() => _downloadedBytes = received);
              }
            },
          );
      if (mounted && !_downloadCancelled) {
        setState(() => _installer = installer);
      }
    } on AppUpdateException catch (error) {
      if (mounted && !_downloadCancelled) setState(() => _failure = error.kind);
    } catch (_) {
      if (mounted && !_downloadCancelled) {
        setState(() => _failure = AppUpdateFailureKind.download);
      }
    } finally {
      client.close();
      if (identical(_downloadClient, client)) _downloadClient = null;
      if (mounted && !_downloadCancelled) setState(() => _downloading = false);
    }
  }

  Future<void> _install() async {
    final installer = _installer;
    if (installer == null || _installing) return;
    final windowProvider = context.read<WindowProvider>();
    setState(() => _installing = true);
    try {
      await const AppUpdateService().launchInstallerAfterExit(installer);
      await windowProvider.exit(discardUnsaved: true);
    } on AppUpdateException catch (error) {
      if (mounted) {
        setState(() {
          _installing = false;
          _failure = error.kind;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _installing = false;
          _failure = AppUpdateFailureKind.download;
        });
      }
    }
  }

  Future<void> _retry() async {
    if (_failure == AppUpdateFailureKind.installerLaunch &&
        _installer != null) {
      setState(() => _failure = null);
      await _install();
    } else if (_update != null) {
      await _download();
    } else {
      await _check();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final content = _checking
        ? Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.checkingForUpdates)),
            ],
          )
        : _downloading
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.downloadingAppUpdate),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _update!.sizeBytes > 0
                    ? (_downloadedBytes / _update!.sizeBytes).clamp(0, 1)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.appUpdateDownloadProgress(
                  (_downloadedBytes / 1024 / 1024).toStringAsFixed(1),
                  (_update!.sizeBytes / 1024 / 1024).toStringAsFixed(1),
                ),
                textAlign: TextAlign.end,
              ),
            ],
          )
        : _failure != null
        ? Text(
            _failureMessage(l10n),
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: widget.theme.textColorSecondary,
            ),
          )
        : _update == null
        ? Text(
            l10n.upToDate,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: widget.theme.textColorSecondary,
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.appVersion,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.theme.textColorSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(widget.currentVersion),
                  const SizedBox(width: 10),
                  const Text('→'),
                  const SizedBox(width: 10),
                  Text(_update!.version),
                ],
              ),
              if (_installer != null) ...[
                const SizedBox(height: 12),
                Text(l10n.appUpdateDownloaded),
              ],
            ],
          );
    return AppDialog(
      theme: widget.theme,
      title: l10n.appUpdateTitle,
      titleFontSize: 18,
      titleFontWeight: FontWeight.w600,
      content: SizedBox(width: 390, child: content),
      actions: [
        AppActionButton(
          theme: widget.theme,
          label: _downloading
              ? l10n.cancelDownload
              : _checking
              ? l10n.settingsCancel
              : l10n.close,
          settingBackground: true,
          onPressed: _installing
              ? null
              : () {
                  if (_downloading) {
                    _downloadCancelled = true;
                    _downloadClient?.close();
                  }
                  Navigator.of(context).pop();
                },
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          borderRadius: BorderRadius.circular(8),
        ),
        if (_failure != null)
          AppActionButton(
            theme: widget.theme,
            label: _failure == AppUpdateFailureKind.integrity
                ? l10n.redownloadUpdate
                : l10n.retry,
            primary: true,
            settingBackground: true,
            onPressed: _installing ? null : _retry,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            borderRadius: BorderRadius.circular(8),
          ),
        if (_update != null && _failure == null && !_checking && !_downloading)
          AppActionButton(
            theme: widget.theme,
            label: _installing
                ? l10n.preparingAppUpdate
                : _installer == null
                ? l10n.downloadAppUpdate
                : l10n.installAppUpdate,
            primary: true,
            settingBackground: true,
            onPressed: _downloading || _installing
                ? null
                : _installer == null
                ? _download
                : _install,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            borderRadius: BorderRadius.circular(8),
          ),
      ],
    );
  }

  String _failureMessage(AppLocalizations l10n) => switch (_failure!) {
    AppUpdateFailureKind.network => l10n.updateCheckNetworkFailure,
    AppUpdateFailureKind.timeout => l10n.updateCheckTimeout,
    AppUpdateFailureKind.manifestNotFound => l10n.updateCheckManifestMissing(
      switch (appReleaseChannel) {
        AppReleaseChannel.alpha => l10n.updateChannelAlpha,
        AppReleaseChannel.beta => l10n.updateChannelBeta,
        AppReleaseChannel.stable => l10n.updateChannelStable,
      },
    ),
    AppUpdateFailureKind.server => l10n.updateCheckServerFailure,
    AppUpdateFailureKind.http => l10n.updateCheckHttpFailure,
    AppUpdateFailureKind.invalidManifest => l10n.updateCheckInvalidManifest,
    AppUpdateFailureKind.download => l10n.appUpdateDownloadFailure,
    AppUpdateFailureKind.integrity => l10n.appUpdateIntegrityFailure,
    AppUpdateFailureKind.installerLaunch =>
      l10n.appUpdateInstallerLaunchFailure,
    AppUpdateFailureKind.unknown => l10n.updateCheckUnknownFailure,
  };
}

class _UpdateStatusButton extends StatelessWidget {
  const _UpdateStatusButton({
    required this.theme,
    required this.checking,
    required this.available,
    required this.failed,
    required this.onPressed,
  });

  final AppTheme theme;
  final bool checking;
  final bool available;
  final bool failed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.l10n.appUpdateTitle,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTooltip(
          verticalOffset: 16,
          message: checking
              ? context.l10n.checkingForUpdates
              : available
              ? context.l10n.appUpdateTitle
              : context.l10n.checkForAppUpdates,
          child: SizedBox(
            width: 28,
            height: 28,
            child: MenuItemSurface(
              theme: theme,
              onPressed: checking ? null : onPressed,
              borderRadius: BorderRadius.circular(14),
              backgroundColor: available
                  ? const Color(0xFF4B9AF5)
                  : Color.alphaBlend(
                      theme.secondary.withValues(alpha: .6),
                      theme.primary,
                    ),
              foregroundColor: available
                  ? Colors.white
                  : theme.textColorSecondary,
              hoverColor: available
                  ? const Color(0xFF367FCF)
                  : theme.secondaryTextHoverColor,
              child: Center(
                child: checking
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            available ? Colors.white : theme.textColorSecondary,
                          ),
                        ),
                      )
                    : Icon(
                        available
                            ? Symbols.download
                            : Symbols.refresh,
                        size: 18,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: available
                ? const Color(0xFFE8F1FF)
                : Color.alphaBlend(
                    theme.secondary.withValues(alpha: .6),
                    theme.primary,
                  ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            available
                ? context.l10n.otaNewVersion
                : context.l10n.checkForUpdates,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: available
                  ? const Color(0xFF2878D4)
                  : theme.textColorSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}
