/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-21 15:43:04
 * @LastEditTime: 2025-11-21 18:26:53
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'provider/theme_provider.dart';

class TGlassesP4PageControlCenter extends StatefulWidget {
  final bool isConnected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const TGlassesP4PageControlCenter({
    super.key,
    required this.isConnected,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  State<TGlassesP4PageControlCenter> createState() =>
      _TGlassesP4PageControlCenterState();
}

class _TGlassesP4PageControlCenterState
    extends State<TGlassesP4PageControlCenter> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 主列靠左对齐
      children: [
        // 标题 - 移到卡片上方
        Padding(
          padding: const EdgeInsets.only(top: 25, left: 35, right: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "T-Glasses-P4",
                style: TextStyle(
                  fontSize: 25, // 增大字体
                  fontWeight: FontWeight.bold,
                  color: theme.textColorPrimary,
                ),
              ),
              Text(
                "智能眼镜",
                style: TextStyle(fontSize: 15, color: theme.textColorSecondary),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 状态头部 - 放在单独的容器中
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
                  color: widget.isConnected
                      ? Colors.green.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.isConnected
                        ? Colors.green.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Symbols.developer_board, // 改为 developer_board 图标
                  size: 30,
                  color: widget.isConnected ? Colors.green : Colors.grey,
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
                      "智能眼镜开发板 • ${widget.isConnected ? '已连接' : '未连接'}",
                      style: TextStyle(color: theme.textColorSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 主要内容区域 - 使用 Expanded 确保填充剩余空间
        Expanded(
          child: widget.isConnected
              ? _buildConnectedContent(theme, context) // 已连接内容
              : _buildDisconnectedContent(theme, context), // 未连接内容
        ),
      ],
    );
  }

  // 已连接状态的内容
  Widget _buildConnectedContent(AppTheme theme, BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // 已连接内容靠左对齐
        children: [
          const SizedBox(height: 24),

          // 快速操作卡片 - 仅在连接时显示
          Text(
            "快速操作",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // 快速操作网格使用响应式布局
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3, // 示例中只有3个卡片
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180, // 设置单个卡片的最大宽度，实现响应式三列/两列切换
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0, // 调整为更接近正方形
            ),
            itemBuilder: (context, index) {
              // 根据索引返回不同的快速操作卡片
              switch (index) {
                case 0:
                  return _buildQuickActionCard(
                    theme,
                    "重启设备",
                    Symbols.restart_alt,
                    Colors.blue,
                    () {},
                  );
                case 1:
                  return _buildQuickActionCard(
                    theme,
                    "更新固件",
                    Symbols.system_update,
                    Colors.purple,
                    () {},
                  );
                case 2:
                  return _buildQuickActionCard(
                    theme,
                    "设备信息",
                    Symbols.info,
                    Colors.green,
                    () {},
                  );
                default:
                  return const SizedBox.shrink();
              }
            },
          ),
          const SizedBox(height: 24),

          // 设备状态网格 - 仅在连接时显示
          Text(
            "设备状态",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // 设备状态网格使用响应式布局
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 6, // 示例中共有6个状态卡片
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350, // 设置单个卡片的最大宽度，实现响应式两列布局
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 3.5, // 调整为更扁平的比例
            ),
            itemBuilder: (context, index) {
              // 根据索引返回不同的状态卡片
              switch (index) {
                case 0:
                  return _buildStatusCard(
                    theme,
                    "连接状态",
                    "已连接",
                    Symbols.check_circle,
                    Colors.green,
                  );
                case 1:
                  return _buildStatusCard(
                    theme,
                    "电池电量",
                    "85%",
                    Symbols.battery_5_bar,
                    Colors.blue,
                  );
                case 2:
                  return _buildStatusCard(
                    theme,
                    "温度",
                    "32°C",
                    Symbols.thermostat,
                    Colors.orange,
                  );
                case 3:
                  return _buildStatusCard(
                    theme,
                    "信号强度",
                    "优秀",
                    Symbols.wifi,
                    Colors.green,
                  );
                case 4:
                  return _buildStatusCard(
                    theme,
                    "固件版本",
                    "v1.2.3",
                    Symbols.info,
                    theme.textColorPrimary,
                  );
                case 5:
                  return _buildStatusCard(
                    theme,
                    "运行时间",
                    "2天14小时",
                    Symbols.timer,
                    Colors.purple,
                  );
                default:
                  return const SizedBox.shrink();
              }
            },
          ),
          const SizedBox(height: 24),

          // 实时数据图表区域 - 仅在连接时显示
          Text(
            "实时监控",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: theme.secondary,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "CPU 使用率",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: theme.tertiary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        "实时图表区域",
                        style: TextStyle(color: theme.textColorTertiary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
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

  // 构建快速操作卡片
  Widget _buildQuickActionCard(
    AppTheme theme,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      color: theme.secondary,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 增大图标尺寸
                Icon(icon, size: 36, color: color),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: TextStyle(
                    // 略微增大字体
                    fontSize: 14,
                    color: theme.textColorPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 构建状态卡片
  Widget _buildStatusCard(
    AppTheme theme,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      color: theme.secondary,
      child: Padding(
        // 增大内边距
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // 增大图标尺寸
            Icon(icon, size: 30, color: color),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14, // 略微增大
                      color: theme.textColorTertiary,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18, // 增大值文本
                      fontWeight: FontWeight.bold,
                      color: theme.textColorPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
