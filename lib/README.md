# 源码目录约定

项目按功能模块组织代码，文件名使用 `snake_case`，类名使用 `UpperCamelCase`。

```text
lib/
  main.dart                         应用启动入口
  app/                              应用组装、导航、主界面框架和窗口
  core/                             多个功能共用的基础能力
    widgets/settings/               通用设置布局和控件
  features/
    settings/presentation/
      pages/                        完整设置页面
      widgets/                      设置分类内容和主题选择等局部组件
    devices/
      domain/                       共享设备标识及业务定义
      state/                        设备列表状态和添加设备流程状态
      presentation/                 设备选择、页面分派及通用设备界面
      t_glasses_p4/
        domain/                     该设备的业务类型与连接状态定义
        presentation/
          pages/                    完整设备页面
          widgets/                  设备专用界面组件
  l10n/                             手动维护的中英文 ARB 翻译
  generated/l10n/                   flutter gen-l10n 生成的代码
```

## 文件放置

- `app/` 负责全局 Provider 注入、导航和窗口组装；具体产品页面由设备展示目录分派。
- `core/` 只放跨模块复用的代码，不依赖具体设备页面。
- `domain/` 放不依赖 Flutter 界面的业务类型和规则。例如连接状态枚举属于设备领域定义。
- `state/` 放页面流程状态及 Provider；无需把所有状态都提升为全局状态。
- `pages/` 放完整页面，`widgets/` 放嵌入页面的内容组件。文件名分别使用 `_page.dart`、`_content.dart` 或组件职责名称。
- 设备目录已经说明产品时，文件名不再重复设备名称；跨模块使用的类名可以保留设备标识。
- 设置控件位于 `core/widgets/settings/` 时，文件名不再重复 `setting_` 或 `settings_` 前缀；类名保留职责标识，例如 `SettingsRow`。
- 目录已明确模块时，省略文件名中的重复模块词。例如 `app/providers.dart`、`core/theme/provider.dart`、`features/devices/domain/catalog.dart`。单一模块的主页面可命名为 `pages/page.dart`，类名仍保留完整用途，避免调用处混淆。
- 新文件使用中文 `@Description` 文件头。已有作者、日期和许可证信息保留；不补写无法确认的历史日期。
- `///` 用于类和公开成员的使用说明，`//` 用于内部实现说明。
- 测试按对应模块放在项目根目录的 `test/` 下。

## 通用设置控件

`core/widgets/settings/widgets.dart` 是统一导出入口，各实现文件按职责拆分：

- `page_layout.dart`：标题和滚动内容布局。
- `row.dart`：设置说明、控件及更多操作的排列。
- `fields.dart`：文本输入和只读字段。
- `select.dart`：下拉选择及菜单生命周期。
- `stepper.dart`、`action_button.dart`：数值增减和操作按钮。
- `more_button.dart`、`decoration.dart`：目录内部使用的菜单和装饰实现。

菜单、设置行控件和主题选择继续复用 `MenuItemSurface` 的颜色过渡与交互规则。

右键、托盘、个人中心、文本操作和设置下拉菜单统一使用 `RightClickMenuBuilder.buildMenuPanel`，背景、圆角、阴影、字体、图标和悬停配色由公共组件管理。弹出时使用 `PopupMenuTransition` 的 150 毫秒淡入和轻微展开；托盘宿主和 Flutter 文本选择层已有淡入时只接入展开，避免重复叠加透明度。新增文本输入使用固定的 `AppTextSelectionMenu.build` 回调，防止页面刷新时菜单被关闭后重新弹出。

## 添加设备与设置页

1. 在 `features/devices/domain/catalog.dart` 中登记支持的设备标识。
2. 在该设备目录下实现页面及专用组件。
3. 在 `DevicePresentationCatalog` 中登记图标、主页和设置页映射。
4. 通过 `AppNavigationProvider.openDeviceSettings(deviceName)` 打开指定设备的设置。

主窗口不直接导入具体产品的设置页面。没有设置页映射的设备会显示未适配说明和返回入口，避免打开其他产品的设置。当前设备标识仍沿用现有的型号名称；多个同型号设备实例接入时，再引入实例 ID。

蓝牙、Wi-Fi、账号等功能接入时，按实际需要增加通信服务和数据层，不预先建立空的分层目录。
