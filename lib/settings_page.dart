import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart';
import 'language.dart';
import 'window.dart';

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
