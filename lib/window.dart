/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-10-27 09:07:11
 * @LastEditTime: 2025-10-27 17:13:24
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';

import 'theme.dart';
import 'language.dart';
import 'l10n/app_localizations.dart';
import 'home_page.dart';

// MainApp 现在可以是 StatelessWidget，因为状态已经移到 Provider 中
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<ThemeProvider, WindowProvider, LanguageProvider>(
      builder:
          (context, themeProvider, windowProvider, languageProvider, child) {
            final theme = themeProvider.themeData;
            final isMaximized = windowProvider.isMaximized;
            final locale = languageProvider.locale;

            return MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                backgroundColor: Colors.transparent,
                // 添加 Builder
                body: Builder(
                  // 使用新的 languageContext
                  builder: (BuildContext languageContext) {
                    return Container(
                      margin: isMaximized
                          ? EdgeInsets.zero
                          : const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.primary,
                        borderRadius: isMaximized
                            ? BorderRadius.zero
                            : BorderRadius.circular(10),
                        boxShadow: isMaximized ? [] : _buildBoxShadow(),
                      ),
                      child: ClipRRect(
                        borderRadius: isMaximized
                            ? BorderRadius.zero
                            : BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Column(
                              children: [
                                // 将 context 替换为 languageContext
                                _buildAppTitleBar(languageContext),
                                _buildCurrentPage(languageContext),
                              ],
                            ),
                            _buildAppTitleBarControlsResizeArea(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
    );
  }

  // 构建窗口控制按钮组件
  Widget _buildAppTitleBarControls(BuildContext context) {
    final windowProvider = Provider.of<WindowProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    final isFocused = windowProvider.isFocused;
    final isMaximized = windowProvider.isMaximized;

    // 根据焦点状态确定图标颜色
    final Color iconColor = isFocused
        ? theme.iconColor
        : theme.inactiveIconColor;

    return Row(
      children: [
        // 最小化按钮
        AppTitleBarControlsButtonTemplate(
          icon: Symbols.remove_rounded,
          onPressed: isFocused ? () => windowProvider.minimize() : null,
          hoverColor: isFocused
              ? Colors.grey.withValues(alpha: 0.2)
              : Colors.transparent,
          iconColor: iconColor,
        ),
        // 最大化/还原按钮
        AppTitleBarControlsButtonTemplate(
          icon: isMaximized ? Symbols.filter_none : Symbols.crop_square_rounded,
          onPressed: isFocused
              ? () => windowProvider.handleMaximizeRestore()
              : null,
          hoverColor: isFocused
              ? Colors.grey.withValues(alpha: 0.2)
              : Colors.transparent,
          iconSize: isMaximized ? 13.5 : 14,
          iconWeight: 510.0,
          rotateAngle: isMaximized ? 180 : 0,
          iconColor: iconColor,
        ),
        // 关闭按钮
        AppTitleBarControlsButtonTemplate(
          icon: Symbols.close_rounded,
          onPressed: isFocused ? () => windowProvider.close() : null,
          hoverColor: isFocused ? Colors.red.shade600 : Colors.transparent,
          iconColor: iconColor,
        ),
      ],
    );
  }

  // 构建自定义标题栏
  Widget _buildAppTitleBar(BuildContext context) {
    final windowProvider = Provider.of<WindowProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    final isFocused = windowProvider.isFocused;

    // 标题栏高度
    const double titleBarHeight = 30.0;

    return Container(
      height: titleBarHeight,
      color: theme.primary,
      child: Row(
        children: [
          // 填充剩余空间
          Expanded(
            child: DragToMoveArea(
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  context.l10n.appTitle, // 使用本地化文本
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: isFocused
                        ? theme.appTitleTextColor
                        : theme.inactiveTextColor,
                  ),
                ),
              ),
            ),
          ),
          // 右侧窗口控制按钮
          _buildAppTitleBarControls(context),
        ],
      ),
    );
  }

  // 构建窗口边框调整区域
  Widget _buildAppTitleBarControlsResizeArea() {
    const double resizeAreaSize = 5.0;

    return Consumer<WindowProvider>(
      builder: (context, windowProvider, child) {
        final isMaximized = windowProvider.isMaximized;

        // 如果窗口最大化，隐藏调整区域
        if (isMaximized) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            // 边缘调整区域
            _buildResizeArea(
              left: 0,
              top: 0,
              bottom: 0,
              width: resizeAreaSize,
              cursor: SystemMouseCursors.resizeLeftRight,
              edge: ResizeEdge.left,
            ),
            _buildResizeArea(
              right: 0,
              top: 0,
              bottom: 0,
              width: resizeAreaSize,
              cursor: SystemMouseCursors.resizeLeftRight,
              edge: ResizeEdge.right,
            ),
            _buildResizeArea(
              left: 0,
              top: 0,
              right: 0,
              height: resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpDown,
              edge: ResizeEdge.top,
            ),
            _buildResizeArea(
              left: 0,
              bottom: 0,
              right: 0,
              height: resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpDown,
              edge: ResizeEdge.bottom,
            ),
            // 角落调整区域
            _buildResizeArea(
              left: 0,
              top: 0,
              width: resizeAreaSize,
              height: resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpLeftDownRight,
              edge: ResizeEdge.topLeft,
            ),
            _buildResizeArea(
              right: 0,
              top: 0,
              width: resizeAreaSize,
              height: resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpRightDownLeft,
              edge: ResizeEdge.topRight,
            ),
            _buildResizeArea(
              left: 0,
              bottom: 0,
              width: resizeAreaSize,
              height: resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpRightDownLeft,
              edge: ResizeEdge.bottomLeft,
            ),
            _buildResizeArea(
              right: 0,
              bottom: 0,
              width: resizeAreaSize,
              height: resizeAreaSize,
              cursor: SystemMouseCursors.resizeUpLeftDownRight,
              edge: ResizeEdge.bottomRight,
            ),
          ],
        );
      },
    );
  }

  // 可重用的边缘调整组件
  Widget _buildResizeArea({
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
    required MouseCursor cursor,
    required ResizeEdge edge,
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startResizing(edge),
          child: Container(
            width: width,
            height: height,
            color: Colors.transparent,
          ),
        ),
      ),
    );
  }

  // 专门的柔和阴影构建方法
  List<BoxShadow> _buildBoxShadow() {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.3), // 阴影颜色和透明度：黑色，50%透明度
        blurRadius: 5, // 模糊半径：阴影边缘模糊程度，值越大越模糊
        spreadRadius: -1, // 扩散半径：负值让阴影向内收缩，消除硬边
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.3),
        blurRadius: 4,
        spreadRadius: -2,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 3,
        spreadRadius: -3,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 2,
        spreadRadius: -4,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.1),
        blurRadius: 1,
        spreadRadius: -5,
      ),
    ];
  }

  // 构建当前页面内容
  Widget _buildCurrentPage(BuildContext context) {
    final windowProvider = Provider.of<WindowProvider>(context, listen: false);

    switch (windowProvider.currentPage) {
      case WindowPage.home:
        return const HomePage();
      default:
        return const HomePage();
    }
  }
}

