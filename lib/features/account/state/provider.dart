/*
 * @Description: 管理 GitHub 登录、限速轮询、取消、会话恢复和退出，隔离过期异步响应。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 14:22:16
 * @LastEditTime: 2026-10-03 16:53:55
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/github_api.dart';
import '../data/token_store.dart';
import '../domain/models.dart';

enum AccountPhase {
  signedOut,
  restoring,
  requesting,
  waiting,
  completing,
  signedIn,
  signingOut,
}

class AccountProvider extends ChangeNotifier {
  AccountProvider({
    required this.clientId,
    required GithubAuthorizationApi api,
    required AccountTokenStore store,
    Future<bool> Function(Uri)? openBrowser,
    this.supported = true,
  }) : _api = api,
       _store = store,
       _openBrowser =
           openBrowser ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  factory AccountProvider.production({String clientId = githubClientId}) {
    return AccountProvider(
      clientId: clientId,
      api: GithubApi(clientId: clientId),
      store: SecureAccountTokenStore(clientId),
      supported:
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.android),
    );
  }

  final String clientId;
  final bool supported;
  final GithubAuthorizationApi _api;
  final AccountTokenStore _store;
  final Future<bool> Function(Uri) _openBrowser;
  AccountPhase phase = AccountPhase.signedOut;
  GithubUser? user;
  AccountError? error;
  DeviceAuthorization? authorization;
  bool canRetryRestore = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _pollTimer;
  Timer? _expiryTimer;
  Duration _interval = Duration.zero;
  Future<void> _storageQueue = Future.value();

  bool get configured => clientId.trim().isNotEmpty;
  bool get busy =>
      phase != AccountPhase.signedIn && phase != AccountPhase.signedOut;
  bool _active(int generation) => !_disposed && generation == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _expiryTimer?.cancel();
  }

  Future<void> _storage(Future<void> Function() operation) {
    final result = _storageQueue.then((_) => operation());
    _storageQueue = result.catchError((Object _) {});
    return result;
  }

  Future<void> restore() async {
    if (!configured || !supported || busy || user != null || _disposed) return;
    final generation = ++_generation;
    phase = AccountPhase.restoring;
    error = null;
    canRetryRestore = false;
    _notify();
    try {
      GithubToken? token;
      try {
        token = await _store.read();
      } catch (_) {
        throw const AccountException(AccountError.storage);
      }
      if (!_active(generation)) return;
      if (token != null) {
        final profile = await _api.getUser(token);
        if (!_active(generation)) return;
        user = profile;
      }
      phase = user == null ? AccountPhase.signedOut : AccountPhase.signedIn;
    } on AccountException catch (exception) {
      if (!_active(generation)) return;
      if (exception.reason == AccountError.expired) {
        try {
          await _storage(_store.clear);
        } catch (_) {
          if (_active(generation)) error = AccountError.storage;
        }
      } else {
        canRetryRestore = true;
      }
      if (!_active(generation)) return;
      error ??= exception.reason;
      phase = AccountPhase.signedOut;
    } catch (_) {
      if (!_active(generation)) return;
      error = AccountError.network;
      canRetryRestore = true;
      phase = AccountPhase.signedOut;
    }
    _notify();
  }

  Future<void> signIn() async {
    if (busy || user != null || _disposed) return;
    error = !supported
        ? AccountError.unsupported
        : !configured
        ? AccountError.notConfigured
        : null;
    if (error != null) {
      _notify();
      return;
    }
    final generation = ++_generation;
    canRetryRestore = false;
    phase = AccountPhase.requesting;
    _notify();
    try {
      final code = await _api.requestCode();
      if (!_active(generation)) return;
      authorization = code;
      _interval = code.interval;
      phase = AccountPhase.waiting;
      _expiryTimer = Timer(code.expiresIn, () {
        if (_active(generation)) _fail(AccountError.expired);
      });
      _schedulePoll(generation);
      _notify();
      // 显示验证码后由用户点击打开浏览器，避免焦点跳走而看不到验证码。
    } on AccountException catch (exception) {
      if (_active(generation)) _fail(exception.reason);
    } catch (_) {
      if (_active(generation)) _fail(AccountError.network);
    }
  }

  void _schedulePoll(int generation) {
    _pollTimer = Timer(_interval, () => unawaited(_poll(generation)));
  }

  Future<void> _poll(int generation) async {
    if (!_active(generation) || authorization == null) return;
    try {
      final result = await _api.poll(authorization!, _interval);
      if (!_active(generation)) return;
      if (result.token == null) {
        _interval = result.nextInterval ?? _interval;
        _schedulePoll(generation);
        return;
      }
      _stopTimers();
      phase = AccountPhase.completing;
      authorization = null;
      error = null;
      _notify();
      final profile = await _api.getUser(result.token!);
      if (!_active(generation)) return;
      try {
        await _storage(() async {
          if (_active(generation)) await _store.write(result.token!);
        });
      } catch (_) {
        throw const AccountException(AccountError.storage);
      }
      if (!_active(generation)) return;
      user = profile;
      phase = AccountPhase.signedIn;
      _notify();
    } on AccountException catch (exception) {
      if (_active(generation)) _fail(exception.reason);
    } catch (_) {
      if (_active(generation)) _fail(AccountError.network);
    }
  }

  void _fail(AccountError reason) {
    ++_generation;
    _stopTimers();
    authorization = null;
    error = reason;
    phase = AccountPhase.signedOut;
    _notify();
  }

  void cancel() {
    if (phase != AccountPhase.requesting && phase != AccountPhase.waiting) {
      return;
    }
    ++_generation;
    _stopTimers();
    authorization = null;
    error = null;
    phase = AccountPhase.signedOut;
    _notify();
  }

  Future<void> openAuthorizationPage() async {
    if (phase != AccountPhase.waiting) return;
    final generation = _generation;
    bool opened;
    try {
      opened = await _openBrowser(DeviceAuthorization.verificationUri);
    } catch (_) {
      opened = false;
    }
    if (!_active(generation) || phase != AccountPhase.waiting) return;
    error = opened ? null : AccountError.browser;
    _notify();
  }

  Future<void> signOut() async {
    if (_disposed || busy) return;
    final generation = ++_generation;
    _stopTimers();
    phase = AccountPhase.signingOut;
    error = null;
    _notify();
    try {
      await _storage(_store.clear);
      if (!_active(generation)) return;
      user = null;
      authorization = null;
      canRetryRestore = false;
    } catch (_) {
      if (!_active(generation)) return;
      error = AccountError.storage;
    }
    phase = user == null ? AccountPhase.signedOut : AccountPhase.signedIn;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _stopTimers();
    _api.close();
    super.dispose();
  }
}
