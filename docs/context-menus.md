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

## 菜单宽度

画布智能体卡片和聊天底部「上下文已用」的右键菜单启用 `fitWidthToItems`。
最小宽度为 150 逻辑像素，与「全选」文本菜单一致，短标签右侧仍保留留白。
长标签按当前语言、实际字体和文字缩放测量，以最宽菜单项为准，只加上图标、勾选标记和必要留白；
最长标签无尾部标记时距面板右侧约 13 逻辑像素（不含滚动条通道）。
仅可用窗口宽度不足时才用省略号，不换行，菜单项高度仍为 28 逻辑像素。
其他菜单保持原有宽度策略。

## 动画和定位

画布智能体卡片把存储操作和工作流关系分别放入一级子菜单。鼠标悬停或点击分类即可展开，靠近窗口边缘时自动换侧并限位；根菜单和子菜单按各自内容计算高度。在支持的最小窗口尺寸内，所有菜单项都应完整可见，不通过滚动条访问命令。空白画布菜单和文本选择菜单不受此分组影响。角色卡不放在右键菜单，更换和解绑使用聊天页右上角的「角色卡」菜单，导入使用设置里的角色卡库。

两层菜单面板之间保留 8 逻辑像素，鼠标跨过间隙时子菜单保持展开。左键再点已展开的分类不执行操作，子菜单保持展开。移动到一级菜单的普通操作时收起子菜单，旧分类恢复默认底色，不因焦点残留显示灰底；分类处于悬停或展开状态时，文字、图标和箭头统一使用主题的高亮前景色。

右键菜单打开后，左键点击触发控件自身（包括图片）或菜单外部均应关闭菜单。`MenuAnchor` 将锚点视为内部区域，因此公共构建器在锚点的原始指针按下事件中主动关闭菜单，并保留控件原有左键操作；不能仅依赖外部点击关闭。再次右键按下先关闭旧菜单，松手后在新位置重新打开。

可选择文本区域内的图片独占右键手势：按下时关闭已有的文本菜单，松手后只打开图片菜单。按住右键不会先弹出「全选」，图片旁的正文保留原有文本选择菜单。

页面内公共菜单的一级和二级面板使用 `PopupMenuTransition` 的 150 毫秒淡入与轻微展开。文本选择工具栏
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
