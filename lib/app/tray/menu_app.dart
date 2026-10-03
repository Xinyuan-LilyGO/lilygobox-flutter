/*
 * @Description: 托盘独立 Flutter 菜单窗口，复用右键菜单组件、实心图标及悬停渐变。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 01:10:00
 * @LastEditTime: 2026-10-04 01:57:39
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/context_menu/right_click_menu.dart';
import '../../core/theme/provider.dart';
import '../../core/widgets/menu_item_surface.dart';

class TrayMenuApp extends StatefulWidget {
  const TrayMenuApp({super.key});

  static const channel = MethodChannel('lilygobox/tray_menu');
  static const shadowPadding = 16.0;
  static final cardBounds = RRect.fromRectAndRadius(
    const Rect.fromLTWH(shadowPadding, shadowPadding, 150, 75),
    const Radius.circular(8),
  );

  @override
  State<TrayMenuApp> createState() => _TrayMenuAppState();
}

class _TrayMenuAppState extends State<TrayMenuApp> {
  final _theme = ThemeProvider();
  String _show = '';
  String _exit = '';
  bool _visible = false;
  bool _prepared = false;
  bool _reducedMotion = false;
  bool _activating = false;
  int _generation = 0;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    TrayMenuApp.channel.setMethodCallHandler((call) async {
      if (call.method == 'present' || call.method == 'prepare') {
        final presenting = call.method == 'present';
        final args = Map<String, Object?>.from(call.arguments as Map);
        final requestId = args['requestId'] as int? ?? _requestId + 1;
        if (requestId < _requestId) return;
        _requestId = requestId;
        _theme.setTheme(
          args['theme'] == 'light' ? ThemeType.light : ThemeType.dark,
        );
        setState(() {
          _show = args['show'] as String;
          _exit = args['exit'] as String;
          _reducedMotion = args['reduceMotion'] == true;
          _prepared = true;
          _visible = presenting;
          _activating = false;
          _generation++;
        });
        final generation = _generation;
        // 首帧完成后再显示原生窗口，避免首次展开闪白或显示旧的语言。
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && presenting && _visible && generation == _generation) {
          await TrayMenuApp.channel.invokeMethod<void>('painted', {
            'requestId': requestId,
            'fadeDurationMs': MenuItemSurface.animationDuration.inMilliseconds,
            'reduceMotion': _reducedMotion,
          });
        }
      } else if (call.method == 'dismiss') {
        final args = call.arguments as Map?;
        final requestId = args?['requestId'] as int? ?? _requestId + 1;
        if (requestId < _requestId) return;
        _requestId = requestId;
        setState(() {
          _visible = false;
          _generation++;
        });
      }
    });
    unawaited(TrayMenuApp.channel.invokeMethod<void>('ready'));
  }

  Future<void> _activate(String action) async {
    if (_activating || !_visible) return;
    _activating = true;
    final generation = _generation;
    final requestId = _requestId;
    // 短暂保留点击墨水反馈，再交给主窗口执行操作。
    if (!_reducedMotion) {
      await Future<void>.delayed(MenuItemSurface.animationDuration);
    }
    if (mounted && _visible && _generation == generation) {
      await TrayMenuApp.channel.invokeMethod<void>(action, {
        'requestId': requestId,
      });
    }
    if (_generation == generation) _activating = false;
  }

  void _dismiss() {
    if (!_visible) return;
    setState(() {
      _visible = false;
      _generation++;
    });
    unawaited(
      TrayMenuApp.channel.invokeMethod<void>('dismiss', {
        'requestId': _requestId,
      }),
    );
  }

  @override
  void dispose() {
    TrayMenuApp.channel.setMethodCallHandler(null);
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: _reducedMotion,
        textScaler: TextScaler.noScaling,
      ),
      child: child!,
    ),
    home: Scaffold(
      backgroundColor: Colors.transparent,
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          // 透明阴影也属于窗口，点击这里或圆角外侧应立即关闭菜单。
          if (!TrayMenuApp.cardBounds.contains(event.localPosition)) _dismiss();
        },
        child: SizedBox.expand(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
            },
            child: Focus(
              autofocus: true,
              // 隐藏时保留已排版的菜单，预热字体与图标，原生窗口负责可见性。
              child: _prepared
                  ? KeyedSubtree(
                      key: ValueKey(_generation),
                      // 整张卡片由原生宿主淡入，避免这里只淡入文字而背景直接出现。
                      child: Padding(
                        padding: const EdgeInsets.all(
                          TrayMenuApp.shadowPadding,
                        ),
                        child: RightClickMenuBuilder.buildMenuPanel(
                          theme: _theme.themeData,
                          backgroundColor: _theme.themeData.primary,
                          menuItems: [
                            RightClickMenuItem(
                              label: _show,
                              icon: Symbols.open_in_new_rounded,
                              showDivider: true,
                              onTap: () => unawaited(_activate('show')),
                            ),
                            RightClickMenuItem(
                              label: _exit,
                              icon: Symbols.power_settings_new_rounded,
                              onTap: () => unawaited(_activate('exit')),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
}
