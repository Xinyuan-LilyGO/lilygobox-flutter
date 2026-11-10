# 右键与文本操作菜单

## 统一构建入口

应用右键菜单的内容、表面、阴影、悬停状态和动画统一通过
`RightClickMenuBuilder.buildMenuPanel` 构建。带有右键定位行为的控件使用
`RightClickMenuBuilder.buildMenuAnchor`，并在回调中打开对应菜单控制器。

文本输入框和可选择文本通过固定回调 `AppTextSelectionMenu.build` 接入公共菜单：

```dart
TextField(contextMenuBuilder: AppTextSelectionMenu.build)

SelectableText(
  message,
  selectionWidthStyle: ui.BoxWidthStyle.tight,
  contextMenuBuilder: AppTextSelectionMenu.build,
)
```

`ui` 来自 `import 'dart:ui' as ui;`。只读文本的选区绘制约定见 [可复制文本的选区样式](text-selection.md)。
不要在页面内直接使用 Flutter 默认文本工具栏或另行绘制“复制”“全选”等菜单。
公共回调会保留 Flutter 提供的选择、剪贴板操作和平台快捷键，再将菜单项交给
`RightClickMenuBuilder.buildMenuPanel` 绘制。

## 动画和定位

右键菜单打开后，左键点击触发控件自身（包括图片）或菜单外部均应关闭菜单。`MenuAnchor` 将锚点视为内部区域，因此公共构建器在锚点的原始指针按下事件中主动关闭菜单，并保留控件原有左键操作；不能仅依赖外部点击关闭。再次右键按下先关闭旧菜单，松手后在新位置重新打开。

页面内公共菜单使用 `PopupMenuTransition` 的 150 毫秒淡入与轻微展开。文本选择工具栏
已由 Flutter 的选择层处理淡入，因此 `AppTextSelectionMenu` 复用其动画进度，只绘制展开
动画，避免透明度重复叠加。

直接传递 `AppTextSelectionMenu.build` 函数引用，不要在 `build` 中包装成新闭包。Flutter
会用该回调身份维护已打开的选择菜单；每帧创建新闭包可能导致菜单关闭后再次弹出。

## 颜色

菜单通过 `AppTheme` 及 `RightClickMenuBuilder` 的表面颜色参数适配承载背景。控件位于不同
层级时，应传入所在层级的背景并据此派生表面色；不要将某个页面的菜单颜色改成全局固定值。

更新共享菜单样式时，检查普通右键菜单、文本选择菜单、设置下拉菜单和托盘菜单的颜色、
阴影、窗口边界定位以及悬停状态。

Markdown 等跨段落富文本使用 `SelectionArea(contextMenuBuilder: AppTextSelectionMenu.buildRegion, child: ...)`，与 `SelectableText` 共用菜单面板、动画和系统操作，禁止另建默认样式的选择菜单。
