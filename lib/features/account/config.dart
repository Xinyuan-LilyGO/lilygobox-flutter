/*
 * @Description: 配置 GitHub OAuth 应用的公开编号，允许构建参数覆盖。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 16:53:55
 * @LastEditTime: 2026-10-03 16:53:55
 * @License: GPL 3.0
 */

// Client ID 是公开应用标识；此处不存放 Client Secret 或用户登录凭证。
const githubClientId = String.fromEnvironment(
  'GITHUB_CLIENT_ID',
  defaultValue: 'Ov23limaSLeFyydmGVOf',
);
