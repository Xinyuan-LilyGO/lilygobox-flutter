import 'package:LilygoBox/language.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart'; // 假设这里定义了 ThemeProvider 和 themeData 的返回类型
import 'window.dart';

// 定义页面枚举
enum AddBoardPageType { initial, selectBoard }

class AddBoardPage extends StatefulWidget {
  final WindowProvider windowProvider;

  const AddBoardPage({super.key, required this.windowProvider});

  @override
  State<AddBoardPage> createState() => _AddBoardPageState();
}

class _AddBoardPageState extends State<AddBoardPage> {
  // 用于控制关闭按钮的悬停状态
  bool _isHoveringClose = false;
  bool _isHoveringBack = false;
  final Duration _animationDuration = const Duration(milliseconds: 150);

  // 新增：当前页面状态
  AddBoardPageType _currentPage = AddBoardPageType.initial;

  // 模拟板子型号数据
  final List<String> _boardTypes = [
    'ESP32 Dev Module',
    'LilyGo T-Display-S3',
    'TTGO T-Beam',
    'LoRaWAN Module',
    'ESP8266 NodeMCU',
    'Arduino Uno',
    'Raspberry Pi Pico',
  ];

  // 搜索栏控制器和选中的板子
  final TextEditingController _searchController = TextEditingController();
  String? _selectedBoard;
  List<String> _filteredBoards = [];

  // 新增：用于存储每个菜单项当前 Hover 颜色的 Map
  late Map<String, Color> _currentHoverColors;

  @override
  void initState() {
    super.initState();
    _filteredBoards = _boardTypes; // 初始化时显示所有板子
    _searchController.addListener(_filterBoards);

    // 初始化时选中第一个板子，除非列表为空
    if (_filteredBoards.isNotEmpty) {
      _selectedBoard = _filteredBoards.first;
    }

    // 初始化 Hover 颜色 Map
    _initHoverColors();
  }

