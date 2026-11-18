# 旧接口标记约定

旧接口及相关兼容代码必须通过以下任一方式明确标记，便于后续检索：

- 命名包含 `legacy`：Dart 类使用 `Legacy…`，方法和变量使用 `legacy…` / `_legacy…`，独立文件使用 `legacy_…`。
- 在相关入口旁添加 `LEGACY:` 注释，说明对应的旧接口或旧格式。

不适合使用 `legacy` 命名时不强求改名，使用 `LEGACY:` 注释即可。

注释示例：

```dart
// LEGACY: 兼容旧字段 previous_name。
```
