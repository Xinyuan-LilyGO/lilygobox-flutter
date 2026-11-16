# Flutter 稳定版升级与画布性能验证

本轮使用官方 Flutter 3.50.0 stable、Dart 3.14.0。项目约束同步升级，不通过 window_manager legacy API 保留旧实现。Material 组件迁移到 material_ui，新旧第三方 Material 组件需要同时安装对应本地化委托。sqlite3 和自有压缩绑定使用 code assets，移除 sqlite3_flutter_libs。

依赖更新到当前共同可解析的稳定版本。super_clipboard 0.9.1 的依赖范围仍阻挡 package_info_plus 10 和 flutter_secure_storage 11 等版本，不能用 dependency_overrides 假装全部兼容。

## 性能回归经验

使用 profile 模式、实际 Windows 窗口和 25 个智能体，测量右键平移、Ctrl+滚轮缩放及左键框选。测试入口为 integration_test/workflow_performance_test.dart；主机驱动为 test_driver/workflow_performance.dart。生产应用和测试入口都必须覆盖 configureDesktopWindow，单独的画布测试不能发现透明窗口启动兼容问题。

点阵背景原先逐点 drawCircle，新版 Impeller 下会出现大量绘制开销。现在使用 Float32List + drawRawPoints 一次批量绘制，维持 24px 场景间距、缩放补偿和圆点外观。

本机完整窗口测试：逐点背景平均光栅化 56.5ms；批量点阵平均 4.59ms、P99 6.53ms、最差 6.71ms；201 帧中构建和光栅化均未超过 60Hz 预算。数据只代表当前机器和固定场景，不能证明所有设备、负载和高刷新率场景都没有掉帧，更不能追溯证明用户之前升级的具体原因。

实验中 Skia 的独立画布性能较好，但真实应用透明窗口会触发引擎原生崩溃，因此未保留关闭 Impeller 的实验代码。不要仅凭单个基准切换正式应用渲染器。普通圆角窗口的 Clip.antiAliasWithSaveLayer 用于遮罩和圆角边缘正确合成，相关像素回归在 dialog_boundary_test.dart。最大化／贴屏时圆角已归零，此时保留 ClipRRect 节点但改用 Clip.hardEdge，避免无意义的整屏离屏合成。

升级后必须执行 lib 静态检查、存储与画布回归、真实窗口启动、正式构建，再检查实际应用而非只看编译成功。

## Windows 主题切换与隐藏托盘窗口

