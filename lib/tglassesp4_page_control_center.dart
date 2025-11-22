/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-21 15:43:04
 * @LastEditTime: 2025-11-22 16:15:44
 * @License: GPL 3.0
 */
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'provider/theme_provider.dart';

class TGlassesP4PageControlCenter extends StatefulWidget {
  final ConnectionStatus connectionStatus;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onPair;
  final VoidCallback onRefresh;

  const TGlassesP4PageControlCenter({
    super.key,
    required this.connectionStatus,
    required this.onConnect,
    required this.onDisconnect,
    required this.onPair,
    required this.onRefresh,
  });

  @override
  State<TGlassesP4PageControlCenter> createState() =>
      _TGlassesP4PageControlCenterState();
}

enum ConnectionStatus {
  unpaired, // 未配对
  disconnected, // 未连接
  connected, // 已连接
}

class _TGlassesP4PageControlCenterState
    extends State<TGlassesP4PageControlCenter> {
  @override
  Widget build(BuildContext context) {
    // 确保 ThemeProvider 在这里是可用的
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 主列靠左对齐
      children: [
        // 标题区域 - 使用 SizedBox.expand 确保铺满全宽
        SizedBox(
          width: double.infinity, // 确保宽度铺满
          height: 120,
          child: _buildHeaderWithBackground(theme),
        ),

        const SizedBox(height: 5),

        // 设备状态标题 - 保持对齐
        Padding(
          padding: const EdgeInsets.only(
            top: 10,
            left: 35,
            right: 30,
            bottom: 5,
          ),
          child: Text(
            "设备状态",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
        ),

        // 状态头部 - 保持原来的左右 margin
        Container(
          padding: const EdgeInsets.all(15),
          margin: const EdgeInsets.only(left: 30, right: 30),
          decoration: BoxDecoration(
            color: theme.secondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // 设备图标和状态
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _getStatusColor(theme).withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _getStatusColor(theme).withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Symbols.developer_board, // 改为 developer_board 图标
                  size: 30,
                  color: _getStatusColor(theme),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 删除设备在线/离线状态标签
                    const SizedBox(height: 8),
                    Text(
                      _getStatusText(),
                      style: TextStyle(color: theme.textColorSecondary),
                    ),
                  ],
                ),
              ),
              // 未连接状态显示刷新按钮
              if (widget.connectionStatus == ConnectionStatus.disconnected)
                IconButton(
                  icon: Icon(Symbols.refresh, color: theme.textColorTertiary),
                  onPressed: widget.onRefresh,
                ),
            ],
          ),
        ),

        // 主要内容区域 - 使用 Expanded 确保填充剩余空间
        Expanded(child: _buildContentByStatus(theme, context)),
      ],
    );
  }

  Widget _buildHeaderWithBackground(AppTheme theme) {
    return SizedBox(
      width: double.infinity,
      height: 120,
      child: Stack(
        children: [
          // 背景容器
          Container(
            width: double.infinity,
            height: 120,
            decoration: const BoxDecoration(
              color: Color.fromARGB(255, 126, 109, 202),
            ),
          ),

          // 标题内容
          Padding(
            padding: const EdgeInsets.only(top: 25, left: 35, right: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "T-Glasses-P4",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: theme.textColorPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "智能眼镜设备",
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.textColorSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // 底部渐变虚化效果
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 30, // 调整渐变区域的高度
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color.fromARGB(0, 126, 109, 202), // 完全透明
                    theme.tertiary, // 或者使用 theme.primary，根据下方背景色调整
                  ],
                  stops: const [0.0, 1.0], // 可以调整这些值来控制渐变的过渡
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 根据连接状态构建内容
  Widget _buildContentByStatus(AppTheme theme, BuildContext context) {
    switch (widget.connectionStatus) {
      case ConnectionStatus.unpaired:
        return _buildUnpairedContent(theme, context);
      case ConnectionStatus.disconnected:
        return _buildDisconnectedContent(theme, context);
      case ConnectionStatus.connected:
        return _buildConnectedContent(theme, context);
    }
  }

  // 未配对状态的内容
  Widget _buildUnpairedContent(AppTheme theme, BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Symbols.devices_off, size: 64, color: theme.textColorTertiary),
          const SizedBox(height: 16),
          Text(
            "设备未配对",
            style: TextStyle(
              fontSize: 18,
              color: theme.textColorSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text("请先配对设备以建立连接", style: TextStyle(color: theme.textColorTertiary)),
          const SizedBox(height: 24),
          // 配对按钮卡片
          Card(
            color: theme.secondary,
            child: Container(
              width: 200,
              padding: const EdgeInsets.all(16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.onPair,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.link,
                        size: 36,
                        color: theme.sidebarSelectedIconColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "配对设备",
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.textColorPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "点击开始配对",
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textColorTertiary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 未连接状态的内容 - 保持居中
  Widget _buildDisconnectedContent(AppTheme theme, BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Symbols.devices_off, size: 64, color: theme.textColorTertiary),
          const SizedBox(height: 16),
          Text(
            "设备未连接",
            style: TextStyle(
              fontSize: 18,
              color: theme.textColorSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "请连接设备以查看详细信息和控制选项",
            style: TextStyle(color: theme.textColorTertiary),
          ),
        ],
      ),
    );
  }

  // 已连接状态的内容 - 删除所有子项
  Widget _buildConnectedContent(AppTheme theme, BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Symbols.check_circle, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            "设备已连接",
            style: TextStyle(
              fontSize: 18,
              color: theme.textColorSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text("设备连接正常", style: TextStyle(color: theme.textColorTertiary)),
        ],
      ),
    );
  }

  // 获取状态颜色
  Color _getStatusColor(AppTheme theme) {
    switch (widget.connectionStatus) {
      case ConnectionStatus.unpaired:
        return theme.sidebarSelectedIconColor;
      case ConnectionStatus.disconnected:
        return theme.sidebarSelectedIconColor;
      case ConnectionStatus.connected:
        return Colors.green;
    }
  }

  // 获取状态文本
  String _getStatusText() {
    switch (widget.connectionStatus) {
      case ConnectionStatus.unpaired:
        return "智能眼镜开发板 • 未配对";
      case ConnectionStatus.disconnected:
        return "智能眼镜开发板 • 未连接";
      case ConnectionStatus.connected:
        return "智能眼镜开发板 • 已连接";
    }
  }
}