  void _initHoverColors() {
    _currentHoverColors = {
      for (var board in _boardTypes) board: Colors.transparent,
    };
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterBoards);
    _searchController.dispose();
    super.dispose();
  }

  // 根据搜索文本过滤板子列表
  void _filterBoards() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredBoards = _boardTypes
          .where((board) => board.toLowerCase().contains(query))
          .toList();

      // 搜索结果变化时，如果当前选中项不在结果中，则选中第一个结果
      if (_filteredBoards.isNotEmpty &&
          !_filteredBoards.contains(_selectedBoard)) {
        _selectedBoard = _filteredBoards.first;
      } else if (_filteredBoards.isEmpty) {
        _selectedBoard = null;
      }
    });
  }

  // 构建右上角的关闭按钮
  Widget _buildCloseButton(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringClose = true),
      onExit: (_) => setState(() => _isHoveringClose = false),
      child: AnimatedContainer(
        duration: _animationDuration,
        width: 33,
        height: 33,
        decoration: BoxDecoration(
          color: _isHoveringClose
              ? theme.iconHoverColor
              : theme.iconBackgroundColor,
          shape: BoxShape.circle,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                // 在关闭页面前，强制清除悬停状态
                _isHoveringClose = false;
              });
              // 点击关闭按钮，切换回 home 页面
              widget.windowProvider.setPage(WindowPage.home);
            },
            borderRadius: BorderRadius.circular(20.0),
            child: Center(
              child: Icon(
                Symbols.close_rounded,
                size: 19,
                color: theme.iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 构建左上角的返回按钮 (风格与关闭按钮一致)
  Widget _buildBackButton(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    return MouseRegion(
      // 新增：悬停状态管理
      onEnter: (_) => setState(() => _isHoveringBack = true),
      onExit: (_) => setState(() => _isHoveringBack = false),
      child: AnimatedContainer(
        // 新增：悬停动画
        duration: _animationDuration,
        width: 33,
        height: 33,
        decoration: BoxDecoration(
          color:
              _isHoveringBack // 使用新的悬停状态
              ? theme.iconHoverColor
              : theme.iconBackgroundColor,
          shape: BoxShape.circle,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                // 在切换页面/组件状态前，确保清除悬停状态
                _isHoveringBack = false; // 强制清除悬停状态

                _currentPage = AddBoardPageType.initial; // 返回初始页面
                // _selectedBoard = null; // 保持当前选中项不变，下次进入时会重新选中第一个
                _searchController.clear(); // 清空搜索栏
                _filteredBoards = _boardTypes; // 恢复完整列表
                _selectedBoard = _boardTypes.isNotEmpty
                    ? _boardTypes.first
                    : null; // 重设选中项
                _initHoverColors(); // 重置悬停颜色
              });
            },
            borderRadius: BorderRadius.circular(20.0),
            child: Center(
              child: Icon(
                Symbols.arrow_back_rounded,
                size: 19,
                color: theme.iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 初始页面的内容 (添加板子类型按钮)
  Widget _buildInitialPage(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    return Padding(
      key: const ValueKey('InitialPage'), // AnimatedSwitcher 需要 key
      padding: const EdgeInsets.all(30.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 标题
          Text(
            context.l10n.addBoard,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
          const SizedBox(height: 5),
          // 描述
          Text(
            context.l10n.addBoardDescription,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: theme.textColorTertiary),
          ),
          const SizedBox(height: 20),
          // 长条圆角按键
          SizedBox(
            width: double.infinity,
            height: 50,
            child: Material(
              color: theme.tertiarytextBackgroundColor,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: () {
                  // 点击后切换到选择板子页面
                  setState(() {
                    _currentPage = AddBoardPageType.selectBoard;
                    // 确保进入选择页面时至少选中一个板子
                    if (_selectedBoard == null && _filteredBoards.isNotEmpty) {
                      _selectedBoard = _filteredBoards.first;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(6),
                hoverColor: theme.tertiaryTextHoverColor,
                splashColor: theme.tertiaryTextSplashColor,
                highlightColor: theme.tertiaryTextHighlightColor,
                child: Container(
                  width: double.infinity,
                  height: 50,
                  alignment: Alignment.center,
                  child: Text(
                    context.l10n.addByBoardType,
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
          // 可以在此添加其他按钮...
        ],
      ),
    );
  }

  // 选择板子页面的内容 (使用设置页面左侧菜单风格)
  Widget _buildSelectBoardPage(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;
    final bool isBoardSelected = _selectedBoard != null; // 始终为 true，除非列表为空

    return Padding(
      key: const ValueKey('SelectBoardPage'), // AnimatedSwitcher 需要 key
      padding: const EdgeInsets.all(30.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 标题
          Text(
            '选择板子', // 新标题
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
          const SizedBox(height: 5),
          // 描述
          Text(
            '点击下方选择你需要添加的板子', // 新描述
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: theme.textColorTertiary),
          ),
          const SizedBox(height: 20),

          // 搜索栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            decoration: BoxDecoration(
              color: theme.tertiarytextBackgroundColor, // 使用与按钮背景相似的颜色
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextField(
              controller: _searchController,
              // 添加 cursorColor 属性来设置光标颜色
              cursorColor: theme.primary,
              decoration: InputDecoration(
                hintText: '搜索板子型号',
                hintStyle: TextStyle(
                  color: theme.textColorTertiary,
                  fontSize: 15.0,
                ),
                border: InputBorder.none,

                // 启用紧凑模式，减少默认的垂直空间
                isDense: true,

                // 使用 contentPadding 进一步微调高度
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10.0,
                  horizontal: 0.0,
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
              margin: const EdgeInsets.symmetric(horizontal: 10), // 稍微缩进
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              decoration: BoxDecoration(
                color: theme.primary, // 使用 primary 作为列表背景色，与二次背景色区分
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ListView.builder(
                  itemCount: _filteredBoards.length,
                  itemBuilder: (context, index) {
                    final boardName = _filteredBoards[index];
                    final isSelected = boardName == _selectedBoard;
                    // 使用 Map 来存储和获取当前悬停颜色
                    final hoverColor =
                        _currentHoverColors[boardName] ?? Colors.transparent;

                    return MouseRegion(
                      onEnter: (event) {
                        setState(() {
                          // 只有在非选中状态下才应用悬停颜色
                          if (!isSelected) {
                            _currentHoverColors[boardName] =
                                theme.primaryTextHoverColor;
                          }
                        });
                      },
                      onExit: (event) {
                        setState(() {
                          _currentHoverColors[boardName] =
                              Colors.transparent; // 恢复透明
                        });
                      },
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedBoard = boardName;
                            // 点击后确保移除悬停状态，尽管 onExit 也会处理
                            _currentHoverColors[boardName] = Colors.transparent;
                          });
                        },
                        // 使用 AnimatedContainer 来处理背景、圆角和过渡动画
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(
                            vertical: 3,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            // 选中时使用特定的背景色，非选中且悬停时使用 hoverColor
                            color: isSelected
                                ? theme
                                      .primaryTextSelectedColor // 选中背景色
                                : hoverColor, // 非选中状态下的悬停色 (Colors.transparent 或 theme.tertiaryTextHoverColor)
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8.0,
                              horizontal: 10.0,
                            ),
                            child: Row(
                              children: [
                                // 左侧图标 (可选)
                                Icon(
                                  Symbols.developer_board_rounded,
                                  size: 20,
                                  color: theme.iconColor,
                                ),
                                const SizedBox(width: 10),
                                // 板子名称
                                Expanded(
                                  child: Text(
                                    boardName,
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
            child: Material(
              color:
                  isBoardSelected // 始终为 true
                  ? theme
                        .tertiarytextBackgroundColor // 选中时的高亮色
                  : theme.tertiarytextBackgroundColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: isBoardSelected
                    ? () {
                        // TODO: 实现添加选中板子的逻辑
                        print('添加板子');
                        widget.windowProvider.setPage(
                          WindowPage.home,
                        ); // 添加后关闭弹窗
                      }
                    : null,
                borderRadius: BorderRadius.circular(6),
                hoverColor: isBoardSelected
                    ? Colors
                          .white // 启用时的悬停效果
                    : Colors.transparent,
                child: Container(
                  width: double.infinity,
                  height: 50,
                  alignment: Alignment.center,
                  child: Text(
                    '添加板子', // 显示选中的板子
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isBoardSelected
                          ? Colors
                                .white // 选中时的文字颜色
                          : theme.textColorTertiary,
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
      case AddBoardPageType.initial:
        currentPageWidget = _buildInitialPage(context);
        break;
      case AddBoardPageType.selectBoard:
        currentPageWidget = _buildSelectBoardPage(context);
        break;
    }

    // 使用 Stack 实现模态效果：下层是背景遮罩，上层是居中弹窗
    return Stack(
      children: [
        // 背景遮罩层：变暗且不可触摸 (使用 ModalBarrier 阻止下层交互)
        const ModalBarrier(
          color: Color.fromARGB(100, 0, 0, 0), // 半透明黑色
        ),

        // 居中弹窗内容
        Center(
          child: Container(
            width: 400, // 弹窗宽度
            height: 550, // 弹窗高度
            decoration: BoxDecoration(
              color: theme.secondary, // 使用 secondary 作为弹窗背景色
              borderRadius: BorderRadius.circular(10), // 圆角
              // 阴影属性，使弹窗浮出
              boxShadow: const [
                BoxShadow(
                  color: Color.fromARGB(100, 0, 0, 0),
                  blurRadius: 30,
                  spreadRadius: 0,
                ),
              ],
            ),
            // 使用 Stack 确保按钮可以定位
            child: Stack(
              children: [
                // 使用 AnimatedSwitcher 实现页面的动画切换
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) {
                    // 使用 FadeTransition 实现淡入淡出效果
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: currentPageWidget, // 当前页面内容
                ),

                // 右上角关闭按钮
                Positioned(
                  top: 12,
                  right: 12,
                  child: _buildCloseButton(context),
                ),

                // 左上角返回按钮 (只在 SelectBoard 页面显示)
                if (_currentPage == AddBoardPageType.selectBoard)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _buildBackButton(context),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
