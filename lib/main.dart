/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-10-17 22:29:20
 * @LastEditTime: 2025-10-25 17:59:23
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import 'theme.dart';

void main() async {
  debugPaintSizeEnabled = false; // 部件边界调试

  // 确保 Flutter 绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();
  // 确保 windowManager 已初始化
  await windowManager.ensureInitialized();

  // 定义窗口选项
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1050, 700), // 初始窗口大小
    backgroundColor: Colors.transparent, // 设置背景透明
    skipTaskbar: false, // 不在任务栏中隐藏
    titleBarStyle: TitleBarStyle.hidden, // 关键：隐藏原生标题栏，以便使用自定义标题栏
    center: true, // 窗口居中显示
  );

  // 等待窗口准备好显示
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless(); // 设置窗口无边框
    // await windowManager.setHasShadow(true); // 添加窗口阴影
    await windowManager.show(); // 显示窗口
    await windowManager.focus(); // 窗口获得焦点
  });

  // 启动Flutter应用
  runApp(
    // 使用 MultiProvider 包装应用
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ThemeProvider())],
      child: const MainApp(),
    ),
  );
}

// MainApp 转换为 StatefulWidget 以实现 WindowListener
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

// 混入 WindowListener 以监听窗口状态变化
class _MainAppState extends State<MainApp> with WindowListener {
  // 私有成员变量，存储窗口是否最大化状态
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    // 添加窗口监听器
    windowManager.addListener(this);
    _init(); // 调用初始化方法
  }

  @override
  void dispose() {
    // 移除窗口监听器
    windowManager.removeListener(this);
    super.dispose();
  }

  // 初始化方法：检查窗口初始状态
  void _init() async {
    // 异步检查窗口是否最大化
    _isMaximized = await windowManager.isMaximized();
    // 更新UI状态
    setState(() {});
  }

  // 监听窗口最大化事件（回调函数）
  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true; // 更新状态为最大化
    });
  }

  // 监听窗口取消最大化（恢复）事件
  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false; // 更新状态为非最大化
    });
  }

  // 处理窗口最大化/还原操作
  Future<void> _handleMaximizeRestore() async {
    if (_isMaximized) {
      await windowManager.unmaximize(); // 还原窗口
    } else {
      await windowManager.maximize(); // 最大化窗口
    }
  }

  // 构建窗口控制按钮组件
  Widget _buildWindowControls(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    return Row(
      children: [
        // 最小化按钮
        _WindowButton(
          icon: Symbols.remove_rounded, // 图标
          onPressed: () => windowManager.minimize(), // 点击回调
          hoverColor: Colors.grey.withOpacity(0.2), // 鼠标悬停颜色
          iconColor: theme.iconColor, // 图标颜色
        ),
        // 最大化/还原按钮（根据状态显示不同图标）
        _WindowButton(
          icon: _isMaximized
              ? Symbols
                    .filter_none // 最大化图标
              : Symbols.crop_square_rounded, // 还原图标
          onPressed: _handleMaximizeRestore, // 点击回调
          hoverColor: Colors.grey.withOpacity(0.2),
          iconSize: _isMaximized ? 13.5 : 14,
          iconWeight: 510.0,
          rotateAngle: _isMaximized ? 180 : 0,
          iconColor: theme.iconColor, // 图标颜色
        ),
        // 关闭按钮
        _WindowButton(
          icon: Symbols.close_rounded,
          onPressed: () => windowManager.close(), // 关闭窗口
          hoverColor: Colors.red.shade600, // 关闭按钮使用红色高亮
          iconColor: theme.iconColor, // 图标颜色
        ),
      ],
    );
  }

  // 构建自定义标题栏
  Widget _buildCustomTitleBar(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    // 标题栏高度
    const double titleBarHeight = 30.0;

    return Container(
      height: titleBarHeight,
      color: theme.primary,
      child: Row(
        children: [
          // 填充剩余空间
          Expanded(
            // 使用 DragToMoveArea 实现窗口拖动功能
            child: DragToMoveArea(
              child: Container(
                alignment: Alignment.centerLeft, // 左对齐
                padding: const EdgeInsets.only(left: 10), // 左内边距
                child: Text(
                  'Ciallo (自定义标题栏)', // 标题文本
                  style: TextStyle(fontSize: 12, color: theme.textColor),
                ),
              ),
            ),
          ),
          // 右侧窗口控制按钮
          _buildWindowControls(context),
        ],
      ),
    );
  }

  // 构建窗口边框调整区域
  Widget _buildWindowResizeArea() {
    const double resizeAreaSize = 5.0;

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

  // 主要的UI构建方法
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final theme = themeProvider.themeData;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Container(
              margin: const EdgeInsets.all(10), // 更大的边距
              decoration: BoxDecoration(
                color: theme.primary,
                borderRadius: BorderRadius.circular(8),
                boxShadow: _buildBoxShadow(), // 使用专门的柔和阴影方法
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        _buildCustomTitleBar(context),
                        Expanded(
                          child: Container(
                            color: theme.primary,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade800,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '应用程序内容区域',
                                  style: TextStyle(
                                    color: theme.textColor,
                                    fontSize: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    _buildWindowResizeArea(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
}

// 封装窗口控制按钮的 StatelessWidget
class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon, // 必需参数：图标
    required this.onPressed, // 必需参数：点击回调函数
    required this.hoverColor, // 必需参数：悬停颜色
    this.iconColor = const Color.fromARGB(255, 255, 255, 255), // 可选参数：图标颜色
    this.iconSize = 20, // 图标尺寸参数
    this.iconWeight = 300.0, // 图标粗细
    this.rotateAngle = 0.0, // 旋转角度（度数）
  });

  // 成员变量声明
  final IconData icon; // 图标数据类型
  final VoidCallback onPressed; // 回调函数类型（无参数无返回值）
  final Color hoverColor; // 颜色类型
  final Color iconColor; // 颜色颜色
  final double iconSize; // 图标尺寸
  final double iconWeight; // 图标粗细
  final double grade = -25.0; // 图标等级，用于微调粗细 (-25 到 0 之间)
  final double opticalSize = 48.0; // 光学尺寸，影响图标的视觉比例
  final double rotateAngle; // 旋转角度（以度为单位，如 90.0 表示旋转90度）

  @override
  Widget build(BuildContext context) {
    // SizedBox用于控制固定尺寸的容器
    return SizedBox(
      width: 45, // 固定宽度
      height: 30, // 固定高度
      child: Material(
        color: Colors.transparent, // 透明背景
        child: InkWell(
          hoverColor: hoverColor, // 鼠标悬停时的颜色
          onTap: onPressed, // 点击事件处理
          child: Transform.rotate(
            angle: rotateAngle * (3.1415926535 / 180), // 将角度转换为弧度
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
