import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart';
import 'window.dart';

class AddBoardPage extends StatefulWidget {
  final WindowProvider windowProvider;

  const AddBoardPage({super.key, required this.windowProvider});

  @override
  State<AddBoardPage> createState() => _AddBoardPageState();
}

class _AddBoardPageState extends State<AddBoardPage> {
  // 用于控制关闭按钮的悬停状态
  bool _isHoveringClose = false;
  final Duration _animationDuration = const Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    // 确保使用正确的方式获取 Provider 的值 (使用 listen: false)
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;
    // 假设 theme 中有 iconHoverColor 和 iconBackgroundColor

    // 使用 Stack 实现模态效果：下层是背景遮罩，上层是居中弹窗
    return Stack(
      children: [
        // 背景遮罩层：变暗且不可触摸 (使用 ModalBarrier 阻止下层交互)
        ModalBarrier(
          // dismissible: false, // 系统提示音
          color: const Color.fromARGB(100, 0, 0, 0), // 半透明黑色
        ),

        // 居中弹窗内容
        Center(
          child: Container(
            width: 400, // 弹窗宽度
            height: 550, // 弹窗高度
            decoration: BoxDecoration(
              color: theme.secondary, // 使用 secondary 作为弹窗背景色
              borderRadius: BorderRadius.circular(15), // 圆角
            ),
            // 使用 Stack 确保关闭按钮可以定位
            child: Stack(
              children: [
                // 弹窗内容
                Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 标题
                      Text(
                        '添加板子',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: theme.textColorPrimary, // 标题颜色
                        ),
                      ),
                      const SizedBox(height: 10),
                      // 描述
                      Text(
                        '这里可以添加开发板，请选择添加开发板的方式',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textColorTertiary, // 描述颜色
                        ),
                      ),
                      const SizedBox(height: 30),
                      // 长条圆角按键
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            // TODO: 实现添加板子的逻辑
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            '通过扫描设备添加',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.primary, // 按钮文字颜色
                            ),
                          ),
                        ),
                      ),
                      // ... 可以添加更多内容
                    ],
                  ),
                ),

                // 右上角关闭按钮
                Positioned(
                  top: 10,
                  right: 10,
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHoveringClose = true),
                    onExit: (_) => setState(() => _isHoveringClose = false),
                    child: AnimatedContainer(
                      duration: _animationDuration,
                      width: 30, // 调整尺寸以适应您的主题风格
                      height: 30, // 调整尺寸
                      decoration: BoxDecoration(
                        color: _isHoveringClose
                            // 假设 theme 中有 iconHoverColor 和 iconBackgroundColor
                            ? theme.iconHoverColor ??
                                  theme
                                      .tertiary // 悬停颜色
                            : theme.iconBackgroundColor ??
                                  Colors.transparent, // 默认背景色
                        shape: BoxShape.circle,
                      ),
                      child: Material(
                        color: Colors.transparent, // 确保 Material 背景透明
                        child: InkWell(
                          onTap: () {
                            // [修改]：点击关闭按钮，切换回 home 页面
                            widget.windowProvider.setPage(WindowPage.home);
                          },
                          borderRadius: BorderRadius.circular(15.0), // 调整圆角
                          child: Center(
                            child: Icon(
                              Symbols.close_rounded,
                              size: 18,
                              color: theme.iconColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
