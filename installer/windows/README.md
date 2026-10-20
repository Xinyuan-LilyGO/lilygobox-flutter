# Windows 测试安装包

使用 Inno Setup 6 的默认安装向导，不包含自定义安装界面和应用内更新功能。

## 安装语言与许可协议

启动安装程序时可以选择简体中文或英文，仅影响安装和卸载向导，不改变应用内的语言设置。

安装向导提供“创建桌面快捷方式”选项，默认勾选，可手动取消。快捷方式创建在当前用户的桌面，卸载时自动移除；开始菜单快捷方式始终创建。

安装完成页提供“立即打开 LilygoBox”选项，默认勾选；静默安装时不会自动启动应用。

安装时检测应用专属互斥量，应用仍在运行时阻止安装，不自动关闭应用。开始写入安装文件前会再次检查，防止安装向导打开后用户又启动应用。请先等待设备固件更新结束，再完全退出应用（包括托盘进程）。静默安装同样不能覆盖正在运行的应用。

## 卸载与用户数据

卸载前必须完全退出应用（包括托盘进程）。从 Windows 设置或控制面板卸载时，在同一个确认窗口中提供默认不勾选的“同时删除 LilygoBox 用户数据”选项，点击“卸载”直接开始，不再弹出第二次确认。取消不会执行清理。静默卸载始终保留用户数据。

安装完成时将当前用户的普通卸载入口配置为 `/SILENT /LILYGOBOXINTERACTIVE`：前者跳过 Inno Setup 默认确认，后者显示本项目合并后的交互确认窗口；卸载进度仍然显示。系统静默卸载入口保持 Inno Setup 默认配置。

勾选后，在程序卸载阶段结束时清理以下应用专属目录：

- `%APPDATA%\LILYGO\LilygoBox`：设置、加密的登录凭据和设备配对记录。
- `%LOCALAPPDATA%\LILYGO\lilygobox`：固件缓存。

不会删除整个 `LILYGO` 目录、用户自行保存的文件、其他应用共享的安全存储加密密钥，也不会撤销 GitHub 服务器端授权或重置设备。清理失败会显示未能删除的目录，不会静默宣称清理完成。

安装向导显示仓库根目录 `LICENSE` 中的 GNU GPL v3 协议原文，选择接受后才能继续安装。协议副本会安装到应用目录下的 `LICENSE.txt`。项目已有许可证，因此不额外添加可能冲突的通用商业许可模板。

构建脚本会自动将 `LICENSE` 转为 `build/installer/LICENSE.rtf`，标题居中、正文左对齐并自动换行，仅调整排版，不修改协议文字，无需额外插件。

简体中文语言文件保存在 `languages/ChineseSimplified.isl`，来源为 [Inno Setup 简体中文社区翻译](https://github.com/kira-96/Inno-Setup-Chinese-Simplified-Translation)，文件中保留译者和来源信息。

## 构建

安装 Inno Setup 6，然后在仓库根目录运行：

```powershell
./installer/windows/build.ps1 -FlutterPath 'D:\flutter sdk\bin\flutter.bat'
```

如果已有 Release 构建产物，可以添加 `-SkipFlutterBuild` 跳过 Flutter 构建。如果编译器安装在其他目录，请使用 `-IsccPath` 指定路径。

脚本会从 `pubspec.yaml` 读取版本号，检查完整的 Release 输出，并将安装包写入 `build/installer/`。

## 手动测试

1. 完全退出 LilygoBox，包括托盘进程。
2. 运行生成的安装程序。默认安装目录为 `%LOCALAPPDATA%\Programs\LilygoBox`。
   分别检查简体中文和英文安装向导，并确认许可协议页面必须选择接受才能继续。
3. 从开始菜单启动 LilygoBox。
4. 测试覆盖安装已有版本前，先退出应用程序。
5. 通过“Windows 设置 > 应用”卸载，分别检查默认保留数据和勾选删除数据两种情况；同时检查取消卸载不会清理数据。

后续升级时请保持脚本中的 `AppId` 不变。此测试安装包没有签名，也没有捆绑 Microsoft Visual C++ 运行库；正式分发前请在干净的计算机上测试。构建脚本不会执行安装或卸载操作。
