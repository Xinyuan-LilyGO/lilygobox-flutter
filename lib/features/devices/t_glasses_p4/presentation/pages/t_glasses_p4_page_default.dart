/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-21 15:45:13
 * @LastEditTime: 2025-11-21 15:48:03
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/theme/theme_provider.dart';

class TGlassesP4PageDefault extends StatelessWidget {
  const TGlassesP4PageDefault({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.help_outline, size: 64, color: theme.textColorSecondary),
          const SizedBox(height: 16),
          Text(
            "页面开发中",
            style: TextStyle(fontSize: 18, color: theme.textColorSecondary),
          ),
        ],
      ),
    );
  }
}
