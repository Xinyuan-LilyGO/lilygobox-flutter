/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-17 11:23:58
 * @LastEditTime: 2025-11-17 11:26:49
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_info/package_info_provider.dart';
import '../../../../core/l10n/language_provider.dart';

// 关于内容区域的 Widget
class AboutContent extends StatelessWidget {
  final dynamic theme; // 接受主题数据

  const AboutContent({super.key, required this.theme});

  // 构建关于页面中的信息项 (Item)
  Widget _buildInfoItem(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: theme.textColorTertiary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: theme.textColorSecondary, // 主要颜色用于内容
              fontSize: 16,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packageInfoProvider = Provider.of<PackageInfoProvider>(
      context,
      listen: false,
    );

    return Container(
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.fromLTRB(40.0, 30.0, 40.0, 40.0), // 内部边距
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 主标题
            Text(
              context.l10n.about,
              style: TextStyle(
                color: theme.textColorPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            // 分隔线
            Divider(color: theme.dividerColor, height: 1),

            const SizedBox(height: 20),

            _buildInfoItem(
              context.l10n.version,
              'v${packageInfoProvider.version}',
            ),

            const SizedBox(height: 10),

            _buildInfoItem(
              context.l10n.copyright,
              '${packageInfoProvider.appName} \n'
              '© 2025 LILYGO Corporation${context.l10n.allRightsReserved}',
            ),
          ],
        ),
      ),
    );
  }
}
