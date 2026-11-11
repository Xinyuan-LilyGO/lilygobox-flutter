# 设置下拉控件颜色

`SettingSelect` 通过 `surfaceColor` 接收所在页面或弹窗的背景；默认使用设置内容区的 `theme.secondary`。
收起控件底色由 `selectControlColorForSurface` 根据实际承载背景派生。展开菜单与承载层分开，使用 `popupSurfaceColor`：浅色主题为白色，深色主题为专用深灰；不要把承载背景混入菜单内容底色。选中、悬停和文字颜色继续使用共享菜单组件的主题配置。

设置页普通灰色文字按钮（包括“添加模型服务”和其他复用 `AppActionButton` 的普通操作）与模型服务卡片统一使用 `settingsControlBackgroundColor`，与设置内容背景上的下拉框收起底色相同，均由 `secondary` 向 `textColorPrimary` 插值 12% 得到，随主题背景调整同步变化。普通按钮显式提供承载背景时按该背景派生；悬停从按钮实际背景通过 `hoverColorForBackground` 派生。紫色主要操作、红色删除按钮、弹窗专用底色、第三层卡片上的专用按钮以及显式覆盖颜色继续保留各自规则。
