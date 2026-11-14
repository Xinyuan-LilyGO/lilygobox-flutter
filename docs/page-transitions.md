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

## 用时详情内的折叠

总“用时”和内部“模型思考”、工具操作详情使用同一套展开反馈：200 ms 高度展开与透明度淡入，进入曲线 easeOut、退出曲线 easeIn，顶部为展开锚点。内部折叠不得只使用 AnimatedSize，让文字一瞬间出现或消失。稳定的展开/收起 Key 确保正文增量刷新不重播动画。

内部详情退出时保留内容仅用于完成淡出，同时通过 IgnorePointer、ExcludeFocus、ExcludeSemantics 和 SelectionContainer.disabled 隔离交互、焦点、语义与文本选择；动画结束后移除正文。已有选区在点击折叠时清除。系统关闭动画时，内部详情立即切换，不改变箭头、点击范围或滚动条规格。

## 任务画布视图重置

工作流的手动“重置视图”使用 200 ms、easeInOut 的位移与缩放插值，保持画布内容连续可见，不使用淡出替换。首次布局和窗口适配直接定位；用户平移、拖动节点或点击缩放时立即打断正在进行的重置动画。减少动画模式下直接定位，页面销毁时释放动画控制器。
