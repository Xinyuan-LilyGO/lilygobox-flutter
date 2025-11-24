/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-21 15:43:04
 * @LastEditTime: 2025-11-24 14:37:59
 * @License: GPL 3.0
 */
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

    // 如果是未配对状态，只显示简化内容
    if (widget.connectionStatus == ConnectionStatus.unpaired) {
      return _buildUnpairedContent(theme, context);
    }

    // 其他状态显示完整界面
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 主列靠左对齐
      children: [
        // 标题区域 - 使用 SizedBox.expand 确保铺满全宽
        SizedBox(
          width: double.infinity, // 确保宽度铺满
          height: 110,
          child: _buildHeaderWithBackground(theme),
        ),

        const SizedBox(height: 5),

        // 设备状态标题 - 保持对齐
        Padding(
          padding: const EdgeInsets.only(left: 35, right: 30, bottom: 5),
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
            color: theme.tertiaryTextBackgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              // 设备图标和状态
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _getStatusColor(theme).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _getStatusColor(theme).withValues(alpha: 0.3),
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
                    Text(
                      _getStatusText(),
                      style: TextStyle(
                        fontSize: 15,
                        color: theme.textColorSecondary,
                      ),
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
      child: Stack(
        children: [
          // 背景容器 注释保留
          // Container(
          //   width: double.infinity,
          //   height: 110,
          //   decoration: const BoxDecoration(
          //     color: Color.fromARGB(255, 126, 109, 202),
          //   ),
          // ),

          // 标题内容
          Padding(
            padding: const EdgeInsets.only(top: 22, left: 35, right: 30),
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
                  ),
                ),
              ],
            ),
          ),

          // 底部渐变虚化效果 注释保留
          // Positioned(
          //   bottom: -1,
          //   left: 0,
          //   right: 0,
          //   child: Container(
          //     height: 30, // 调整渐变区域的高度
          //     decoration: BoxDecoration(
          //       gradient: LinearGradient(
          //         begin: Alignment.topCenter,
          //         end: Alignment.bottomCenter,
          //         colors: [
          //           const Color.fromARGB(0, 126, 109, 202), // 完全透明
          //           theme.tertiary, // 或者使用 theme.primary，根据下方背景色调整
          //         ],
          //         stops: const [0.0, 1.0], // 可以调整这些值来控制渐变的过渡
          //       ),
          //     ),
          //   ),
          // ),
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

  // 未配对状态的内容 - 简化版，只保留必要元素
  Widget _buildUnpairedContent(AppTheme theme, BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 150),

          // 未配对图标
          Icon(Symbols.devices_off, size: 64, color: theme.textColorTertiary),

          const SizedBox(height: 5),

          // 未配对字样 - 恢复之前的样式
          Text(
            "设备未配对",
            style: TextStyle(
              fontSize: 18,
              color: theme.textColorSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),

          Text("请先配对设备以建立连接", style: TextStyle(color: theme.textColorTertiary)),
          const SizedBox(height: 20),

          // 配对按钮 - 整个按钮可触发
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30), // 左右边距
            child: Container(
              width: 600, // 让容器宽度填满可用空间
              height: 70,
              decoration: BoxDecoration(
                color: theme.tertiaryTextBackgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  hoverColor: theme.basePrimary,
                  // highlightColor: Colors.transparent,
                  // splashColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onPair, // 整个按钮区域都可触发
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(width: 30),
                      Icon(
                        Symbols.connect_without_contact,
                        size: 40,
                        color: theme.iconColor,
                      ),
                      const SizedBox(width: 15),
                      Text(
                        "配对设备",
                        style: TextStyle(
                          fontSize: 17,
                          color: theme.textColorPrimary,
                        ),
                      ),
                      // 添加Spacer将箭头推到最右边
                      const Spacer(),
                      // 朝右的箭头图标
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 20,
                        color: theme.iconColor,
                      ),
                      const SizedBox(width: 20),
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
        return theme.basePrimary;
      case ConnectionStatus.disconnected:
        return theme.basePrimary;
      case ConnectionStatus.connected:
        return Colors.green;
    }
  }

  // 获取状态文本
  String _getStatusText() {
    switch (widget.connectionStatus) {
      case ConnectionStatus.unpaired:
        return "未配对";
      case ConnectionStatus.disconnected:
        return "未连接";
      case ConnectionStatus.connected:
        return "已连接";
    }
  }
}
