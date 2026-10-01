/*
 * @Description: 为尚未适配专属界面的设备提供通用占位页面。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

// 通用板子页面内容（用于其他板子类型）
class GenericDevicePageContent extends StatelessWidget {
  final String deviceName;

  const GenericDevicePageContent({super.key, required this.deviceName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.developer_board, size: 64, color: Colors.grey),
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
