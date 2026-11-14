/*
 * @Description: 为尚未适配专属界面的设备提供通用占位页面。
 */

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

// 通用板子页面内容（用于其他板子类型）
class GenericDevicePageContent extends StatelessWidget {
  final String deviceName;
  final IconData icon;

  const GenericDevicePageContent({
    super.key,
    required this.deviceName,
    this.icon = Symbols.link,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            '$deviceName 页面',
            style: const TextStyle(fontSize: 24, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            '这是 $deviceName 的通用页面',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
