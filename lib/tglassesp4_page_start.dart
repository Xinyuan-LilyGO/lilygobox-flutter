/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-21 15:42:49
 * @LastEditTime: 2025-11-21 15:47:44
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'provider/theme_provider.dart';

class TGlassesP4PageStart extends StatelessWidget {
  const TGlassesP4PageStart({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 50),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 50.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 板子名称
              Text(
                "T-Glasses-P4",
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: theme.textColorPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                "智能眼镜开发板",
                style: TextStyle(fontSize: 16, color: theme.textColorSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),

              // 相关资料介绍
              Card(
                color: theme.secondary,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "相关资料",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.textColorPrimary,
                        ),
                      ),
                      const SizedBox(height: 15),
                      _buildInfoItem(theme, "文档", "查看完整技术文档和用户手册"),
                      _buildInfoItem(theme, "示例代码", "获取开发示例和代码模板"),
                      _buildInfoItem(theme, "教程", "学习如何使用 T-Glasses-P4 进行开发"),
                      _buildInfoItem(theme, "社区支持", "获取技术支持和社区帮助"),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 构建信息项
  Widget _buildInfoItem(AppTheme theme, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Symbols.arrow_forward,
            size: 16,
            color: theme.textColorSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.textColorPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
