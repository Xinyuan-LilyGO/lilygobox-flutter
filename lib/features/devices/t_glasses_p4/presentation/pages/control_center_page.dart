/*
 * @Description: 根据 T-Glasses-P4 的配对和连接状态展示控制中心内容。
 * @Author: LILYGO_L
 * @Date: 2025-11-21 15:43:04
 * @LastEditTime: 2026-10-04 12:33:13
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../../core/l10n/language_provider.dart';
import '../../../../../core/theme/provider.dart';
import '../../../../../core/widgets/app_tooltip.dart';
import '../../../../../core/widgets/interaction_decoration.dart';
import '../../domain/connection_status.dart';

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

class _TGlassesP4PageControlCenterState
    extends State<TGlassesP4PageControlCenter> {
  bool _isPairButtonHovered = false;

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
          padding: const EdgeInsets.only(left: 35, right: 30, bottom: 3),
          child: Text(
            "设备状态",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
        ),

        // 状态头部 - 改为 Card 类型
        Padding(
          padding: const EdgeInsets.only(left: 30, right: 30),
          child: Card(
            elevation: 2,
            color: theme.tertiaryTextBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                    AppTooltip(
                      message: context.l10n.refresh,
                      verticalOffset: 16,
                      child: IconButton(
                        icon: Icon(
                          Symbols.refresh,
                          color: theme.textColorTertiary,
                        ),
                        onPressed: widget.onRefresh,
                      ),
                    ),
                ],
              ),
            ),
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

          // 配对按钮 - 整个按钮可触发（添加悬停效果）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isPairButtonHovered = true),
              onExit: (_) => setState(() => _isPairButtonHovered = false),
              child: SizedBox(
                width: 600,
                height: 70,
                child: InteractionDecoration(
                  palette: theme,
                  decoration: BoxDecoration(
                    color: _isPairButtonHovered
                        ? theme.adaptiveColor(
                            dark: theme.basePrimary,
                            light: Color.alphaBlend(
                              theme.basePrimary.withValues(alpha: 0.22),
                              theme.primary,
                            ),
                          )
                        : theme.tertiaryTextBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      hoverColor: Colors.transparent,
                      // splashColor: Colors.transparent,
                      // highlightColor: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      onTap: widget.onPair,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const SizedBox(width: 25),
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
                          const Spacer(),
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
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 150),
          Icon(Symbols.devices_off, size: 64, color: theme.textColorTertiary),
          const SizedBox(height: 5),
          Text(
            "设备未连接",
            style: TextStyle(
              fontSize: 18,
              color: theme.textColorSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
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
