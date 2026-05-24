import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../../app/navigation/app_navigation_provider.dart';
import '../../../../../core/l10n/language_provider.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/theme_provider.dart';
import '../../../../../core/widgets/animated_circle_icon_button.dart';
import '../../../../../core/widgets/vscode_settings.dart';

class TGlassesP4SettingsSplitView extends StatefulWidget {
  const TGlassesP4SettingsSplitView({super.key});

  @override
  State<TGlassesP4SettingsSplitView> createState() =>
      _TGlassesP4SettingsSplitViewState();
}

class _TGlassesP4SettingsSplitViewState
    extends State<TGlassesP4SettingsSplitView> {
  // 菜单项的键（不变的），用于 _selectedTitle 和 _contentMap
  static const String _generalKey = 'general';

  // 当前选中的菜单项的 key
  String _selectedTitleKey = _generalKey;

  // 映射菜单项的 key 到一个唯一的数字 ID，用于 _buildContent 的 switch 语句
  final Map<String, int> _contentMap = {_generalKey: 0};

  // 用于存储每个菜单项当前 Hover 颜色的 Map
  late Map<String, Color> _currentHoverColors;

  @override
  void initState() {
    super.initState();
    // 初始化 Hover 颜色 Map，使用固定的 key
    _currentHoverColors = {_generalKey: Colors.transparent};
  }

  // 颜色渐变的持续时间
  static const Duration _animationDuration = Duration(milliseconds: 150);

  /// 根据当前选中的键返回对应的设置内容 Widget
  Widget _buildContent(dynamic theme) {
    final selectedIndex = _contentMap[_selectedTitleKey] ?? 0;

    switch (selectedIndex) {
      case 0: // 通用设置
        return _buildGeneralSettingsContent(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  // 通用设置内容
  Widget _buildGeneralSettingsContent(AppTheme theme) {
    return VscodeSettingsPage(
      theme: theme,
      title: '通用',
      children: [
        VscodeSettingsRow(
          theme: theme,
          title: 'device_name',
          description: '设备在列表和窗口标题中显示的名称',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value: 'T-Glasses-P4',
          ),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'device_id',
          description: '设备唯一识别 ID',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value: 'TGLS-P4-20241119',
          ),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'hardware_version',
          description: '当前连接设备的硬件版本',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(theme: theme, value: 'Rev 2.1'),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'firmware_version',
          description: '设备固件版本',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(theme: theme, value: 'v1.2.3'),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'serial_number',
          description: '设备序列号',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value: 'SN-TGLS-P4-001',
          ),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'uptime',
          description: '设备当前运行时间',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value: '12小时 34分钟',
          ),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'cpu_usage',
          description: '设备当前 CPU 使用率',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(theme: theme, value: '24%'),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'memory_usage',
          description: '设备当前内存占用',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value: '256MB / 512MB',
          ),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'storage_space',
          description: '设备当前存储占用',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value: '1.2GB / 4GB',
          ),
        ),
      ],
    );
  }

  // 构建菜单项列表 - 只保留基础分类和通用项
  List<Map<String, dynamic>> _buildMenuItems(BuildContext context) {
    return [
      {'type': 'header', 'title': context.l10n.basic},
      {'type': 'item', 'title': context.l10n.general, 'key': _generalKey},
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 监听主题变化，但只在主题真正变化时重置悬停颜色
    final newTheme = Provider.of<ThemeProvider>(
      context,
      listen: true,
    ).themeData;

    // 只有当主题变化时才更新悬停颜色
    if (_lastTheme != newTheme) {
      _lastTheme = newTheme;

      // 重置所有非选中项的悬停颜色为主题的主色
      setState(() {
        _currentHoverColors.updateAll((key, value) {
          // 如果是选中项，保持选中颜色；否则重置为主题主色
          return key == _selectedTitleKey
              ? value // 保持选中项的颜色不变
              : newTheme.primary;
        });
      });
    }
  }

  // 添加一个变量来追踪上次的主题
  AppTheme? _lastTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: true).themeData;
    final menuItems = _buildMenuItems(context);

    return Container(
      color: theme.primary, // 覆盖整个背景
      child: Row(
        children: [
          // 左侧：设置菜单导航 - 覆盖左侧边栏区域
          Container(
            width: 250,
            color: theme.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题：板子设置
                Padding(
                  padding: const EdgeInsets.fromLTRB(15.0, 15.0, 15.0, 5.0),
                  child: Text(
                    context.l10n.deviceSettings,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: theme.textColorPrimary,
                    ),
                  ),
                ),

                // 滚动菜单列表
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 5.0),
                    itemCount: menuItems.length,
                    itemBuilder: (context, index) {
                      final item = menuItems[index];

                      if (item['type'] == 'divider') {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8.0,
                            horizontal: 15.0,
                          ),
                          child: Divider(color: theme.dividerColor, height: 1),
                        );
                      }

                      if (item['type'] == 'header') {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(
                            15.0,
                            10.0,
                            10.0,
                            5.0,
                          ),
                          child: Text(
                            item['title'],
                            style: TextStyle(
                              color: theme.textColorTertiary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }

                      // 设置项 (type: 'item')
                      final title = item['title'] as String;
                      final key = item['key'] as String;
                      final isSelected = key == _selectedTitleKey;

                      // 计算目标背景色
                      final targetColor = isSelected
                          ? theme.primaryTextSelectedColor
                          : _currentHoverColors[key] ?? theme.primary;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15.0,
                          vertical: 2.0,
                        ),
                        child: TweenAnimationBuilder<Color?>(
                          duration: _animationDuration,
                          tween: ColorTween(
                            begin: theme.primary,
                            end: targetColor,
                          ),
                          builder: (context, color, child) {
                            return SizedBox(
                              height: 30.0,
                              child: InkWell(
                                onHover: (isHovering) {
                                  if (!isSelected) {
                                    setState(() {
                                      _currentHoverColors[key] = isHovering
                                          ? theme.primaryTextHoverColor
                                          : theme.primary;
                                    });
                                  }
                                },
                                onTap: () {
                                  setState(() {
                                    _selectedTitleKey = key;
                                    _currentHoverColors.updateAll(
                                      (k, value) => theme.primary,
                                    );
                                  });
                                },
                                borderRadius: BorderRadius.circular(6.0),
                                child: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10.0,
                                    vertical: 0.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(6.0),
                                  ),
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      color: theme.textColorSecondary,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // 右侧：设置详细内容
          Expanded(
            child: Container(
              color: theme.secondary,
              child: Stack(
                children: [
                  // 内容区
                  Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: Container(
                        key: ValueKey<String>(_selectedTitleKey),
                        child: _buildContent(theme),
                      ),
                    ),
                  ),

                  // 关闭按钮
                  Positioned(
                    top: 20,
                    right: 20,
                    child: AnimatedCircleIconButton(
                      icon: Symbols.close_rounded,
                      theme: theme,
                      size: 40,
                      iconSize: 22,
                      onPressed: () =>
                          context.read<AppNavigationProvider>().goHome(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
