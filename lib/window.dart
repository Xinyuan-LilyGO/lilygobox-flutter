import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';

// 假设这些文件存在
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
      builder: (context, themeProvider, windowProvider, languageProvider, child) {
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
                            // !!! 修改: 使用 Consumer 包裹 _buildCurrentPage 以监听 currentPage 变化
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
              ? theme.appTitleBarIconBackgroundColor
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
              ? theme.appTitleBarIconBackgroundColor
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
    // 设置按钮的尺寸和图标大小（可以根据需要调整）
    // 调整尺寸让按钮看起来更协调
    const double settingsButtonDiameter = 24.0; // 按钮的直径

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
          // 添加设置按钮
          // 为了使按钮居中，可以包裹在一个Center中或者调整SizedBox
          Center(
            // 使用Center包裹，使按钮在垂直方向上居中
            child: SizedBox(
              width: settingsButtonDiameter,
              height: settingsButtonDiameter,
              child: Material(
                color: Colors.transparent, // 确保 Material 背景透明
                child: InkWell(
                  onTap: isFocused
                      ? () {
                          // !!! 修改：点击设置按钮，切换到设置页面
                          Provider.of<WindowProvider>(
                            context,
                            listen: false,
                          ).setPage(WindowPage.settings);
                        }
                      : null,
                  splashFactory: InkRipple.splashFactory,
                  borderRadius: BorderRadius.circular(
                    settingsButtonDiameter / 2,
                  ),
                  hoverColor: isFocused
                      ? theme
                            .appTitleBarIconBackgroundColor // 鼠标悬停时的亮度增加
                      : Colors.transparent, // 非焦点状态下不显示hover效果
                  child: Container(
                    alignment: Alignment.center, // 确保图标在圆形区域内居中
                    decoration: BoxDecoration(
                      color: Colors.transparent, // 常显示的圆圈背景
                      borderRadius: BorderRadius.circular(
                        settingsButtonDiameter / 2,
                      ), // 确保背景也是圆形
                    ),
                    child: Icon(
                      Symbols.settings,
                      size: 16.0,
                      color: isFocused
                          ? theme.iconColor
                          : theme.inactiveIconColor,
                      fill: 1, // 图标填充
                      weight: 400, // 可选：设置图标粗细
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 5.0),
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

  // 构建当前页面内容 (修改)
  Widget _buildCurrentPage(BuildContext context) {
    // 使用 Consumer 确保当 currentPage 变化时，AnimatedSwitcher 能够重建并触发动画
    return Consumer<WindowProvider>(
      builder: (context, windowProvider, child) {
        final Widget page;
        final WindowPage currentPage = windowProvider.currentPage;

        switch (currentPage) {
          case WindowPage.home:
            page = const HomePage();
            break;
          case WindowPage.settings:
            // 传入 windowProvider
            page = SettingsPage(windowProvider: windowProvider);
            break;
          default:
            page = const HomePage();
        }

        return Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500), // 调整动画持续时间
            reverseDuration: const Duration(milliseconds: 500), // 反向动画持续时间
            switchInCurve: Curves.easeOutCubic, // 进入曲线
            switchOutCurve: Curves.easeInCubic, // 退出曲线
            transitionBuilder: (Widget child, Animation<double> animation) {
              // 使用 child.key 来判断当前正在执行动画的组件是谁
              final isSettingsPage =
                  child.key == const ValueKey(WindowPage.settings);

              // Settings Page: Slide in from bottom, slide out to bottom
              if (isSettingsPage) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 1.0), // 从底部开始
                    end: const Offset(0.0, 0.0), // 到正常位置
                  ).animate(animation),
                  child: child,
                );
              } else {
                // Home Page: Fade in/out
                return FadeTransition(opacity: animation, child: child);
              }
            },
            child: SizedBox.expand(
              // 确保子组件的 Key 发生变化以触发 AnimatedSwitcher
              key: ValueKey(currentPage),
              child: page,
            ),
          ),
        );
      },
    );
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

// !!! 修改: 增加 settings 枚举值
enum WindowPage { home, settings }

class WindowProvider with ChangeNotifier, WindowListener {
  bool _isMaximized = false;
  bool _isFocused = true;

  bool get isMaximized => _isMaximized;
  bool get isFocused => _isFocused;

  // !!! 修改: 默认页面为 home
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

  // !!! 修改: setPage 用于切换页面
  void setPage(WindowPage page) {
    _currentPage = page;
    notifyListeners();
  }
}

// !!! 新增: 设置页面组件
class SettingsPage extends StatelessWidget {
  final WindowProvider windowProvider;

  const SettingsPage({super.key, required this.windowProvider});

  @override
  Widget build(BuildContext context) {
    // 确保使用正确的方式获取 Provider 的值
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    return Container(
      color: theme.secondary, // 与主窗口背景一致
      child: Column(
        children: [
          // 顶部标题栏/关闭按钮
          Container(
            height: 30.0, // 与主标题栏高度保持一致
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor, // 使用主题中的分隔线颜色
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  // 假设有一个名为 settingsTitle 的本地化键
                  context.l10n.settingsTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.appTitleTextColor,
                  ),
                ),
                const Spacer(),
                // 右上角关闭按钮 (返回主页)
                IconButton(
                  icon: Icon(
                    Symbols.close_rounded,
                    size: 18,
                    color: theme.iconColor,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    maxWidth: 30,
                    maxHeight: 30,
                  ),
                  onPressed: () {
                    windowProvider.setPage(WindowPage.home); // 返回主页
                  },
                ),
              ],
            ),
          ),
          // 设置内容区域
          Expanded(
            child: Center(
              child: Text(
                "settingsContent", // 假设有一个名为 settingsContent 的本地化键
                style: TextStyle(color: theme.textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
