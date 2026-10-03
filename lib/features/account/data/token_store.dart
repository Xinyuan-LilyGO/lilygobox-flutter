/*
 * @Description: 使用系统安全存储保存 GitHub 登录凭证，按应用编号隔离。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 14:22:16
 * @LastEditTime: 2026-10-03 14:22:16
 * @License: GPL 3.0
 */

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/models.dart';

class SecureAccountTokenStore implements AccountTokenStore {
  SecureAccountTokenStore(String clientId)
    : _key = 'lilygobox.github.$clientId.access_token';
  final String _key;
  final _storage = const FlutterSecureStorage();
  @override
  Future<GithubToken?> read() async {
    final value = await _storage.read(key: _key);
    return value == null || value.isEmpty ? null : GithubToken(value);
  }

  @override
  Future<void> write(GithubToken token) =>
      _storage.write(key: _key, value: token.value);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}
