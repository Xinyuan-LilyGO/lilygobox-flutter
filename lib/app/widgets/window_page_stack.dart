/*
 * @Description: 根据导航状态切换主窗口外壳、设置及设备设置页面。
 */

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/update_scope.dart';
import '../../features/devices/presentation/catalog.dart';
import '../../features/settings/presentation/pages/page.dart';
import '../navigation/provider.dart';
import '../shell/pages/page.dart';

/// 设置覆盖主外壳，关闭后原页面继续使用同一个 State。
class WindowPageStack extends StatefulWidget {
  const WindowPageStack({super.key});

  @override
  State<WindowPageStack> createState() => _WindowPageStackState();
}

class _WindowPageStackState extends State<WindowPageStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  // 与设置页共用进度，恢复旧版底层页面的渐隐和返回时的渐显。
  late final Animation<double> _backgroundOpacity = ReverseAnimation(_curve);
  late final Animation<Offset> _overlayPosition = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_curve);
  final _backgroundSnapshot = SnapshotController();
  final _overlaySnapshot = SnapshotController();

  @override
  void initState() {
    super.initState();
    _animation.addStatusListener(_updateBackgroundSnapshot);
  }

  void _updateBackgroundSnapshot(AnimationStatus status) {
    // 被覆盖的外壳已暂停且不能接收输入，短暂过渡期间
    // 仅冻结绘制结果，保留其现有 State。
    final transitioning =
        !kIsWeb &&
        (status == AnimationStatus.forward ||
            status == AnimationStatus.reverse);
    _backgroundSnapshot.allowSnapshotting = transitioning;
    _overlaySnapshot.allowSnapshotting = transitioning;
  }

  void _resumeOverlayPainting() {
    // 过渡期间的操作必须立即反映到界面，不能等待
    // 临时过渡纹理释放。仅悬停时继续保留快照，
    // 鼠标移动不应恢复整个页面的绘制。
    _overlaySnapshot.allowSnapshotting = false;
  }

  AppPage? _overlay;
  String? _deviceName;

  @override
  Widget build(BuildContext context) {
    final navigation = context.watch<AppNavigationProvider>();
    final current = navigation.currentPage;
    final covered =
        current == AppPage.settings || current == AppPage.deviceSettings;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (covered) {
      if (_overlay != current || _deviceName != navigation.settingsDeviceName) {
        _overlaySnapshot.clear();
      }
      _overlay = current;
      _deviceName = navigation.settingsDeviceName;
      if (reducedMotion) {
        _animation.value = 1;
      } else if (_animation.status != AnimationStatus.forward &&
          !_animation.isCompleted) {
        _animation.forward();
      }
    } else if (reducedMotion) {
      _animation.value = 0;
    } else if (_animation.status != AnimationStatus.reverse &&
        !_animation.isDismissed) {
      _animation.reverse();
    }

    return Expanded(
      child: AnimatedBuilder(
        animation: _animation,
        // 页面构建和绘制与过渡进度相互独立。
        // 缓存图层可以移动和淡入淡出，无需重绘整个页面。
        child: _overlay == null
            ? null
            : RepaintBoundary(
                child: _overlay == AppPage.settings
                    ? const SettingsPage()
                    : DevicePresentationCatalog.settingsPageFor(
                        _deviceName!,
                        onClose: navigation.closeSettings,
                      ),
              ),
        builder: (context, overlayPage) {
          final overlayVisible = covered || !_animation.isDismissed;
          return Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: covered && _animation.isCompleted,
                child: TickerMode(
                  enabled: !overlayVisible,
                  child: ExcludeFocus(
                    excluding: overlayVisible,
                    child: ExcludeSemantics(
                      excluding: overlayVisible,
                      child: IgnorePointer(
                        ignoring: overlayVisible,
                        child: FadeTransition(
                          opacity: _backgroundOpacity,
                          child: SnapshotWidget(
                            controller: _backgroundSnapshot,
                            mode: SnapshotMode.permissive,
                            autoresize: true,
                            child: ThemeUpdateScope(
                              active: !covered,
                              child: const RepaintBoundary(child: AppShell()),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (overlayVisible)
                ExcludeFocus(
                  excluding: !covered,
                  child: IgnorePointer(
                    ignoring: !covered,
                    child: SlideTransition(
                      position: _overlayPosition,
                      child: FadeTransition(
                        opacity: _curve,
                        child: Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onKeyEvent: (_, _) {
                            _resumeOverlayPainting();
                            return KeyEventResult.ignored;
                          },
                          child: Listener(
                            onPointerDown: (_) => _resumeOverlayPainting(),
                            onPointerSignal: (_) => _resumeOverlayPainting(),
                            child: SnapshotWidget(
                              controller: _overlaySnapshot,
                              mode: SnapshotMode.permissive,
                              autoresize: true,
                              child: overlayPage,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _animation.removeStatusListener(_updateBackgroundSnapshot);
    _backgroundSnapshot.dispose();
    _overlaySnapshot.dispose();
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }
}
