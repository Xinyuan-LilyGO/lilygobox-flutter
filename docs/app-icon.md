# Windows 应用图标

应用内标志源文件：`assets/images/branding/lilygobox_logo.svg`。

Windows 使用 `windows/runner/resources/app_icon.ico`，由 `Runner.rc` 嵌入
可执行文件，供资源管理器、窗口和任务切换使用。图标采用现有标志与浅色圆角底，
包含 16、20、24、32、40、48、64、96、128、256 像素版本，以适配不同显示缩放。
高清预览位于 `assets/images/branding/lilygobox_app_icon.png`。

## 更新图标

修改 SVG 后，使用安装了 `sharp` 的 Node.js 环境运行：

```sh
node tool/generate_windows_icon.cjs
```

`sharp` 仅用于资源生成，不是 Flutter 运行依赖。脚本会同时更新预览 PNG 和 ICO。
提交生成后的文件，其他开发者正常编译时无需安装 Node.js 或重新生成图标。

关闭正在运行的旧版本，再执行 `flutter run -d windows` 或
`flutter build windows`。原生应用图标需要重新编译，热重载和热重启不会更新它。

如果旧快捷方式仍显示默认图标，可重新创建快捷方式；固定到任务栏的旧快捷方式可
取消固定后重新固定。本次仅替换 Windows 图标，其他平台图标资源保持原状。
