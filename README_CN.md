<h1 align="center">LilygoBox</h1>

## **[English](./README.md) | 中文**

[![Flutter](https://img.shields.io/badge/Flutter-3.35.6%2B-02569B?style=flat-square&logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.9.2%2B-0175C2?style=flat-square&logo=dart)](https://dart.dev/)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue?style=flat-square)](./LICENSE)

**LilygoBox** 是一款基于 Flutter 开发的 LILYGO 设备控制应用。项目按照应用壳层、公共核心模块和业务功能模块拆分，方便设备页面、设置页面、多语言、主题和桌面窗口行为独立维护。

当前项目重点面向 Windows 桌面端体验。仓库中可能保留其他平台目录，这是 Flutter 工程脚手架的一部分，但现阶段并不作为支持目标。

## 目录

- [功能特性](#功能特性)
- [支持列表](#支持列表)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [项目结构](#项目结构)
- [开发说明](#开发说明)

## 功能特性

### 桌面应用壳层

应用壳层负责桌面窗口外框、标题栏、缩放覆盖层、页面栈和左侧导航。页面导航状态与桌面窗口状态分离，应用内页面切换不会和最大化、焦点、最小化、关闭等系统窗口行为混在一起。

### 面向设备的结构设计

设备定义与展示映射分离。通用设备状态放在 devices 功能模块中，像 **T-Glasses-P4** 这样的专属设备页面则放在对应设备自己的目录下。

### 公共核心模块

通用服务和可复用 UI 组件放在 `lib/core`，包含主题、多语言辅助、窗口状态、右键菜单和通用分栏组件等。

### 多语言支持

可编辑的翻译源文件使用 ARB 格式，存放在 `lib/l10n`。Flutter 生成的本地化 Dart 文件存放在 `lib/generated/l10n`，并从 analyzer 规则中排除。

## 支持列表

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Windows | 支持 | 当前主要开发和构建目标 |
| Linux | 不支持 | 可能保留平台目录，但尚未验证 Release 构建和运行行为 |
| macOS | 不支持 | 可能保留平台目录，但尚未验证 Release 构建和运行行为 |
| Android | 不支持 | 保留自 Flutter 工程脚手架 |
| iOS | 不支持 | 保留自 Flutter 工程脚手架 |
| Web | 不支持 | 保留自 Flutter 工程脚手架 |

## 环境要求

| 工具 | 版本 | 说明 |
| --- | --- | --- |
| Flutter | 3.35.6 或更高版本 | 在 `pubspec.yaml` 中定义 |
| Dart | 3.9.2 或更高版本 | 在 `pubspec.yaml` 中定义 |
| Windows 桌面构建工具链 | 按平台安装 | Windows 桌面构建需要对应工具链 |

## 快速开始

安装依赖：

```bash
flutter pub get
```

如果修改了 ARB 多语言文件，重新生成本地化代码：

```bash
flutter gen-l10n
```

运行 Windows 桌面应用：

```bash
flutter run -d windows
```

构建 Windows Release：

```bash
flutter build windows
```

## 项目结构

```text
lib/
  app/                         # 应用级壳层、启动逻辑、Provider 组合和导航。
    bootstrap/                 # 桌面端启动代码，例如窗口初始化。
    navigation/                # 应用内页面路由状态。
    shell/                     # 主应用壳层、侧边栏和壳层状态。
      pages/                   # 应用壳层页面和首页内容。
      state/                   # 应用壳层选择状态。
      widgets/                 # 应用壳层组件，例如侧边栏按钮。
    widgets/                   # 窗口外框、标题栏、页面栈和缩放覆盖层。

  core/                        # 跨功能复用模块。
    app_info/                  # 应用和包信息 Provider。
    context_menu/              # 通用右键菜单工具。
    l10n/                      # 多语言辅助和语言 Provider。
    layout/                    # 通用布局状态，例如分栏宽度。
    theme/                     # 主题定义和主题 Provider。
    widgets/                   # 通用 UI 基础组件。
    window/                    # 桌面窗口状态和窗口操作。

  features/                    # 按业务功能拆分的模块。
    devices/                   # 设备管理和设备页面。
      domain/                  # 支持的设备名称和领域层目录。
      presentation/            # 设备页面、组件和展示映射。
      state/                   # 设备功能状态。
      t_glasses_p4/            # T-Glasses-P4 专属页面、组件和状态。
    settings/                  # 设置页面和设置相关组件。

  generated/                   # 生成代码目录。
    l10n/                      # Flutter gen-l10n 生成的本地化代码。

  l10n/                        # 可编辑的 ARB 翻译源文件。
  main.dart                    # Flutter 应用入口。
```

根目录配置文件：

| 文件 | 用途 |
| --- | --- |
| `pubspec.yaml` | Flutter 包信息、SDK 约束和依赖配置 |
| `analysis_options.yaml` | Flutter lint 规则和 analyzer 排除项 |
| `l10n.yaml` | Flutter 多语言代码生成配置 |
| `package_rename_config.yaml` | 应用和包重命名配置 |
| `pubspec.lock` | 依赖版本锁定文件 |

## 开发说明

- 应用级壳层代码放在 `lib/app`。
- 跨功能复用代码放在 `lib/core`。
- 业务功能代码放在 `lib/features/<feature>`。
- 可编辑翻译文件放在 `lib/l10n`。
- 不要手动修改 `lib/generated/l10n` 下的生成文件；应修改 ARB 文件后执行 `flutter gen-l10n`。
- 项目内部 Dart 文件优先使用相对路径导入。
