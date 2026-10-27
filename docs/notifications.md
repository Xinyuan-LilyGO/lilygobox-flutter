# 应用内通知

应用当前默认使用 Flutter `SnackBar` 作为短暂的操作结果通知。它显示在 LilygoBox 窗口内，由 `ScaffoldMessenger` 管理，不是 Windows 通知中心或其他操作系统的系统通知。

通知背景复用悬停提示的反色背景颜色，并使用 80% 不透明度；通知文字颜色及其他样式沿用原设置。

## 使用场景

适合通知用户刚刚执行的操作结果，例如配置导入或导出成功、设备删除结果，以及可恢复操作失败。所有短暂操作通知统一调用 `showAppNotice`，位于 `lib/core/widgets/app_notice.dart`。不要在业务页面直接创建 `SnackBar`，以便统一管理样式和后续调整。

底部通知在 Debug、Profile 和 Release 模式下都应显示。不要使用 `kDebugMode`、`kReleaseMode` 等构建模式判断隐藏面向用户的通知。仅当对应的 `ScaffoldMessenger` 已卸载时，才跳过显示。

## 选择其他反馈方式

需要用户作出重要决定或明确确认后才能继续时，使用项目公共确认对话框 `showAppConfirmation`（`lib/core/widgets/confirmation_dialog.dart`）。持续存在、需要用户采取行动的错误应显示在相关页面内容中，不应只短暂显示在底部。

## 多语言

所有面向用户的通知文案必须使用 `AppLocalizations`。在 `lib/l10n/app_en.arb` 和 `lib/l10n/app_zh.arb` 中同步维护英文和中文文案，并重新生成本地化代码；不要在通知调用处硬编码界面文字。

## 平台范围

`SnackBar` 是 Flutter 应用内组件，Flutter 支持的平台均可使用，但需要当前页面位于包含 `ScaffoldMessenger` 的应用界面中。它不会在应用窗口关闭或后台运行时作为系统通知送达。
