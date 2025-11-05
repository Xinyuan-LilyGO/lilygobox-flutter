import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';

import 'provider/theme_provider.dart';
import 'provider/language_provider.dart';
import 'provider/package_info_provider.dart';
import 'provider/window_provider.dart';

import 'l10n/app_localizations.dart';
import 'home_page.dart';
import 'settings_page.dart';
import 'add_board_page.dart';

// MainApp 现在可以是 StatelessWidget，因为状态已经移到 Provider 中
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 在当前帧渲染完成之后执行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PackageInfoProvider>(
        context,
        listen: false,
      ).initializePackageInfo();
    });

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
          // onPressed: isFocused ? () => windowProvider.minimize() : null,
          // hoverColor: isFocused
          //     ? theme.appTitleBarIconBackgroundColor
          //     : Colors.transparent,
          onPressed: () => windowProvider.minimize(),
          hoverColor: theme.appTitleBarIconBackgroundColor,
          iconColor: iconColor,
        ),
        // 最大化/还原按钮
        AppTitleBarControlsButtonTemplate(
          icon: isMaximized ? Symbols.filter_none : Symbols.crop_square_rounded,
          // onPressed: isFocused
          //     ? () => windowProvider.handleMaximizeRestore()
          //     : null,
          // hoverColor: isFocused
          //     ? theme.appTitleBarIconBackgroundColor
          //     : Colors.transparent,
          onPressed: () => windowProvider.handleMaximizeRestore(),
          hoverColor: theme.appTitleBarIconBackgroundColor,
          iconSize: isMaximized ? 13.5 : 14,
          iconWeight: 510.0,
          rotateAngle: isMaximized ? 180 : 0,
          iconColor: iconColor,
        ),
        // 关闭按钮
        AppTitleBarControlsButtonTemplate(
          icon: Symbols.close_rounded,
          // onPressed: isFocused ? () => windowProvider.close() : null,
          // hoverColor: isFocused ? Colors.red.shade600 : Colors.transparent,
          onPressed: () => windowProvider.close(),
          hoverColor: Colors.red.shade600,
          iconColor: iconColor,
        ),
      ],
    );
  }

  // 构建自定义标题栏
  Widget _buildAppTitleBar(BuildContext context) {
    final windowProvider = Provider.of<WindowProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final packageInfoProvider = Provider.of<PackageInfoProvider>(
      context,
      listen: false,
    );
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
                  packageInfoProvider.appName,
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
                  // onTap: isFocused
                  //     ? () {
                  //         // 点击设置按钮，切换到设置页面
                  //         Provider.of<WindowProvider>(
                  //           context,
                  //           listen: false,
                  //         ).setPage(WindowPage.settings);
                  //       }
                  //     : null,
                  onTap: () {
                    // 点击设置按钮，切换到设置页面
                    Provider.of<WindowProvider>(
                      context,
                      listen: false,
                    ).setPage(WindowPage.settings);
                  },
                  splashFactory: InkRipple.splashFactory,
                  borderRadius: BorderRadius.circular(
                    settingsButtonDiameter / 2,
                  ),
                  // hoverColor: isFocused
                  //     ? theme
                  //           .appTitleBarIconBackgroundColor // 鼠标悬停时的亮度增加
                  //     : Colors.transparent, // 非焦点状态下不显示hover效果
                  hoverColor: theme.appTitleBarIconBackgroundColor,
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

  // 构建当前页面内容
  Widget _buildCurrentPage(BuildContext context) {
    return Consumer<WindowProvider>(
      builder: (context, windowProvider, child) {
        final WindowPage currentPage = windowProvider.currentPage;

        // 确定 BASE LAYER (基础内容层) 应该显示哪个页面
        // 如果当前是 settings，则基础层显示 settings
        // 如果当前是 home 或 addBoard (模态)，则基础层显示 home
        final WindowPage basePageKey = currentPage == WindowPage.settings
            ? WindowPage.settings
            : WindowPage.home;

        // BASE LAYER: 处理 Home <-> Settings 的切换动画
        final Widget baseContent = AnimatedSwitcher(
          // 动画时长保持不变
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (Widget child, Animation<double> animation) {
            // 通过 Key 识别当前正在进入/退出的页面
            final WindowPage key = (child.key as ValueKey<WindowPage>).value;

            // Settings Page: 使用滑动动画 (原风格)
            if (key == WindowPage.settings) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 1.0), // 从底部开始
                  end: const Offset(0.0, 0.0), // 到正常位置
                ).animate(animation),
                child: child,
              );
            }
            // Home Page: 使用渐变动画
            else {
              return FadeTransition(opacity: animation, child: child);
            }
          },
          child: SizedBox.expand(
            // 确保子组件的 Key 发生变化以触发 AnimatedSwitcher
            key: ValueKey(basePageKey),
            // 实例化基础层页面
            child: basePageKey == WindowPage.settings
                ? SettingsPage(windowProvider: windowProvider)
                : const HomePage(),
          ),
        );

        // 处理背景遮罩的缓慢渐变动画
        final Widget modalBarrier = AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            // 背景遮罩只使用渐变动画
            return FadeTransition(opacity: animation, child: child);
          },
          child: currentPage == WindowPage.addBoard
              ? const ModalBarrier(
                  key: ValueKey('modal_barrier_active'), // 激活时的 Key
                  color: Color.fromARGB(100, 0, 0, 0), // 半透明黑色
                )
              : Container(
                  key: const ValueKey('modal_barrier_inactive'), // 非激活时的 Key
                ),
        );

        // 处理 AddBoard 模态弹窗的缩放动画
        final Widget modalContent = AnimatedSwitcher(
          // 动画时长保持不变
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            // 弹窗内容保持缩放动画
            return ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
          child: currentPage == WindowPage.addBoard
              ? AddBoardPage(
                  // 确保 AddBoardPage 作为模态层始终占据整个屏幕
                  key: const ValueKey(WindowPage.addBoard),
                  windowProvider: windowProvider,
                )
              // 当 AddBoardPage 不激活时，返回一个空的 Container，Key 必须不同于 addBoard 的 key
              : Container(key: const ValueKey('empty_modal_content')),
        );

        // 使用 Expanded 包裹 Stack，将三层叠加起来
        return Expanded(
          child: Stack(
            children: [
              baseContent, // 底层内容 (Home 或 Settings)
              modalBarrier, // 中层背景遮罩 (新的 FadeTransition)
              modalContent, // 上层模态弹窗 (保持 ScaleTransition)
            ],
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
