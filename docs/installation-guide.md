# 安装说明

LilygoBox 当前支持 Windows 桌面端。Linux、macOS、Android、iOS 和 Web 暂不是已支持的发布平台。

## Windows

使用 LilygoBox Release 提供的 `LilygoBox-windows-x64-setup.exe` x64 安装程序。安装器可选择英文或简体中文，会显示项目的 GPL v3 许可协议，并提供创建桌面快捷方式的选项。开始菜单快捷方式始终创建。安装完成页默认勾选“立即打开 LilygoBox”。软件版本由发布清单和 GitHub Release 标签标识。

默认安装目录：

```text
%LOCALAPPDATA%\Programs\LilygoBox
```

安装器不会强制关闭 LilygoBox。安装或升级前，请完全退出应用，包括系统托盘进程。如果设备固件正在更新，请等待更新结束后再退出应用并运行安装程序。

### 升级

运行较新版本的安装程序，并安装到现有位置。安装器使用相同的应用标识进行升级。用户设置、已保存的登录信息、设备配对记录和固件缓存会保留。

### 卸载

先完全退出应用，包括系统托盘进程，然后打开 **Windows 设置 > 应用** 卸载 LilygoBox。卸载窗口默认保留用户数据；勾选“同时删除 LilygoBox 用户数据”会一并删除本机设置、登录信息、设备配对记录和固件缓存。此操作不会重置已连接的设备，也不会删除用户的 GitHub 网站账号。

静默卸载会保留用户数据。安装包未捆绑 Microsoft Visual C++ 运行库，在干净的 Windows 系统上可能需要单独安装。

## 其他平台

Linux、macOS、Android、iOS 和 Web 当前不是已支持的发布平台。仓库中可能存在对应 Flutter 工程目录，但尚未验证其安装包和运行行为。

## 开发构建

开发环境要求和 `flutter run` 命令请参阅[中文 README 的快速开始](../README_CN.md)。Windows 安装包的构建和维护方式见 [installer/windows/README.md](../installer/windows/README.md)。