// 更新窗口控制按钮组件，添加工具提示
class AppTitleBarControlsButtonTemplate extends StatelessWidget {
  const AppTitleBarControlsButtonTemplate({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.hoverColor,
    required this.iconColor,
    
    this.iconSize = 20,
    this.iconWeight = 300.0,
    this.rotateAngle = 0.0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color hoverColor;
  final Color iconColor;
  final double iconSize;
  final double iconWeight;
  final double grade = -25.0;
  final double opticalSize = 48.0;
  final double rotateAngle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 45,
      height: 30,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          hoverColor: hoverColor,
          onTap: onPressed,
          child: Transform.rotate(
            angle: rotateAngle * (3.1415926535 / 180),
            child: Icon(
              icon,
              size: iconSize,
              color: iconColor,
              weight: iconWeight,
              grade: grade,
              opticalSize: opticalSize,
            ),
          ),
        ),
      ),
    );
  }
}

enum WindowPage { home }

class WindowProvider with ChangeNotifier, WindowListener {
  bool _isMaximized = false;
  bool _isFocused = true;

  bool get isMaximized => _isMaximized;
  bool get isFocused => _isFocused;

  WindowPage _currentPage = WindowPage.home;
  WindowPage get currentPage => _currentPage;

  WindowProvider() {
    windowManager.addListener(this);
    _init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _init() async {
    _isMaximized = await windowManager.isMaximized();
    _isFocused = await windowManager.isFocused();
    notifyListeners();
  }

  // 监听窗口最大化事件
  @override
  void onWindowMaximize() {
    _isMaximized = true;
    notifyListeners();
  }

  // 监听窗口取消最大化事件
  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
    notifyListeners();
  }

  // 监听窗口获得焦点事件
  @override
  void onWindowFocus() {
    _isFocused = true;
    notifyListeners();
  }

  // 监听窗口失去焦点事件
  @override
  void onWindowBlur() {
    _isFocused = false;
    notifyListeners();
  }

  // 处理窗口最大化/还原操作
  Future<void> handleMaximizeRestore() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  // 最小化窗口
  Future<void> minimize() async {
    await windowManager.minimize();
  }

  // 关闭窗口
  Future<void> close() async {
    await windowManager.close();
  }

  void setPage(WindowPage page) {
    _currentPage = page;
    notifyListeners();
  }
}
