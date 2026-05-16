/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-17 11:02:14
 * @LastEditTime: 2025-11-17 11:26:54
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';

// 添加新的语言与地区内容组件
class LanguageAndRegionContent extends StatefulWidget {
  final dynamic theme;

  const LanguageAndRegionContent({super.key, required this.theme});

  @override
  State<LanguageAndRegionContent> createState() =>
      _LanguageAndRegionContentState();
}

class _LanguageAndRegionContentState extends State<LanguageAndRegionContent> {
  // 语言选择器的折叠状态
  bool _isLanguageSelectorExpanded = false;

  // 用于存储语言选项的悬停状态
  final Map<String, Color> _languageHoverColors = {};

  // 当前选中语言的悬停状态
  Color? _currentLanguageHoverColor;

  // 动画持续时间
  final Duration _animationDuration = const Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(
      context,
      listen: true,
    );
    final currentLanguageCode = languageProvider.locale.languageCode;

    // 根据当前的语言代码找到对应的 Map 对象
    final currentLanguageMap = LanguageProvider.supportedLanguages.firstWhere(
      (lang) => lang['code'] == currentLanguageCode,
      orElse: () => {'code': 'en', 'name': 'English', 'nativeName': 'English'},
    );

    return GestureDetector(
      // 捕获点击事件，包括空白区域。
      // HitTestBehavior.translucent 允许 GestureDetector 捕获在子 Widget 上但未被子 Widget 消费的点击，
      // 并且也捕获空白区域的点击。
      behavior: HitTestBehavior.translucent,
      onTap: () {
        // 如果选择器处于展开状态，点击任何空白区域都会收缩它
        if (_isLanguageSelectorExpanded) {
          setState(() {
            _isLanguageSelectorExpanded = false;
            _languageHoverColors.clear(); // 清除悬停状态
            _currentLanguageHoverColor = null; // 清除当前选中语言的悬停状态
          });
        }
        // 如果选择器已收缩，则不执行任何操作
      },
      child: Container(
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.fromLTRB(40.0, 30.0, 40.0, 40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Text(
              context.l10n.languageAndRegion,
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

            // 语言设置区域折叠选择器
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
                        context.l10n.language,
                        style: TextStyle(
                          color: widget.theme.textColorTertiary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.l10n.languageDescription,
                        style: TextStyle(
                          color: widget.theme.textColorSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 40),

                // 右侧语言选择折叠列表
                SizedBox(
                  width: 200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 当前选中的语言显示区域 (可点击展开/折叠)
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
                                _currentLanguageHoverColor =
                                    widget.theme.secondaryTextHoverColor;
                              });
                            },
                            onExit: (_) {
                              setState(() {
                                _currentLanguageHoverColor = null;
                              });
                            },
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isLanguageSelectorExpanded =
                                      !_isLanguageSelectorExpanded;
                                });
                              },
                              child: AnimatedContainer(
                                duration: _animationDuration,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      _currentLanguageHoverColor ??
                                      widget.theme.primary,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          // 语言名称和本地名称紧挨着显示
                                          Flexible(
                                            child: RichText(
                                              overflow: TextOverflow.ellipsis,
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text:
                                                        currentLanguageMap['nativeName']!,
                                                    style: TextStyle(
                                                      color: widget
                                                          .theme
                                                          .textColorPrimary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text:
                                                        " (${currentLanguageMap['name']!})",
                                                    style: TextStyle(
                                                      color: widget
                                                          .theme
                                                          .textColorTertiary,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AnimatedRotation(
                                      turns: _isLanguageSelectorExpanded
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

                      // 语言选项列表 (可折叠)
                      AnimatedContainer(
                        duration: _animationDuration,
                        height: _isLanguageSelectorExpanded
                            ? (LanguageProvider.supportedLanguages.length *
                                  40.0)
                            : 0,
                        child: AnimatedOpacity(
                          duration: _animationDuration,
                          opacity: _isLanguageSelectorExpanded ? 1.0 : 0.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.theme.primary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount:
                                  LanguageProvider.supportedLanguages.length,
                              itemBuilder: (context, index) {
                                final language =
                                    LanguageProvider.supportedLanguages[index];
                                final isSelected =
                                    language['code'] == currentLanguageCode;
                                final isFirst = index == 0;
                                final isLast =
                                    index ==
                                    LanguageProvider.supportedLanguages.length -
                                        1;

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
                                          _languageHoverColors[language['code']!] =
                                              widget
                                                  .theme
                                                  .primaryTextHoverColor;
                                        });
                                      }
                                    },
                                    onExit: (_) {
                                      if (!isSelected) {
                                        setState(() {
                                          _languageHoverColors[language['code']!] =
                                              widget.theme.primary;
                                        });
                                      }
                                    },
                                    child: GestureDetector(
                                      onTap: () {
                                        if (language['code'] !=
                                            currentLanguageCode) {
                                          // 语言切换
                                          languageProvider.changeLanguage(
                                            language['code']!,
                                          );

                                          setState(() {
                                            // 切换语言后，收缩选择器
                                            _isLanguageSelectorExpanded = false;
                                            _languageHoverColors.clear();
                                            _currentLanguageHoverColor = null;
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
                                              : _languageHoverColors[language['code']] ??
                                                    widget.theme.primary,
                                          borderRadius: borderRadius,
                                        ),
                                        child: Row(
                                          children: [
                                            // 语言名称和本地名称紧挨着显示
                                            Expanded(
                                              child: RichText(
                                                overflow: TextOverflow.ellipsis,
                                                text: TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text:
                                                          language['nativeName']!,
                                                      style: TextStyle(
                                                        color: widget
                                                            .theme
                                                            .textColorPrimary,
                                                        fontWeight: isSelected
                                                            ? FontWeight.bold
                                                            : FontWeight.w600,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text:
                                                          " (${language['name']!})",
                                                      style: TextStyle(
                                                        color: widget
                                                            .theme
                                                            .textColorTertiary,
                                                        fontSize: 11,
                                                        fontWeight: isSelected
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                      ),
                                                    ),
                                                  ],
                                                ),
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
}
