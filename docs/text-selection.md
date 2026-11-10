# 可复制文本的选区样式

应用内只读、可选择的文本（AI 对话消息、设备详情、登录验证码等）统一采用贴合每行文字的横向选区：

```dart
import 'dart:ui' as ui;

SelectableText(
  text,
  selectionWidthStyle: ui.BoxWidthStyle.tight,
  contextMenuBuilder: AppTextSelectionMenu.build,
)
```

Flutter 桌面端默认的 `BoxWidthStyle.max` 会把跨行选区扩展至整个文本区域宽度，导致短行右侧出现大片高亮。只读文本应显式指定 `BoxWidthStyle.tight`，不要依赖平台默认值。

此设置只改变高亮区域的横向绘制，不修改内容、换行、文字布局宽度或复制结果。保留连续拖选、跨行选择、全选、Ctrl+C，以及项目统一的右键菜单。文本中实际存在的空格仍属于原文，不能为了缩短选区而删除、裁剪或拆分原文。空行和换行处可能仍有表示换行被选中的窄选区。

不要把每行拆为独立的 `SelectableText`，也不要通过缩小整个消息布局、改变字体或移除换行来模拟选区效果。普通输入框的编辑选区不属于本规范的只读文本范围；AI 多行聊天编辑器同样显式使用 `BoxWidthStyle.tight`，避免短行右侧空白被扩展高亮，真实空格和换行仍保留。

修改后检查长短行混合、空行、自动折行、中英文内容，以及鼠标拖选、全选、复制和右键菜单；复制结果应保留原有内容和换行。菜单接入见 [右键与文本操作菜单](context-menus.md)。

AI Markdown 富文本使用一个 `SelectionArea` 包含所有段落，保留跨段落连续选择；段落由 `Text.rich` 绘制，采用 Flutter 段落贴合文字的选区。不要开启 Markdown 库逐段独立的 `SelectableText` 模式。消息下方的复制按钮复制完整原始 Markdown，选择后复制则复制当前选中的可见文本。

聊天代码块仅在文本超宽时使用独立 `SelectableText` 与横向滚动；可容纳的代码和表格继续参与正文跨段落选区。不要为每个代码块、表格无条件增加横向滚动层，Windows 长消息中这会影响后续内容的鼠标选区定位。

## 点击空白取消选区

聊天正文使用持久的 `FocusNode` 管理只读选区，并通过 `TextFieldTapRegion.onTapOutside` 在左键点击外部空白或其他非文本控件时释放该焦点。Flutter 随焦点离开清除选区，不能只依赖文本内部点击，否则聊天区两侧空白无法取消高亮。用户消息、Markdown 和嵌套的超宽代码块都需要验证。

公共文本右键菜单的实际菜单面板也放在 `TextFieldTapRegion` 内，与正文和输入框使用 Flutter 默认的 `EditableText` 分组，保证点击“复制”“全选”时不会提前清除选区。不要将覆盖整个窗口的菜单定位层加入分组，否则菜单打开后，窗口空白也会被当成文本内部。只处理外部左键按下，不在鼠标移动、拖选过程或右键按下时强制清除；普通输入框继续使用自身的焦点和编辑选区逻辑。
