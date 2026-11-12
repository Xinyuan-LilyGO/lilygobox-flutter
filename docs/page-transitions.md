# 公共页面切换动画

## 同一区域的内容切换

同一卡片、输入区或展开面板内，互相替换的内容页统一复用 `lib/core/widgets/popup_menu_transition.dart` 中的 `PopupMenuPageTransition`，不要在各页面另写一套切换动画。当前用于选择模型与思考强度、权限模式与自定义批准，以及聊天输入框与单次工具批准面板的切换。

- 时长复用 `PopupMenuTransition.duration`，来源为 `InteractionDecoration.animationDuration`，当前为 **150ms**。
- 进入与退出曲线均复用 `InteractionDecoration.animationCurve`，当前为 **线性**。
- 使用纯透明度淡入淡出；不额外改变控件坐标或缩放比例。区域高度由当前页面决定，退出页底部对齐叠放，不以旧页面高度撑开当前内容。
- 根据逻辑页面设置稳定的 `Key`。同一页面的数据刷新不重播切换；待批准请求切换时以请求 ID 区分。不要每帧生成新 Key。
- 退出中的页面由公共组件通过 `IgnorePointer`、`ExcludeFocus` 和 `ExcludeSemantics` 隔离，不能在淡出期间继续接收鼠标、键盘或无障碍操作。
- `MediaQuery.disableAnimationsOf(context)` 为真时，切换时长为零，立即显示目标内容。

切换动画不负责保存业务数据。输入草稿、附件、队列等应由外部控制器或已有状态持有；批准面板显示时释放输入焦点，恢复输入区后不自动抢回焦点。

## 与其他动画的区别

菜单首次打开沿用 `PopupMenuTransition`，包含淡入和轻微高度展开，详见[右键与文本操作菜单](context-menus.md)。不要把菜单打开动画再叠加到同一区域的页面切换上。

需要保留已访问页面状态的应用导航沿用 `RetainedPageStack`，其进入淡入时长为 200ms；隐藏页暂停自身动画并隔离键盘焦点。不要为复用内容切换样式而替换这类页面的状态保留机制。
