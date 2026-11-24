# 文档

本目录集中存放项目开发规范和功能说明。

## 开发规范

- Windows 最大化时多选拖动脱离鼠标、上千张卡片加载和长聊天滚动分段的修复方法与实机基准。[画布与长聊天卡顿](flutter-upgrade-performance.md#画布与长聊天卡顿)

- [标准提示框与操作按钮](dialog-style.md)：公共窗口模板、统一字体、按钮尺寸与浅色背景上的 6% 灰色按钮规则。

- [提交说明约定](commit_messages.md)：英文标题、可选范围和改动列表的格式。
- [兼容性维护约定](legacy-compatibility.md)：按公开发布的基线保留兼容性，只清理未发布的中间实现，并保护设备更新适配。
- [Dart 文件头注释](dart-file-headers.md)：文件职责说明与格式示例。
- [全局输入框样式](text-input-style.md)：主标题与次标题的统一字号、字重、颜色、行高与排列，以及共享控件、内边距、无障碍和特殊输入框约定。
- [右键与文本操作菜单](context-menus.md)：公共菜单构建器、文本选择接入、动画与背景配色约定。
- [公共页面切换动画](page-transitions.md)：内容页淡入淡出、稳定标识、退出页交互隔离及减少动画设置。
- [可复制文本的选区样式](text-selection.md)：按每行文字绘制高亮，保留连续选择、换行和复制行为。
- [设置下拉控件颜色](dropdown-colors.md)：根据承载背景派生下拉框及展开菜单颜色，维持明暗主题对比。
- [全局页面滚动](scroll-behavior.md)：公共平滑滚轮、嵌套仲裁、滚动条与聊天分页。
- [全局数值滑条样式](slider-style.md)：共享胶囊滑条、细轨道端点与等级节点对齐规则。
- [AI 回复耗时与详情](assistant-response-details.md)：回复状态与用时、请求重试、错误记录、设置操作详情、Markdown 渲染、复制与消息时间。

## 功能说明

- [智能体记忆与存储](agent-memory-storage.md)：聊天持久化、长期记忆、上下文压缩、单文件数据包和冲突处理。

- [主页智能体工作流](assistant-workspaces.md)：多层智能体树、主智能体与可视化子智能体、双向消息、独立会话和本地恢复。
- [AI 工具权限与批准](assistant-permissions.md)
- [提问卡片与回答回传](assistant-user-input.md)：模型工具触发、输入区替换、选项与自填答案、停止和取消，以及思考与正文分离。
- [AI 思考强度](ai-reasoning-effort.md)
- [模型图片输入能力声明](ai-image-input.md)
- [Windows 离线语音](offline-voice.md)：官方模型导入、音色试听、聊天录音与回复朗读。
- [Windows 剪贴板历史粘贴](windows-clipboard-history.md)
- [应用图标](app-icon.md)
- [配置文件](configuration-file.md)
- [设备连接](device-connection.md)
- [GitHub 登录](github-login.md)
- [光效](glow-effects.md)
- [安装指南](installation-guide.md)
- [本地存储](local-storage.md)
- [通知](notifications.md)
