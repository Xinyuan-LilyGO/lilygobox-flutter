/*
 * @Description: 使用系统安全存储保存 AI 服务密钥。
 */

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AiCredentialStore {
  Future<String?> read({required String serviceId});
  Future<void> write(String value, {required String serviceId});
  Future<void> clear({required String serviceId});
}

class SecureAiCredentialStore implements AiCredentialStore {
  const SecureAiCredentialStore({this._storage = const FlutterSecureStorage()});

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String serviceId}) =>
      _storage.read(key: _storageKey(serviceId));

  @override
  Future<void> write(String value, {required String serviceId}) =>
      _storage.write(key: _storageKey(serviceId), value: value);

  @override
  Future<void> clear({required String serviceId}) =>
      _storage.delete(key: _storageKey(serviceId));

  String _storageKey(String id) => 'lilygobox.ai.api_key.service.$id';
}
