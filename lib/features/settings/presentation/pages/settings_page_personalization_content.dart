/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-17 11:11:13
 * @LastEditTime: 2025-11-17 11:50:09
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/theme_provider.dart';

// 个性化主题设置内容组件
class PersonalizationContent extends StatefulWidget {
  final dynamic theme;

  const PersonalizationContent({super.key, required this.theme});

  @override
  State<PersonalizationContent> createState() => _PersonalizationContentState();
}

class _PersonalizationContentState extends State<PersonalizationContent> {
  // 主题选择器的折叠状态
  bool _isThemeSelectorExpanded = false;

  // 用于存储主题选项的悬停状态
  final Map<ThemeType, Color> _themeHoverColors = {};

  // 当前选中主题的悬停状态
  Color? _currentThemeHoverColor;

  // 动画持续时间
  final Duration _animationDuration = const Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: true);
    final currentThemeType = themeProvider.currentTheme;

    return GestureDetector(
      // 捕获点击事件，包括空白区域
      behavior: HitTestBehavior.translucent,
      onTap: () {
        // 如果选择器处于展开状态，点击任何空白区域都会收缩它
        if (_isThemeSelectorExpanded) {
          setState(() {
            _isThemeSelectorExpanded = false;
            _themeHoverColors.clear(); // 清除悬停状态
            _currentThemeHoverColor = null; // 清除当前选中主题的悬停状态
          });
        }
      },
      child: Container(
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.fromLTRB(40.0, 30.0, 40.0, 40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Text(
              context.l10n.personalization,
              style: TextStyle(
                color: widget.theme.textColorPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            // 分隔线
            Divider(color: widget.theme.dividerColor, height: 1),

            const SizedBox(height: 20),

            // 主题设置区域折叠选择器
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧说明 (flex: 2)
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.theme,
                        style: TextStyle(
                          color: widget.theme.textColorTertiary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.l10n.themeDescription,
                        style: TextStyle(
                          color: widget.theme.textColorSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 40),

                // 右侧主题选择折叠列表
                SizedBox(
                  width: 200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 当前选中的主题显示区域 (可点击展开/折叠)
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.theme.primary,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: MouseRegion(
                            onEnter: (_) {
                              setState(() {
                                _currentThemeHoverColor =
                                    widget.theme.secondaryTextHoverColor;
                              });
                            },
                            onExit: (_) {
                              setState(() {
                                _currentThemeHoverColor = null;
                              });
                            },
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isThemeSelectorExpanded =
                                      !_isThemeSelectorExpanded;
                                });
                              },
                              child: AnimatedContainer(
                                duration: _animationDuration,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      _currentThemeHoverColor ??
                                      widget.theme.primary,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          // 当前主题名称
                                          Flexible(
                                            child: Text(
                                              _getCurrentThemeName(
                                                context,
                                                currentThemeType,
                                              ),
                                              style: TextStyle(
                                                color: widget
                                                    .theme
                                                    .textColorPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AnimatedRotation(
                                      turns: _isThemeSelectorExpanded
                                          ? 0.0
                                          : -0.25,
                                      duration: _animationDuration,
                                      curve: Curves.easeInOut,
                                      child: Icon(
                                        Icons.arrow_drop_down,
                                        color: widget.theme.textColorSecondary,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 3),

                      // 主题选项列表 (可折叠)
                      AnimatedContainer(
                        duration: _animationDuration,
                        height: _isThemeSelectorExpanded
                            ? (ThemeType.values.length * 40.0)
                            : 0,
                        child: AnimatedOpacity(
                          duration: _animationDuration,
                          opacity: _isThemeSelectorExpanded ? 1.0 : 0.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.theme.primary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: ThemeType.values.length,
                              itemBuilder: (context, index) {
                                final themeType = ThemeType.values[index];
                                final isSelected =
                                    themeType == currentThemeType;
                                final isFirst = index == 0;
                                final isLast =
                                    index == ThemeType.values.length - 1;

                                // 根据位置设置不同的圆角
                                BorderRadius borderRadius = BorderRadius.zero;
                                if (isFirst && isLast) {
                                  // 只有一个选项时
                                  borderRadius = BorderRadius.circular(5);
                                } else if (isFirst) {
                                  // 第一个选项
                                  borderRadius = const BorderRadius.only(
                                    topLeft: Radius.circular(5),
                                    topRight: Radius.circular(5),
                                  );
                                } else if (isLast) {
                                  // 最后一个选项
                                  borderRadius = const BorderRadius.only(
                                    bottomLeft: Radius.circular(5),
                                    bottomRight: Radius.circular(5),
                                  );
                                }
                                // 中间选项保持 BorderRadius.zero（无圆角）

                                return Material(
                                  color: Colors.transparent,
                                  child: MouseRegion(
                                    onEnter: (_) {
                                      if (!isSelected) {
                                        setState(() {
                                          _themeHoverColors[themeType] = widget
                                              .theme
                                              .primaryTextHoverColor;
                                        });
                                      }
                                    },
                                    onExit: (_) {
                                      if (!isSelected) {
                                        setState(() {
                                          _themeHoverColors[themeType] =
                                              widget.theme.primary;
                                        });
                                      }
                                    },
                                    child: GestureDetector(
                                      onTap: () {
                                        if (themeType != currentThemeType) {
                                          // 主题切换
                                          themeProvider.setTheme(themeType);

                                          setState(() {
                                            // 切换主题后，收缩选择器
                                            _isThemeSelectorExpanded = false;
                                            _themeHoverColors.clear();
                                            _currentThemeHoverColor = null;
                                          });
                                        }
                                      },
                                      child: AnimatedContainer(
                                        duration: _animationDuration,
                                        height: 40,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10.0,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? widget
                                                    .theme
                                                    .primaryTextSelectedColor
                                              : _themeHoverColors[themeType] ??
                                                    widget.theme.primary,
                                          borderRadius: borderRadius,
                                        ),
                                        child: Row(
                                          children: [
                                            // 主题名称
                                            Expanded(
                                              child: Text(
                                                _getThemeName(
                                                  context,
                                                  themeType,
                                                ),
                                                style: TextStyle(
                                                  color: widget
                                                      .theme
                                                      .textColorPrimary,
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isSelected)
                                              Icon(
                                                Icons.check,
                                                size: 16,
                                                color: widget
                                                    .theme
                                                    .textColorPrimary,
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
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 获取当前主题的名称
  String _getCurrentThemeName(BuildContext context, ThemeType themeType) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final themeData = themeProvider.allThemes.firstWhere(
      (theme) => theme.type == themeType,
    );
    return themeData.getName(context.l10n);
  }

  // 获取主题名称
  String _getThemeName(BuildContext context, ThemeType themeType) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final themeData = themeProvider.allThemes.firstWhere(
      (theme) => theme.type == themeType,
    );
    return themeData.getName(context.l10n);
  }
}
