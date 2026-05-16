/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-05 09:52:14
 * @LastEditTime: 2025-11-20 10:08:16
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/app_navigation_provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/widgets/animated_circle_icon_button.dart';
import '../../domain/device_catalog.dart';
import '../../state/add_device_page_type.dart';
import '../../state/device_manager_provider.dart';

class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  // 用于控制两个按钮的悬停状态
  bool _isHoveringInitialButton = false;
  bool _isHoveringAddDeviceButton = false;

  final Duration _animationDuration = const Duration(milliseconds: 150);

  // 当前页面状态
  AddDevicePageType _currentPage = AddDevicePageType.initial;

  // 模拟板子型号数据
  final List<String> _deviceTypes = DeviceCatalog.supportedDeviceNames;

  // 搜索栏控制器和选中的板子
  final TextEditingController _searchController = TextEditingController();
  // 保持初始值为 null
  String? _selectedDevice;
  List<String> _filteredDevices = [];

  // 用于跟踪当前悬停的板子（简化悬停管理）
  String? _hoveredDevice;

  @override
  void initState() {
    super.initState();
    _filteredDevices = _deviceTypes; // 初始化时显示所有板子
    _searchController.addListener(_filterDevices);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterDevices);
    _searchController.dispose();
    super.dispose();
  }

  // 根据搜索文本过滤板子列表
  void _filterDevices() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredDevices = _deviceTypes
          .where((device) => device.toLowerCase().contains(query))
          .toList();

      // 搜索时清除悬停状态
      _hoveredDevice = null;
    });
  }

  // 构建右上角的关闭按钮
  Widget _buildCloseButton(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    return AnimatedCircleIconButton(
      icon: Symbols.close_rounded,
      theme: theme,
      onPressed: () => context.read<AppNavigationProvider>().goHome(),
    );
  }

  // 构建左上角的返回按钮 (风格与关闭按钮一致)
  Widget _buildBackButton(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    return AnimatedCircleIconButton(
      icon: Symbols.arrow_back_rounded,
      theme: theme,
      onPressed: () {
        setState(() {
          _currentPage = AddDevicePageType.initial;
          _selectedDevice = null;
          _searchController.clear();
          _hoveredDevice = null;
        });
      },
    );
  }

  // 初始页面的内容 (添加板子类型按钮)
  Widget _buildInitialPage(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    return Padding(
      key: const ValueKey('InitialPage'), // AnimatedSwitcher 需要 key
      padding: const EdgeInsets.all(35.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 标题
          Text(
            context.l10n.addDevice,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
          const SizedBox(height: 5),
          // 描述
          Text(
            context.l10n.addDeviceDescription,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: theme.textColorTertiary),
          ),
          const SizedBox(height: 20),
          // 长条圆角按键
          SizedBox(
            width: double.infinity,
            height: 50,
            // 按钮的主体背景色由 AnimatedContainer 动画控制
            child: MouseRegion(
              onEnter: (_) => setState(() => _isHoveringInitialButton = true),
              onExit: (_) => setState(() => _isHoveringInitialButton = false),
              child: AnimatedContainer(
                duration: _animationDuration,
                curve: Curves.easeInOut,
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  // AnimatedContainer 负责背景色的动画
                  color: _isHoveringInitialButton
                      ? theme
                            .secondaryTextHoverColorAlt // 悬停时的颜色
                      : theme.secondaryTextBackgroundColor, // 默认背景色
                ),
                child: Material(
                  // Material 必须是透明的，这样才能看到 AnimatedContainer 的背景色
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    highlightColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    onTap: () {
                      // 点击后切换到选择板子页面
                      setState(() {
                        _isHoveringInitialButton = false; // 确保清除悬停状态
                        _currentPage = AddDevicePageType.selectDevice;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Center(
                      child: Text(
                        context.l10n.addByDeviceType,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: theme.textColorPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 选择板子页面的内容 (使用设置页面左侧菜单风格)
  Widget _buildSelectDevicePage(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    // 检查选中的板子是否在当前过滤列表中
    final bool isDeviceSelected =
        _selectedDevice != null && _filteredDevices.contains(_selectedDevice);

    return Padding(
      key: const ValueKey('SelectDevicePage'), // AnimatedSwitcher 需要 key
      padding: const EdgeInsets.all(35.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 标题
          Text(
            context.l10n.selectDevice,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
          const SizedBox(height: 5),
          // 描述
          Text(
            context.l10n.selectDeviceDescription,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: theme.textColorTertiary),
          ),
          const SizedBox(height: 20),

          // 搜索栏
          Container(
            padding: const EdgeInsets.only(left: 10.0),
            decoration: BoxDecoration(
              color: theme.secondaryTextBackgroundColor, // 使用与按钮背景相似的颜色
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextField(
              controller: _searchController,
              // 添加 cursorColor 属性来设置光标颜色
              cursorColor: theme.primary,
              decoration: InputDecoration(
                hintText: context.l10n.searchForDeviceModel,
                hintStyle: TextStyle(
                  color: theme.textColorTertiary,
                  fontSize: 15.0,
                ),
                border: InputBorder.none,

                // 启用紧凑模式，减少默认的垂直空间
                isDense: true,

                // 使用 contentPadding 进一步微调高度
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 0.0,
                ),

                // 添加清除按钮，方便用户清空搜索
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Symbols.close_rounded,
                          size: 19,
                          color: theme.iconColor,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          // clear() 会自动触发 listener 中的 _filterDevices
                        },
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
              style: TextStyle(color: theme.textColorPrimary),
            ),
          ),
          const SizedBox(height: 20),

          // 添加板子型号列表
          Expanded(
            // 使用 Expanded 填充剩余空间
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              decoration: BoxDecoration(
                color: theme.primary, // 使用 primary 作为列表背景色，与二次背景色区分
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ListView.builder(
                  itemCount: _filteredDevices.length,
                  itemBuilder: (context, index) {
                    final deviceName = _filteredDevices[index];
                    final isSelected = deviceName == _selectedDevice;
                    final isHovered = deviceName == _hoveredDevice;

                    return MouseRegion(
                      onEnter: (event) {
                        setState(() {
                          // 只有在非选中状态下才应用悬停颜色
                          if (!isSelected) {
                            _hoveredDevice = deviceName;
                          }
                        });
                      },
                      onExit: (event) {
                        setState(() {
                          _hoveredDevice = null;
                        });
                      },
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedDevice = deviceName;
                            _hoveredDevice = null; // 点击后清除悬停状态
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(
                            vertical: 3,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme
                                      .primaryTextSelectedColor // 选中背景色
                                : isHovered
                                ? theme
                                      .primaryTextHoverColor // 悬停背景色
                                : theme.primary, // 默认背景色
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8.0,
                              horizontal: 10.0,
                            ),
                            child: Row(
                              children: [
                                // 左侧图标
                                Icon(
                                  Symbols.developer_board_rounded,
                                  size: 20,
                                  color: theme.iconColor,
                                ),
                                const SizedBox(width: 10),
                                // 板子名称
                                Expanded(
                                  child: Text(
                                    deviceName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: theme.textColorSecondary,
                                    ),
                                  ),
                                ),
                                // 右侧选中标记 (如果选中)
                                if (isSelected)
                                  Icon(
                                    Symbols.check_rounded,
                                    size: 20,
                                    color: theme.iconColor,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 底部 "添加板子" 按钮
          SizedBox(
            width: double.infinity,
            height: 50,
            child: MouseRegion(
              onEnter: (_) => setState(() => _isHoveringAddDeviceButton = true),
              onExit: (_) => setState(() => _isHoveringAddDeviceButton = false),
              child: AnimatedContainer(
                duration: _animationDuration,
                curve: Curves.easeInOut,
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  // AnimatedContainer 负责背景色的动画和禁用时的颜色
                  color: isDeviceSelected
                      ? (_isHoveringAddDeviceButton
                            ? theme
                                  .secondaryTextHoverColorAlt // 启用且悬停
                            : theme.secondaryTextBackgroundColor) // 启用且非悬停
                      : theme.secondaryTextBackgroundColor.withValues(
                          alpha: 0.5,
                        ), // 禁用时变暗
                ),
                child: Material(
                  // Material 必须是透明的
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    highlightColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    // 未选中板子时，onTap 设为 null，禁用按钮
                    onTap: isDeviceSelected
                        ? () {
                            debugPrint('添加板子: $_selectedDevice');
                            _isHoveringAddDeviceButton = false;

                            // 使用 DeviceManagerProvider 添加板子
                            final deviceManager =
                                Provider.of<DeviceManagerProvider>(
                                  context,
                                  listen: false,
                                );
                            deviceManager.addDevice(_selectedDevice!);

                            context
                                .read<AppNavigationProvider>()
                                .goHome();
                          }
                        : null,
                    borderRadius: BorderRadius.circular(6),
                    child: Center(
                      child: Text(
                        context.l10n.addDevice,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          // 根据 isDeviceSelected 调整文字颜色
                          color: isDeviceSelected
                              ? theme
                                    .textColorPrimary // 选中时的文字颜色
                              : theme.textColorTertiary, // 禁用时的文字颜色
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 统一在这里获取主题数据
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    // 根据当前页面状态选择要显示的 Widget
    final Widget currentPageWidget;
    switch (_currentPage) {
      case AddDevicePageType.initial:
        currentPageWidget = _buildInitialPage(context);
        break;
      case AddDevicePageType.selectDevice:
        currentPageWidget = _buildSelectDevicePage(context);
        break;
    }

    // Stack 中不再包含 ModalBarrier，只包含居中弹窗内容
    return Stack(
      children: [
        // 居中弹窗内容
        Center(
          child: Container(
            // 外层容器只负责阴影，不裁剪
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromARGB(100, 0, 0, 0),
                  blurRadius: 30,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: ClipRRect(
              // 内层容器负责裁剪
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 400,
                height: 550,
                color: theme.secondary, // 背景色移到内层
                child: Stack(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, animation) {
                        final isInitialToSelect =
                            child.key == const ValueKey('SelectDevicePage');
                        final beginOffset = isInitialToSelect
                            ? const Offset(1.0, 0.0)
                            : const Offset(-1.0, 0.0);

                        final offsetAnimation = Tween<Offset>(
                          begin: beginOffset,
                          end: Offset.zero,
                        ).animate(animation);

                        return SlideTransition(
                          position: offsetAnimation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: currentPageWidget,
                    ),

                    // 按钮代码保持不变...
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _buildCloseButton(context),
                    ),

                    if (_currentPage == AddDevicePageType.selectDevice)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _buildBackButton(context),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
