# 设置下拉控件颜色

`SettingSelect` 通过 `surfaceColor` 接收所在页面或弹窗的背景；默认使用设置内容区的 `theme.secondary`。
收起控件底色由 `selectControlColorForSurface` 根据实际承载背景派生。展开菜单与承载层分开，使用 `popupSurfaceColor`：浅色主题为白色，深色主题为专用深灰；不要把承载背景混入菜单内容底色。选中、悬停和文字颜色继续使用共享菜单组件的主题配置。
