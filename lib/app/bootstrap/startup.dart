import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/storage/preferences.dart';
import '../../core/theme/material_palette.dart';
import '../../core/theme/provider.dart';
import '../lilygobox_app.dart';
import '../providers.dart';
import '../widgets/window_frame.dart';

/// 先绘制启动画面，再恢复本地配置；联网服务继续由主页在后台启动。
class AppStartup extends StatefulWidget {
  const AppStartup({
    super.key,
    this.loadPreferences = AppPreferences.load,
    this.applicationBuilder = _buildApplication,
    this.preferences,
  });

  final Future<AppPreferences> Function() loadPreferences;
  final AppPreferences? preferences;
  final Widget Function(AppPreferences) applicationBuilder;

  static Widget _buildApplication(AppPreferences preferences) =>
      AppProviders(preferences: preferences, child: const LilygoBoxApp());

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup>
    with SingleTickerProviderStateMixin {
  AppPreferences? _preferences;
  Timer? _minimumDisplayTimer;
  bool _minimumDisplayElapsed = false;
  bool _applicationPainted = false;
  bool _showStartup = true;
  bool _fading = false;
  late final AnimationController _fade =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _showStartup = false);
        }
      });
  late final Animation<double> _opacity = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic));

  void _tryFade() {
    if (!mounted || _fading || !_minimumDisplayElapsed || !_applicationPainted) {
      return;
    }
    _fading = true;
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      _fade.value = 1;
    } else {
      _fade.forward();
    }
  }

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _minimumDisplayTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        _minimumDisplayElapsed = true;
        _tryFade();
      });
      if (_preferences == null) _initialize();
    });
  }

  @override
  void dispose() {
    _minimumDisplayTimer?.cancel();
    _fade.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final preferences = await widget.loadPreferences();
    if (!mounted) {
      preferences.dispose();
      return;
    }
    setState(() => _preferences = preferences);
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    if (preferences != null && !_applicationPainted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applicationPainted = true;
        _tryFade();
      });
    }
    final platform = MediaQueryData.fromView(View.of(context));
    return MediaQuery(
      data: platform,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (preferences != null)
              IgnorePointer(
                ignoring: _showStartup,
                child: ExcludeSemantics(
                  excluding: _showStartup,
                  child: KeyedSubtree(
                    key: const ValueKey('application'),
                    child: widget.applicationBuilder(preferences),
                  ),
                ),
              ),
            if (_showStartup)
              FadeTransition(
                opacity: _opacity,
                child: StartupScreen(
                  key: const ValueKey('startup'),
                  themeType:
                      preferences?.stringValue('theme', 'dark') == 'light'
                      ? ThemeType.light
                      : ThemeType.dark,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 简洁的启动标识，使用应用保存的主题，不展示虚构进度。
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key, this.themeType = ThemeType.dark});

  final ThemeType themeType;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> with WindowListener {
  bool _maximized = false;

  bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    if (_desktop) {
      windowManager.addListener(this);
      unawaited(_readWindowState());
    }
  }

  Future<void> _readWindowState() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = maximized);
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void dispose() {
    if (_desktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MaterialPalette.create(widget.themeType);
    return AppWindowFrame(
      theme: theme,
      isMaximized: _maximized,
      showShadow: false,
      child: DragToMoveArea(
        child: Center(
          child: Semantics(
            label: 'LilygoBox',
            image: true,
            child: SvgPicture.asset(
              'assets/images/branding/lilygobox_logo.svg',
              width: 64,
              height: 64,
              excludeFromSemantics: true,
              colorFilter: ColorFilter.mode(
                theme.textColorPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
