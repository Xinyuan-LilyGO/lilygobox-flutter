/*
 * @Description: 定义 GitHub 公开资料、设备授权状态及不含敏感信息的错误类型。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 14:22:16
 * @LastEditTime: 2026-10-03 14:22:16
 * @License: GPL 3.0
 */

enum AccountError {
  notConfigured,
  unsupported,
  network,
  denied,
  expired,
  invalidClient,
  flowDisabled,
  rateLimited,
  invalidResponse,
  storage,
  browser,
}

class AccountException implements Exception {
  const AccountException(this.reason);
  final AccountError reason;
  @override
  String toString() => 'AccountException(${reason.name})';
}

class GithubUser {
  const GithubUser({
    required this.id,
    required this.login,
    this.name,
    this.avatarUrl,
  });
  final int id;
  final String login;
  final String? name;
  final Uri? avatarUrl;
  String get displayName => name?.trim().isNotEmpty == true ? name! : login;
}

class DeviceAuthorization {
  const DeviceAuthorization({
    required this.deviceCode,
    required this.userCode,
    required this.expiresIn,
    required this.interval,
  });
  final String deviceCode;
  final String userCode;
  final Duration expiresIn;
  final Duration interval;
  // 固定可信地址，不把服务响应里的任意网址传给系统浏览器。
  static final verificationUri = Uri.https('github.com', '/login/device');
}

class GithubToken {
  const GithubToken(this.value);
  final String value;
}

class TokenPoll {
  const TokenPoll.pending({this.nextInterval}) : token = null;
  const TokenPoll.authorized(this.token) : nextInterval = null;
  final GithubToken? token;
  final Duration? nextInterval;
}

abstract interface class GithubAuthorizationApi {
  Future<DeviceAuthorization> requestCode();
  Future<TokenPoll> poll(DeviceAuthorization authorization, Duration interval);
  Future<GithubUser> getUser(GithubToken token);
  void close();
}

abstract interface class AccountTokenStore {
  Future<GithubToken?> read();
  Future<void> write(GithubToken token);
  Future<void> clear();
}
