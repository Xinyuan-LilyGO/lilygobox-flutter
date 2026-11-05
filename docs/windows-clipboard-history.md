# Windows 剪贴板历史粘贴

Windows 剪贴板历史通过 Win+V 打开系统面板。Flutter Windows runner 对面板合成的 Ctrl+V 按键序列存在映射问题：Ctrl 被提前释放，导致文本框收不到有效的粘贴快捷键。

`lib/core/window/windows_clipboard_history_paste.dart` 在应用启动时修正这一特定序列，再交由 Flutter 原有键盘和文本编辑流程处理。Flutter 不同版本的异常事件序列有差异，当前兼容 Flutter 3.35 的旧序列以及较新版本中包含独立 V 键事件的序列。标准 `TextField`、`TextFormField` 及共享设置输入框都会自动支持，不需要逐个包装。

兼容处理只改写已知的异常序列。普通按键和 Flutter 使用的全零传输模式探测事件原样转发；应用不会读取、保存或管理 Windows 的剪贴板历史内容。

根因跟踪：[Flutter #143997](https://github.com/flutter/flutter/issues/143997)。升级 Flutter SDK 后应复测 Win+V；若引擎已修复该序列，可移除此应用层兼容代码和对应启动调用。
