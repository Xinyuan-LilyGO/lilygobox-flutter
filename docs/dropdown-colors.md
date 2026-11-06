# 设置下拉控件颜色

`SettingSelect` 通过 `surfaceColor` 接收所在页面或弹窗的背景；默认使用设置内容区的 `theme.secondary`。
控件底色统一由 `selectControlColorForSurface` 派生，展开菜单由 `selectMenuColorForSurface` 派生。
当前混合比例分别为承载背景向 `textColorPrimary` 混合 12% 和 18%：浅色主题形成更深的底色，深色主题形成更亮的底色，以增强与背景的区分。
不要将某个页面的实际颜色复制成全局固定色；不同承载背景仍需分别传入，悬停和文字颜色继续使用共享组件的主题配置。