本机在切换主题时捕获到 flutter_windows.dll 的 0xc0000005，符号定位到 ANGLE 的 rx::StateManager11::updateState。独立集成测试可通过反复向隐藏托盘菜单发送主题更新复现。Flutter 官方 issue [#152299](https://github.com/flutter/flutter/issues/152299) 也有相近的多窗口函数栈，但不能仅凭函数名认定是完全相同的引擎缺陷。

最终改为托盘菜单独立辅助进程：Windows 入口在单实例检测和主应用初始化之前识别内部启动参数，只运行 trayMain。主进程与辅助进程通过有大小上限的 WM_COPYDATA 传递菜单文案、主题及打开／关闭指令，并校验宿主窗口和辅助进程身份；显示窗口和退出操作仍由主进程执行。辅助进程不初始化数据库、聊天、密钥、设备或账号。

菜单在首次配置后安排一次延迟预热，并复用辅助进程与菜单窗口；主窗口通过 Windows Job Object 绑定辅助进程生命周期，辅助进程同时监测主进程退出。预热通过异步消息创建透明但可见的宿主 surface，在可绘制状态完成首帧，Dart 返回带 requestId 的 prepared 后才隐藏；不依赖隐藏窗口绘制。预热期间的右键只记录打开意图，收到 prepared 后再发送 open，避免同步 IPC 在引擎初始化时超时；用户打开菜单仍等待 painted 后淡入。预热确认与用户打开请求通过 requestId 隔离，迟到的预热确认不能隐藏已打开的菜单。预热期间的主题配置与隐藏时的外观更新只缓存，不触发隐藏 surface 绘制。辅助进程不继承主引擎的调试 VM 端口及 start-paused 参数。保留主窗口 Impeller、主题渐变、菜单样式，不保留切换渲染器和线程策略的实验代码。单独关闭隐藏重绘／预热不足以解决打开菜单时的崩溃，不能当作最终方案。

Windows 回归 integration_test/tray_theme_test.dart 连续切换主题并重新打开菜单 20 次，每次确认菜单实际 painted 且辅助进程存活；驱动为 test_driver/tray_theme.dart。

完整应用回归 integration_test/theme_switch_test.dart 通过实际 AppProviders 连续切换主题 20 次，覆盖主窗口渐变、托盘同步及菜单重新打开；使用同一 test_driver/tray_theme.dart 运行。两项 Windows 集成回归及主题卡片、托盘组件测试均通过。主题卡片测试显式设置初始深色，避免依赖默认主题导致无效的重复选中断言。

正式 release 另用 integration_test/theme_release_smoke.dart 验证，不依赖 VM service：真实应用连续切换主题、打开／关闭菜单 20 次，确认每次菜单绘制完成，结果写到 tmp/theme-release-result.json，最后走正常退出保存流程。本机最终结果 passed=true，退出后没有遗留菜单辅助进程。首次打开位置在主进程捕获并随 IPC 传递，避免冷启动期间鼠标移动使菜单跑偏；菜单初始化失败会通知主进程恢复窗口。

## 升级窗口库后的双重阴影

window_manager 0.7／nativeapi 的无边框窗口默认仍有原生阴影；隐藏标题栏并调用 setFrameless(true) 时，库会创建轮廓阴影。应用已有 AppWindowFrame 的自绘阴影，叠加后会形成很重的黑边。configureDesktopWindow 必须显式设置 window.hasShadow = false，保留自绘阴影参数和圆角裁剪。不要通过减淡自绘阴影掩盖双重绘制。Windows 原生状态回归：integration_test/window_shadow_test.dart，检查首次和重复初始化后 hasShadow 都为 false。


## 系统文件窗口打开时原生标题栏重新出现

IFileDialog 打开时会禁用宿主窗口并触发 WM_NCACTIVATE。新版窗口库隐藏标题栏时仍保留 WS_CAPTION，用于 Windows 贴靠；其激活消息最终交给默认窗口过程，宿主被禁用时可能重新画出经典标题栏。主窗口的原生消息处理现在直接消费 WM_NCACTIVATE、WM_NCPAINT 和非客户区主题绘制消息，禁止系统绘制标题栏，保留原有窗口样式与自绘外框。

Windows 回归 integration_test/modal_window_frame_test.dart 使用真实 HWND，先断言顶部像素确实为测试背景色，再禁用／失活窗口比较像素，并实际打开保存、打开文件和选择文件夹对话框，在独立 isolate 中确认宿主被禁用、采样顶部像素并取消对话框，最后检查恢复后的像素。修复前禁用／失活测试可复现系统标题栏覆盖；修复后通过。注意 nativeapi 0.6.1 的 Windows GetNativeNumber 返回 0，不能将其当作 HWND，否则 GetWindowDC(0) 会采样桌面，产生无效的通过结果。

### 窗口最大化与贴靠状态同步

窗口操作前读取 nativeapi 的实时 `isMaximized`，不能仅依赖异步窗口事件更新的缓存；连续最大化/还原与系统先改变状态的情况需回归。Windows 贴靠状态可能晚于最后一次移动/缩放事件提交，原生端在 `WM_EXITSIZEMOVE`、`WM_SIZE`、`WM_MOVE` 后通过合并的下一轮消息通知 `layoutChanged`，Flutter 收到后重新设置圆角和窗口留白，避免贴靠左侧后仍保留普通窗口外框。普通恢复时重新显示圆角和自绘阴影。


### 托盘隐藏图标面板中的右键菜单

菜单宿主收到 `WM_COPYDATA open` 后先确认命令已复制，再通过下一条消息创建或显示 Flutter 菜单，避免同步 IPC 的 1 秒期限把首次引擎启动误判为失效。主窗口检查 IPC 是否收到确认；打开菜单期间设置 15 秒首帧期限，未完成时记录原生诊断并恢复主窗口可达性，不终止仍在正常初始化的辅助进程。

前台窗口变化的关闭规则须区分 Explorer 的任务栏和隐藏图标弹出层：已识别的托盘表面之间切换不关闭菜单，切换到普通应用窗口、外部点击和 Esc 仍关闭。不得通过忽略所有 Explorer 窗口或删除失焦关闭规则来掩盖问题。此路径涉及 Windows 原生 runner，热重载不能加载修改；真实隐藏图标面板交互需要在重新编译的 Windows 应用中验证。


### 窗口状态切换时的极小客户区与无障碍错误

Windows 最小化窗口可能暴露图标大小的客户区。`Win32Window::MessageHandler` 的 `WM_SIZE` 分支在 `SIZE_MINIMIZED` 时保留 Flutter child 原有尺寸，客户区宽度或高度不大于零时也不执行 `MoveWindow`；正常恢复和最大化仍按实际客户区调整。不要跳过 `FlutterWindow` 传递给引擎的窗口生命周期消息。

本次日志中的根布局仅收到 179×14 的尺寸，无法容纳 30 高的标题栏，产生底部溢出 16px。上述修改针对最小化期间不必要的极小布局；已经通过 C++ 语法检查，真实窗口切换需使用重新编译后的程序验证。

`accessibility_bridge.cc` 的 `Failed to update ui::AXTree ... will not be in the tree and is not the new root` 需要独立检查语义树，不能根据布局修改推断已解决。

### 标题栏提示触发 AXTree 错误

真实 Windows 测试确认：标题栏与 Navigator 共用语义边界时，Navigator 内的 `ModalRoute` 使用 `BlockSemantics` 移除此前绘制的节点，范围越过页面内容，导致仍然可见的最小化、最大化和关闭按钮从无障碍树中消失。这时悬停提示的 OverlayPortal 仍提交新的 traversal child，但对应标题栏 anchor 已不在有效树中，产生 `will not be in the tree` 错误。单独给 Tooltip 添加容器无法阻止上层路由屏蔽整个标题栏。

主窗口为标题栏和 Navigator 内容区分别设置常驻 `Semantics(container: true, explicitChildNodes: true)`，将页面路由的语义遮罩限制在内容区内。普通 Tooltip 另保留独立语义容器，避免嵌套 MenuAnchor 与 Tooltip 的 traversal anchors 被合并。保留读屏描述、提示动画和窗口视觉样式，不全局禁用无障碍、不过滤引擎错误。

回归入口为 `integration_test/window_accessibility_test.dart`，覆盖真实应用页面切换、标题栏悬停、点击最大化/还原、最小化/恢复以及弹窗期间的窗口操作。`WINDOW_CYCLES` 可设置循环次数，`WINDOW_DUMP=true` 输出诊断语义树。原生引擎错误不一定触发 `tester.takeException()`，因此通过 `tool/test_window_accessibility.ps1` 同时检查退出码和原生日志，不允许只有测试断言通过却仍刷 AXTree 错误。

Flutter 官方相关记录包括 [提示浮层节点更新问题 #182444](https://github.com/flutter/flutter/issues/182444) 和 [嵌套节点迁移修复 PR #195448](https://github.com/flutter/flutter/pull/195448)。这些上游缺陷是调查线索；本项目此次修正的直接依据是标题栏节点在路由进入后从真实语义树中消失。

本机验证：修正前的 12 轮真实窗口测试记录到 88 条 AXTree 错误；增加标题栏／内容区边界后，24 轮真实 Windows 测试全部通过，包含 6 次弹窗期间的最大化与还原，原生日志未出现 AXTree 错误、布局异常或连接中断。相关 Tooltip 与弹窗边界组件回归共 7 项通过。诊断日志为 `tmp/window-accessibility-diagnostic.log`，最终压力测试日志为 `tmp/window-accessibility-final.log`；这些是本地验证产物，不作为源码提交。

### 最大化后的设置过渡与最大化按钮延迟

性能测试必须覆盖“启动 → 原生窗口最大化 → 首次打开设置”，并用原生 `isMaximized` 断言确认窗口状态，再分别记录首次打开和重复切换。不能仅凭普通窗口的流畅度判断。入口为 `integration_test/window_performance_test.dart`，驱动为 `test_driver/window_performance.dart`；使用 `flutter drive --profile`，通过 `LILYGOBOX_WINDOW_PERF_LABEL` 区分本地报告。

调查依据包括 Flutter 官方 [性能建议](https://docs.flutter.dev/perf/best-practices)、[AnimatedBuilder](https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html) 和 [SnapshotWidget](https://api.flutter.dev/flutter/widgets/SnapshotWidget-class.html)。`saveLayer` 和大面积透明度合成会随窗口像素面积增加开销；本机对照已经确认本项目的整窗离屏裁剪与设置过渡是可避免的成本，不能笼统归因于 Flutter 版本。

最大化／贴屏窗口使用无圆角硬裁剪；普通窗口保留圆角遮罩。设置页通过 AnimatedBuilder.child 保留稳定页面，过渡层设置 RepaintBoundary。底层主外壳和设置层均在非 Web 平台的短过渡期间使用 SnapshotWidget 缓存绘制，动画结束、取消或销毁即释放图像。设置层收到点击、滚轮或键盘操作时恢复实时绘制；仅鼠标悬停不释放快照，避免轻微移动指针就退化为整页实时重绘。保留原有 State、语义、动画曲线和时长，平台视图不能捕获时使用 permissive 回退。

最大化按钮原先通过同步 FFI 调用窗口库，Dart 调用在本机阻塞约 120–125ms。Windows runner 的 `lilygobox/window_layout.toggleMaximize` 现在投递消息后立即回复，由原生窗口消息循环读取实时最大化状态并执行切换；非 Windows 或注入测试窗口沿用平台窗口 API。本机 profile 调用返回约 5–10ms；该数值是调用返回时间，不代表整个系统窗口动画耗时。

托盘可见性回归入口为 `integration_test/tray_visibility_test.dart`：覆盖真实 runner 的右键回调、辅助进程绘制、主窗口隐藏，以及菜单收到失活／取消模式消息后仍可见。检查 IsWindowVisible 和最终 alpha=255，不能只检查 Dart ready。原生菜单不再因这些中间消息立即隐藏，统一交给现有前台窗口监测判断。此测试以原生回调重现消息流程，不能替代 Explorer 隐藏图标面板中的手动右键验证。

此前真实应用 profile 场景的设置过渡对照（历史方案，60Hz，绘制耗时；不包含操作画布后通过个人中心首次打开的触发链）：

| 场景 | 平均 | P90 | P99 | 超过帧预算／帧数 |
| --- | ---: | ---: | ---: | ---: |
| 原实现，最大化反复切换 | 26.207ms | 53.099ms | 73.537ms | 252／319 |
| 无圆角硬裁剪，背景快照 | 4.698ms | 15.300ms | 37.629ms | 30／316 |
| 两层过渡快照，最大化首次打开 | 0.791ms | 1.223ms | 4.389ms | 0／76 |
| 两层过渡快照，最大化反复切换 | 0.775ms | 1.265ms | 3.977ms | 0／317 |

最终场景确认原生窗口为最大化，Flutter 物理视图 2560×1560；窗口切换测得 0／76 个绘制超预算帧。报告为 `tmp/window-performance-before.json`、`tmp/window-performance-snapshot.json`、`tmp/window-performance-snapshot-both.json`。这是当前机器、当前页面内容和自动测试操作下的测量，不能保证任意硬件、并发负载或用户在过渡期间持续输入时都零慢帧。

本轮性能修改后再次运行 24 轮真实窗口／无障碍回归，包含标题栏点击、最大化／还原、最小化／恢复和 6 次弹窗期间窗口操作，全部通过；原生日志未出现 AXTree 错误、框架异常或连接中断。日志为 `tmp/window-accessibility-performance-final.log`。窗口与页面保留相关 13 项组件测试通过；托盘原生可见性测试 4 轮通过（含隐藏主窗口和 alpha 检查）。本轮修改文件的定向静态检查通过；完整 lib 检查另有回收站界面中 4 条既有缺少花括号的 lint 提示，未将其当作本轮窗口修复问题处理。

### 最大化并操作画布后首次打开设置

用户报告仅最大化后，缩放或平移画布，再通过个人中心首次打开设置偶发停顿。SDK 的 SnapshotWidget 在开始捕获时创建额外 scene，并通过 toImageSync 为整个页面生成图像；该调用会提前启动 raster 工作，并非等待 GPU 全部完成后才返回。两个过渡快照同时生成会增加首帧工作量，物理像素面积更大时是需要排查的开销。曾尝试移除背景画布快照，但用户实测最大化后每次进入设置均出现卡顿，该尝试已撤回并恢复双层快照。当前只移除设置层 PointerHover 的快照取消，保留实际操作触发实时绘制；原偶发性能问题尚未通过真实窗口测量确认解决。

性能入口需区分首次打开、最大化并操作画布后的首次打开、紧接着的重复打开，并实际使用个人中心入口；另需覆盖过渡期间持续移动鼠标的场景，普通窗口作为对照。组件测试与静态分析不能证明偶发性能问题已经消除，以上历史数字也不是此次方案的测量结果。当前修改未重新启动应用或运行真实窗口性能测试，需重新编译后验证。


## 聊天快速滚动

连续鼠标滚轮此前每次调用 `animateTo` 都重新创建 180ms 动画。高频输入不断重置动画起始帧，可在组件测试中复现滚轮持续输入而位置暂时不动、停止后再追赶。现在同一次滚轮连续输入共用一个滚动 activity 和动画时钟，通过更新目标位置延续滚动；反向输入放弃旧方向剩余目标，触摸、拖动滚动条和页面隐藏仍能终止活动。嵌套区域的边界仲裁和减少动画偏好继续保留。

聊天正文保持完整高度布局及统一的 SelectionArea，按消息增加独立 RepaintBoundary，减少滚动时长 Markdown 与空行选区辅助绘制的重复执行。底部 64px 淡出改为背景色渐变叠层，不再为整块聊天视口建立 ShaderMask；叠层不接收指针、不增加语义节点。该方式要求聊天背景为不透明纯色，沿用当前 `theme.secondary`，保持主题过渡。

验证包括高频滚轮期间持续位移与累计目标、方向反转、嵌套与中键行为、正文绘制层复用和内容更新、淡出效果在亮暗背景与小视口下的像素对照，以及指针穿透。组件测试不能代替真实 Windows 最大化窗口的帧时间测量；本次没有启动或热重启用户程序，不能据此宣称实际滚动已达到固定帧率。


### 热重启后移动窗口的 AXTree 错误排查

Flutter 3.50.0（引擎 371f77202a73e8dff57a8b3bff75bca55c090aee）的 Windows 源码中，`FlutterWindowsEngine::OnPreEngineRestart` 重置键盘与窗口管理器，却未重建保留视图的 accessibility bridge。该桥接仅在 `FlutterWindowsView::UpdateSemanticsEnabled` 的布尔状态实际改变时销毁或重建。Dart 热重启重新创建语义节点，而 runner 窗口和原生视图继续存在，因此原生语义树残留是本次错误的重要待验证原因。`AccessibilityBridge::CommitUpdates` 在 AXTree 更新失败后只记录错误，没有重建树；窗口移动引起的节点位置更新可能继续触发错误。

以上为当前 SDK 源码排查结果，尚未通过热重启后的真实窗口复现确认因果，也不能将该日志直接归因于窗口句柄或普通布局错误。原有无障碍压力测试未覆盖 Dart 热重启场景。不得全局关闭无障碍、屏蔽日志或仅靠组件测试宣称修复；后续需以完整启动为对照，重复执行热重启、标题栏悬停和拖动窗口，核对原生日志。当前未修改 SDK 或引擎二进制。

### 主题切换与隐藏页面

设置覆盖主页以及主区域保留已访问页面时，原来的 `Offstage` / `TickerMode` 仅停止显示和局部动画，不会停止全局主题通知。180ms 配色过渡中的每一帧仍可唤醒隐藏聊天、工作流及其 Markdown，增加用户实际看到的设置动画的工作量。

现通过 `ThemeUpdateScope` 在保留的隐藏页面边界暂停主题通知，并暂存 Material、默认文字、图标和选区等继承主题；可见设置继续接收完整的平滑配色帧。页面重新显示时同步当前主题和字体，页面 State、对话和滚动位置继续保留。作用域沿用同一个 ThemeProvider，不复制偏好，也不阻断原始业务状态或主题修改操作。此优化没有缩短或关闭全局主题过渡动画。

回归测试检查隐藏页面跨多个主题帧不重建、恢复时读取最新配色与字体、State 不变，以及可见页面仍接收中间颜色。该检查证明通知隔离行为，不代表真实 Windows 最大化窗口已达到固定帧率；本轮未启动或热重启用户程序。
