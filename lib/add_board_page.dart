import 'package:LilygoBox/language.dart';
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
              borderRadius: BorderRadius.circular(10), // 圆角
              // 阴影属性，使弹窗浮出
              boxShadow: [
                BoxShadow(
                  color: const Color.fromARGB(100, 0, 0, 0), // 阴影颜色，透明度可以根据需要调整
                  blurRadius: 30, // 模糊半径
                  spreadRadius: 0,
                ),
              ],
            ),
            // 使用 Stack 确保关闭按钮可以定位
            child: Stack(
              children: [
                // 弹窗内容
                Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 标题
                      Text(
                        context.l10n.addBoard,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: theme.textColorPrimary, // 标题颜色
                        ),
                      ),
                      const SizedBox(height: 10),
                      // 描述
                      Text(
                        context.l10n.addBoardDescription,
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
                        child: Material(
                          color: theme.tertiarytextBackgroundColor,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () {
                              // 实现添加板子的逻辑
                            },
                            borderRadius: BorderRadius.circular(10),
                            // 悬停颜色
                            hoverColor: theme.tertiaryTextHoverColor,
                            // 点击涟漪效果颜色（保持默认或自定义）
                            splashColor: theme.tertiaryTextSplashColor,
                            // 点击高亮颜色
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
                    ],
                  ),
                ),

                // 右上角关闭按钮
                Positioned(
                  top: 12,
                  right: 12,
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHoveringClose = true),
                    onExit: (_) => setState(() => _isHoveringClose = false),
                    child: AnimatedContainer(
                      duration: _animationDuration,
                      width: 33, // 调整尺寸以适应您的主题风格
                      height: 33, // 调整尺寸
                      decoration: BoxDecoration(
                        color: _isHoveringClose
                            ? theme.iconHoverColor
                            : theme.iconBackgroundColor,
                        shape: BoxShape.circle,
                      ),
                      child: Material(
                        color: Colors.transparent, // 确保 Material 背景透明
                        child: InkWell(
                          onTap: () {
                            // 点击关闭按钮，切换回 home 页面
                            widget.windowProvider.setPage(WindowPage.home);
                          },
                          borderRadius: BorderRadius.circular(20.0), // 调整圆角
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
