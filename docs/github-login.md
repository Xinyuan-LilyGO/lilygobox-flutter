# GitHub 登录配置

LilygoBox 使用 GitHub OAuth App 的 Device Flow。Windows、Android 客户端直接访问 GitHub，无需 Supabase、自建服务器或 Client Secret。

## 先登记应用（只需维护者做一次）

1. 在浏览器登录自己的 GitHub，打开 <https://github.com/settings/applications/new>。
2. Application name 填 `LilygoBox`。
3. Homepage URL 填软件主页：`https://github.com/Xinyuan-LilyGO/lilygobox-flutter`。
4. Authorization callback URL 可填 `http://127.0.0.1/github/callback`。这是登记表的必填项；本实现不使用回调、不监听本地端口。
5. 创建后，进入此应用设置，勾选 **Enable Device Flow** 并保存。
6. 复制 **Client ID**。它是公开应用编号，不是密码；不要生成或在客户端填写 Client Secret。

普通使用者无需登记应用，直接用自己的 GitHub 账号授权即可。

## 运行与打包

应用的 Client ID 在 `lib/features/account/config.dart` 中配置。配置完成后，日常运行和打包不需要额外参数。示例统一使用占位符：

```powershell
flutter run -d windows
flutter build windows --release
flutter build apk --release
```

若需要使用另一个 OAuth App，可通过构建参数覆盖，替换下面的 `YOUR_CLIENT_ID`：

```powershell
flutter run -d windows --dart-define=GITHUB_CLIENT_ID=YOUR_CLIENT_ID
flutter build windows --release --dart-define=GITHUB_CLIENT_ID=YOUR_CLIENT_ID
flutter build apk --release --dart-define=GITHUB_CLIENT_ID=YOUR_CLIENT_ID
```

构建参数优先于配置文件的默认值。更改构建参数后需要重新启动运行命令或重新打包。显式传入空值 `--dart-define=GITHUB_CLIENT_ID=` 可禁用登录配置，入口会明确提示未配置，不会发起请求或模拟登录。Client Secret 和用户令牌不得写入源码或文档。

## 用户操作

打开设置 → 个人中心 → 使用 GitHub 登录，复制验证码，点击“前往 GitHub 授权”，在官方页面输入验证码并确认。回到软件后会显示头像和昵称。

- 本实现只请求公开资料，不请求仓库、组织、代码或私有邮箱权限。
- 按 GitHub 返回的间隔轮询；遇到 `slow_down` 增加间隔；拒绝、过期、网络失败可重新登录。
- 取消登录后，后续网络响应不会恢复这次登录。关闭个人中心不会取消，可通过其他设置页面继续操作。
- 凭证使用 `flutter_secure_storage` 保存在系统安全存储中，并按 Client ID 隔离；不写入日志、源码或普通偏好文件。
- 软件重新启动时通过 `/user` 验证保存的凭证。断网时保留凭证并提供重新验证入口，不伪造验证成功。
- 退出登录清除本机凭证，不会删除 GitHub 账号或本地设备，也不会撤销 GitHub 上的授权。撤销授权：<https://github.com/settings/applications> → Authorized OAuth Apps。
- 当前不自动刷新过期访问令牌；过期或被撤销后需要重新授权。未申请 `offline_access`，不保存刷新令牌。
- 数据仍然保存在本机，没有新增云端设备同步或独立的 LilygoBox 服务端账号。

## 验证与限制

自动化测试使用模拟 HTTP 响应和内存凭证仓库，不读取真实用户凭证。实际授权仍需配置自己的 Client ID，并由用户亲自完成 GitHub 网页授权。

Android 已在主 Manifest 添加联网权限并关闭自动备份，避免安全凭证备份恢复后无法解密。Web、iOS、macOS 和 Linux 登录暂未启用。

免费不等于不限量。GitHub Device Flow 有轮询间隔限制，官方还列出了每应用每小时验证码提交次数限制（查阅时为 50 次）；大规模公开发行前需要重新评估此流程，不能把它当成支持数千万用户的无限免费认证服务。

参考：<https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow>。
