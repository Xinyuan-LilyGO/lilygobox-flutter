# Windows 剪贴板历史粘贴

Windows 剪贴板历史通过 Win+V 打开系统面板。Flutter Windows runner 对面板合成的 Ctrl+V 按键序列存在映射问题：Ctrl 被提前释放，导致文本框收不到有效的粘贴快捷键。

`lib/core/window/windows_clipboard_history_paste.dart` 在应用启动时修正这一特定序列，再交由 Flutter 原有键盘和文本编辑流程处理。Flutter 不同版本的异常事件序列有差异，当前兼容 Flutter 3.35 的旧序列以及较新版本中包含独立 V 键事件的序列。标准 `TextField`、`TextFormField` 及共享设置输入框都会自动支持，不需要逐个包装。

安装入口仍在 `main()`，实际注册延后到首帧结束。Flutter 3.35 的 `ServicesBinding` 会在异步同步键盘状态后设置 `PlatformDispatcher.onKeyData`；紧接着 `ensureInitialized()` 同步安装会因回调尚未就绪而跳过，或被后续初始化覆盖。不要改回同步注册。回归测试覆盖了回调延迟就绪的启动过程。

兼容处理只改写已知的异常序列。普通按键和 Flutter 使用的全零传输模式探测事件原样转发；应用不会读取、保存或管理 Windows 的剪贴板历史内容。

根因跟踪：[Flutter #143997](https://github.com/flutter/flutter/issues/143997)。升级 Flutter SDK 后应复测 Win+V；若引擎已修复该序列，可移除此应用层兼容代码和对应启动调用。

## 聊天图片复制与粘贴

- 图片剪贴板统一使用 `lib/core/clipboard/image_clipboard.dart`。Windows 的 PNG/DIB 读写使用 `lilygobox/image_clipboard` 原生通道（`windows/runner/image_clipboard.cpp`）；非 Windows 平台及图片文件 URI 继续通过 `super_clipboard` 读取。附件统一转为 PNG。
- Windows 复制时同时通过 `SetClipboardData` 写入实体化的 PNG、CF_DIBV5、CF_DIB，内存所有权交给系统；不要只依赖 OLE 延迟渲染和应用后续按需提供数据。读取优先 PNG，再尝试 DIBV5/DIB；位图先封装成 BMP 再由 Flutter 转 PNG。原生单项数据和解码后像素数据限制为 64 MiB，避免异常数据造成无界分配。
- `OpenClipboard` 失败时返回 `clipboard_busy`，Dart 最多追加 3 次异步重试，间隔 40/80/120 ms；不要在窗口线程休眠等待。其他错误直接报告。
- 写入标准位图格式使内容可以被 Windows 剪贴板历史识别，但不代表一定被收录。Win+V 历史需要由用户启用，Windows 10 单项上限为 4 MB，大图片仍可能只支持当前剪贴板粘贴；应用不能承诺所有复制图片都会出现在历史记录中。
- Windows runner 的 UI 线程必须使用 `OleInitialize` / `OleUninitialize` 成对初始化与清理。插件通过 `OleGetClipboard` / `OleSetClipboard` 读写图片，仅调用 `CoInitializeEx` 不满足 OLE 剪贴板的要求。
- 聊天编辑器通过 `Actions` 覆盖 Flutter 的 `PasteTextIntent`，键盘粘贴和图片可用的右键粘贴进入同一流程；不要仅在外层 `Focus.onKeyEvent` 拦截 Ctrl+V，内部文本框可能先消费快捷键。普通输入框继续使用 Flutter 原有文本粘贴。
- 图片菜单写入失败、图片读取失败需要记录错误与堆栈并显示本地化提示，不得静默吞掉异常。无图片时继续正常粘贴文本。
- 新增原生插件或修改 runner 后需要完整停止并重新 `flutter run -d windows`；热重载和热重启都不能更新原生 DLL。完整构建后仍失败时应检查实际异常，不应反复用 clean 代替排查。
