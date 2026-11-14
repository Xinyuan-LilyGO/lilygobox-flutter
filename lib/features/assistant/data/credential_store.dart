/*
 * @Description: 使用系统安全存储保存 AI 服务密钥。
 */

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AiCredentialStore {
  Future<String?> read({String? serviceId});
  Future<void> write(String value, {String? serviceId});
  Future<void> clear({String? serviceId});
}

class SecureAiCredentialStore implements AiCredentialStore {
  const SecureAiCredentialStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _key = 'lilygobox.ai.api_key';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({String? serviceId}) =>
      _storage.read(key: _storageKey(serviceId));

  @override
  Future<void> write(String value, {String? serviceId}) =>
      _storage.write(key: _storageKey(serviceId), value: value);

  @override
  Future<void> clear({String? serviceId}) =>
      _storage.delete(key: _storageKey(serviceId));

  String _storageKey(String? id) => id == null ? _key : '$_key.service.$id';
}
