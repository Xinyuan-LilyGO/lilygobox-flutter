# Flutter 发光效果设计与复用

## 适用范围

电池电量填充和侧栏选中指示灯使用 Flutter 原生 `CustomPainter`、`MaskFilter.blur` 和渐变绘制，不依赖发光插件。效果目标是 LED 灯管：清晰的发光主体、近缘亮光和较宽的柔和扩散光。参考图以深色背景为主，浅色主题上的光晕对比天然较弱，应分别检查两种主题。

## 现有实现

- 电池：`lib/features/devices/presentation/widgets/device_dashboard.dart` 中的 `DeviceBatteryGraphic`、`_BatteryGlowPainter`。
- 电池配色：`lib/features/devices/presentation/widgets/device_battery_colors.dart`，复用 `batteryFillColor`，不修改主题 token 定义。
- 侧栏：`lib/app/shell/widgets/sidebar_navigation_item.dart` 中的 `_SidebarSelectionGlowPainter`，沿用 `basePrimary` 强调色，而非固定为参考图的绿色。

## 绘制顺序与参数

先画不透明轨道背景，再画宽柔光、窄亮光，最后画主体及少量高亮。若把光晕放在不透明背景后面，内部扩散光会被遮住。仅用普通阴影不容易得到清晰的发光核心。

| 项目 | 电池 | 侧栏灯管 |
| --- | --- | --- |
| 宽柔光 Gaussian sigma / alpha | 18 / 0.35 | 12 / 0.68 |
| 近缘光 Gaussian sigma / alpha | 6 / 0.65 | 5 / 0.95 |
| 主体 | 上下轻微明度渐变 | 12 × 30 半胶囊灯条，半宽 6，向左偏移 2 后可见宽度 4 |
| 辅助高亮 | 1 像素内缘 | 不绘制内部灯芯 |

`MaskFilter.blur` 的 sigma 与 `BoxShadow.blurRadius` 不是同一个参数，调参时不要直接照搬数值。先调光晕范围，再调透明度，最后微调主体明度。

电池使用原色的 HSL 色相，饱和度设为 0.72，渐变明度为 0.58 → 0.53。大量混白会产生粉绿色；饱和度 0.95 又过于荧光，所以当前采用折中值。低于 10% 保留警告红色，不绘制绿色光晕。零电量不绘制填充。

侧栏沿用主题强调色，灯条位于侧栏最左边界，左侧裁切、右侧圆弧，采用顶部亮边和向下偏移的低透明度阴影，选中项使用主题中性选中底色；可点击时由 MenuItemSurface 提供悬停变色，不可点击时保持选中底色；不绘制选中行描边，使灯条与选中背景关联。光效层使用 `IgnorePointer`，不拦截点击，也不增加重复语义。

## 布局与裁剪踩坑

- 没有 child 的 `CustomPaint` 在宽度约束不确定时可能得到零宽度，整个电池会消失。当前使用 `SizedBox(width: double.infinity, height: height)`，调用方须提供有限可用宽度。
- 光晕应允许超出绘图区；避免给整个绘图套 `ClipRRect`。需要裁剪填充时，只裁剪主体，不能把扩散光一起截断。还需检查祖先的裁剪行为。
- 光晕只影响绘制，不应靠扩大布局 padding 制造，避免改变卡片大小。
- 概览和电池详情当前最大宽度 276、高度 116；窄窗口由可用宽度限制。两处调用应同步修改，构造函数默认高度仍为 52。
- 百分比和时间取消 `FittedBox`，数字字号 36、字重 600，说明文字字号 20。预留高度为系统文字缩放后的 44，单行溢出省略，避免时长变化引起卡片高度跳动。

## 下次复用和验证

复用现有绘制流程，按物体尺寸调整 sigma，颜色从既有主题字段派生。`shouldRepaint` 比较电量和实际使用的颜色，使设备状态变化和主题过渡能重新绘制。不要为静态光晕新增持续运行的动画。

检查浅色和深色主题、窄窗口、文字缩放、0% / 低电量 / 满电量，以及选中状态和点击行为。运行 `flutter analyze --no-pub lib`；修改 Dart 后必须在运行会话触发 `r`，涉及初始化和状态注册时使用 `R`。

官方参考：

- [MaskFilter.blur](https://api.flutter.dev/flutter/dart-ui/MaskFilter/MaskFilter.blur.html)
- [CustomPainter](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html)
