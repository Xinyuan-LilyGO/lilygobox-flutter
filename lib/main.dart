/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-10-17 22:29:20
 * @LastEditTime: 2025-10-17 23:59:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  // 确保 Flutter 绑定已初始化（类似C++中的初始化库）
  WidgetsFlutterBinding.ensureInitialized();
  // 确保 windowManager 已初始化
  await windowManager.ensureInitialized();

  // 定义窗口选项（类似C++中的窗口配置结构体）
  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600), // 初始窗口大小
    center: true, // 窗口居中显示
    backgroundColor: Colors.transparent, // 设置背景透明
    skipTaskbar: false, // 不在任务栏中隐藏
    titleBarStyle: TitleBarStyle.hidden, // 关键：隐藏原生标题栏，以便使用自定义标题栏
  );

  // 等待窗口准备好显示（类似C++中的窗口创建回调）
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show(); // 显示窗口
    await windowManager.focus(); // 窗口获得焦点
  });

  // 启动Flutter应用（类似C++中的程序主循环）
  runApp(const MainApp());
}

// MainApp 转换为 StatefulWidget 以实现 WindowListener
// StatefulWidget 类似于C++中的有状态类，可以保存和更新状态
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

// 混入 WindowListener 以监听窗口状态变化
// 在Dart中，mixin类似于C++的多重继承，用于代码复用
class _MainAppState extends State<MainApp> with WindowListener {
  // 私有成员变量，存储窗口是否最大化状态
  // Dart中以下划线开头的变量表示私有，类似于C++中的private成员
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    // 添加窗口监听器（类似C++中的事件监听器注册）
    windowManager.addListener(this);
    _init(); // 调用初始化方法
  }

  @override
  void dispose() {
    // 移除窗口监听器（类似C++中的资源清理）
    windowManager.removeListener(this);
    super.dispose();
  }

  // 初始化方法：检查窗口初始状态
  void _init() async {
    // 异步检查窗口是否最大化
    _isMaximized = await windowManager.isMaximized();
    // 更新UI状态（类似C++中的界面刷新）
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
  // 在Flutter中，组件构建方法通常以_build开头
  Widget _buildWindowControls() {
    return Row(
      children: [
        // 最小化按钮
        _WindowButton(
          icon: Icons.minimize_rounded, // 图标
          onPressed: () => windowManager.minimize(), // 点击回调
          hoverColor: Colors.grey.withOpacity(0.2), // 鼠标悬停颜色
        ),
        // 最大化/还原按钮（根据状态显示不同图标）
        _WindowButton(
          icon: _isMaximized
              ? Icons
                    .filter_none_rounded // 还原图标
              : Icons.crop_square_rounded, // 最大化图标
          onPressed: _handleMaximizeRestore, // 点击回调
          hoverColor: Colors.grey.withOpacity(0.2),
        ),
        // 关闭按钮
        _WindowButton(
          icon: Icons.close_rounded,
          onPressed: () => windowManager.close(), // 关闭窗口
          hoverColor: Colors.red.shade600, // 关闭按钮使用红色高亮
          iconColor: Colors.black, // 图标颜色
        ),
      ],
    );
  }

  // 构建自定义标题栏
  Widget _buildCustomTitleBar(BuildContext context) {
    // 标题栏高度
    const double titleBarHeight = 30.0;

    return Container(
      height: titleBarHeight,
      color: Colors.white, // 标题栏背景色
      child: Row(
        children: [
          // 左侧可拖动区域 (大部分区域用于拖动窗口)
          Expanded(
            // 使用 DragToMoveArea 实现窗口拖动功能
            child: DragToMoveArea(
              child: Container(
                alignment: Alignment.centerLeft, // 左对齐
                padding: const EdgeInsets.only(left: 10), // 左内边距
                child: const Text(
                  'Ciallo (自定义标题栏)', // 标题文本
                  style: TextStyle(fontSize: 12, color: Colors.black),
                ),
              ),
            ),
          ),
          // 右侧窗口控制按钮
          _buildWindowControls(),
        ],
      ),
    );
  }

  // 主要的UI构建方法（类似C++中的渲染函数）
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // 隐藏调试标志
      // 使用 Scaffold 来组织页面结构（Flutter的基本布局组件）
      home: Scaffold(
        // 设置 Scaffold 背景为透明，使其与窗口背景保持一致
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            // 1. 顶部自定义标题栏
            _buildCustomTitleBar(context),
            // 2. 应用程序主要内容区域
            Expanded(
              // Expanded让子组件占据剩余空间
              child: Container(
                // 应用内容背景装饰
                decoration: const BoxDecoration(color: Colors.blue),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(20), // 内边距
                    decoration: BoxDecoration(
                      color: Colors.blue.shade800, // 内容区域背景色
                      borderRadius: BorderRadius.circular(10), // 圆角
                    ),
                    child: const Text(
                      '应用程序内容区域',
                      style: TextStyle(color: Colors.white, fontSize: 24),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 封装窗口控制按钮的 StatelessWidget
// StatelessWidget 类似于C++中的无状态类，属性不可变
class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon, // 必需参数：图标
    required this.onPressed, // 必需参数：点击回调函数
    required this.hoverColor, // 必需参数：悬停颜色
    this.iconColor = Colors.black, // 可选参数：图标颜色，默认黑色
  });

  // 成员变量声明（类似C++类的成员变量）
  final IconData icon; // 图标数据类型
  final VoidCallback onPressed; // 回调函数类型（无参数无返回值）
  final Color hoverColor; // 颜色类型
  final Color iconColor; // 颜色类型

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
          child: Icon(icon, size: 16, color: iconColor), // 图标组件
        ),
      ),
    );
  }
}
