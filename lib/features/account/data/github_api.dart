/*
 * @Description: 调用 GitHub 设备授权和公开用户资料接口，不使用客户端密钥。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 14:22:16
 * @LastEditTime: 2026-10-03 14:22:16
 * @License: GPL 3.0
 */

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';

class GithubApi implements GithubAuthorizationApi {
  GithubApi({required this.clientId, http.Client? client})
    : _client = client ?? http.Client();
  final String clientId;
  final http.Client _client;
  static const requestTimeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> _request(
    Uri uri, {
    Map<String, String>? form,
    GithubToken? token,
  }) async {
    try {
      final request = http.Request(form == null ? 'GET' : 'POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Accept': 'application/json',
          'User-Agent': 'LilygoBox',
          if (token != null) 'Authorization': 'Bearer ${token.value}',
        });
      if (form != null) request.bodyFields = form;
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(requestTimeout);
      if (response.statusCode == 401) {
        throw const AccountException(AccountError.expired);
      }
      if (response.statusCode == 429 || response.statusCode == 403) {
        throw const AccountException(AccountError.rateLimited);
      }
      if (response.statusCode >= 500) {
        throw const AccountException(AccountError.network);
      }
      if (response.statusCode != 200) {
        throw const AccountException(AccountError.invalidResponse);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return decoded;
    } on AccountException {
      rethrow;
    } on FormatException {
      throw const AccountException(AccountError.invalidResponse);
    } catch (_) {
      // HTTP 异常可能包含请求内容，禁止向日志或界面透出原始异常。
      throw const AccountException(AccountError.network);
    }
  }

  Never _fail(Object? error) => throw AccountException(switch (error) {
    'access_denied' => AccountError.denied,
    'expired_token' || 'token_expired' => AccountError.expired,
    'incorrect_client_credentials' => AccountError.invalidClient,
    'device_flow_disabled' => AccountError.flowDisabled,
    _ => AccountError.invalidResponse,
  });

  @override
  Future<DeviceAuthorization> requestCode() async {
    if (clientId.trim().isEmpty) {
      throw const AccountException(AccountError.notConfigured);
    }
    final data = await _request(
      Uri.https('github.com', '/login/device/code'),
      form: {'client_id': clientId, 'scope': ''},
    );
    if (data.containsKey('error')) _fail(data['error']);
    final code = data['device_code'];
    final userCode = data['user_code'];
    final expires = data['expires_in'];
    final interval = data['interval'] ?? 5;
    if (code is! String ||
        code.isEmpty ||
        userCode is! String ||
        !RegExp(r'^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$').hasMatch(userCode) ||
        expires is! int ||
        expires <= 0 ||
        interval is! int ||
        interval <= 0 ||
        data['verification_uri'] !=
            DeviceAuthorization.verificationUri.toString()) {
      throw const AccountException(AccountError.invalidResponse);
    }
    return DeviceAuthorization(
      deviceCode: code,
      userCode: userCode,
      expiresIn: Duration(seconds: expires),
      interval: Duration(seconds: interval),
    );
  }

  @override
  Future<TokenPoll> poll(
    DeviceAuthorization authorization,
    Duration interval,
  ) async {
    final data = await _request(
      Uri.https('github.com', '/login/oauth/access_token'),
      form: {
        'client_id': clientId,
        'device_code': authorization.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      },
    );
    if (data['error'] == 'authorization_pending') {
      return const TokenPoll.pending();
    }
    if (data['error'] == 'slow_down') {
      final reported = data['interval'];
      final minimum = interval.inSeconds + 5;
      return TokenPoll.pending(
        nextInterval: Duration(
          seconds: reported is int && reported > minimum ? reported : minimum,
        ),
      );
    }
    if (data.containsKey('error')) _fail(data['error']);
    final token = data['access_token'];
    if (token is! String || token.isEmpty || data['token_type'] != 'bearer') {
      throw const AccountException(AccountError.invalidResponse);
    }
    return TokenPoll.authorized(GithubToken(token));
  }

  @override
  Future<GithubUser> getUser(GithubToken token) async {
    final data = await _request(
      Uri.https('api.github.com', '/user'),
      token: token,
    );
    final id = data['id'];
    final login = data['login'];
    if (id is! int || id <= 0 || login is! String || login.isEmpty) {
      throw const AccountException(AccountError.invalidResponse);
    }
    final avatar = Uri.tryParse(
      data['avatar_url'] is String ? data['avatar_url'] : '',
    );
    return GithubUser(
      id: id,
      login: login,
      name: data['name'] is String ? data['name'] : null,
      avatarUrl:
          avatar?.scheme == 'https' &&
              avatar?.host == 'avatars.githubusercontent.com'
          ? avatar
          : null,
    );
  }

  @override
  void close() => _client.close();
}
