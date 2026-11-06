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

不要把每行拆为独立的 `SelectableText`，也不要通过缩小整个消息布局、改变字体或移除换行来模拟选区效果。输入框的编辑选区不属于本规范的只读文本范围。

修改后检查长短行混合、空行、自动折行、中英文内容，以及鼠标拖选、全选、复制和右键菜单；复制结果应保留原有内容和换行。菜单接入见 [右键与文本操作菜单](context-menus.md)。
