/*
 * @Description: 验证 GitHub 授权请求、轮询限速、取消竞态、凭证保存和失效处理。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 14:22:16
 * @LastEditTime: 2026-10-03 14:22:16
 * @License: GPL 3.0
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/account/data/github_api.dart';
import 'package:lilygobox/features/account/domain/models.dart';
import 'package:lilygobox/features/account/state/provider.dart';
import 'package:lilygobox/features/settings/presentation/widgets/profile_content.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

const code = DeviceAuthorization(
  deviceCode: 'test-device-code',
  userCode: 'ABCD-EFGH',
  expiresIn: Duration(seconds: 30),
  interval: Duration(seconds: 5),
);
const profile = GithubUser(id: 123, login: 'tester', name: 'Test User');

class MemoryStore implements AccountTokenStore {
  GithubToken? token;
  bool failWrites = false;
  bool failClear = false;
  int writes = 0;
  @override
  Future<GithubToken?> read() async => token;
  @override
  Future<void> write(GithubToken value) async {
    if (failWrites) throw StateError('storage unavailable');
    writes++;
    token = value;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('storage unavailable');
    token = null;
  }
}

class FakeApi implements GithubAuthorizationApi {
  int requests = 0;
  int polls = 0;
  bool closed = false;
  Completer<DeviceAuthorization>? request;
  Completer<TokenPoll>? pendingPoll;
  AccountError? userFailure;
  List<TokenPoll> results = [
    const TokenPoll.authorized(GithubToken('test-token')),
  ];
  @override
  Future<DeviceAuthorization> requestCode() async {
    requests++;
    return request?.future ?? code;
  }

  @override
  Future<TokenPoll> poll(
    DeviceAuthorization authorization,
    Duration interval,
  ) async {
    polls++;
    return pendingPoll?.future ??
        (results.isEmpty ? const TokenPoll.pending() : results.removeAt(0));
  }

  @override
  Future<GithubUser> getUser(GithubToken token) async {
    if (userFailure != null) throw AccountException(userFailure!);
    return profile;
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  testWidgets(
    'authorization page fits narrow screens and shows verified identity',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final locale in ['zh', 'en']) {
        final api = FakeApi();
        final account = AccountProvider(
          clientId: 'test',
          api: api,
          store: MemoryStore(),
          openBrowser: (_) async => false,
        );
        final theme = ThemeProvider();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: account,
            child: MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(body: ProfileContent(theme: theme.themeData)),
              ),
            ),
          ),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('profile-sign-in')),
        );
        await tester.tap(find.byKey(const ValueKey('profile-sign-in')));
        await tester.pumpAndSettle();
        expect(find.text('ABCD-EFGH'), findsOneWidget);
        final browser = find.byKey(const ValueKey('github-open-browser'));
        await tester.ensureVisible(browser);
        await tester.tap(browser);
        await tester.pumpAndSettle();
        expect(account.error, AccountError.browser);
        expect(find.byKey(const ValueKey('github-error')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text('Test User'), findsOneWidget);
        expect(find.text('@tester'), findsOneWidget);
        expect(find.byKey(const ValueKey('github-user-code')), findsNothing);
        final signOut = find.byKey(const ValueKey('github-sign-out'));
        await tester.ensureVisible(signOut);
        await tester.tap(signOut);
        await tester.pumpAndSettle();
        expect(account.user, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        account.dispose();
        theme.dispose();
      }
    },
  );

  test(
    'device requests use form encoding, minimal scope and no client secret',
    () async {
      var count = 0;
      final api = GithubApi(
        clientId: 'test-client',
        client: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['accept'], 'application/json');
          if (count++ == 0) {
            expect(
              request.url.toString(),
              'https://github.com/login/device/code',
            );
            expect(request.bodyFields, {
              'client_id': 'test-client',
              'scope': '',
            });
            return http.Response(
              jsonEncode({
                'device_code': 'test-code',
                'user_code': 'ABCD-EFGH',
                'verification_uri': 'https://github.com/login/device',
                'expires_in': 900,
                'interval': 5,
              }),
              200,
            );
          }
          if (count == 2) {
            expect(
              request.url.toString(),
              'https://github.com/login/oauth/access_token',
            );
            expect(
              request.bodyFields['grant_type'],
              'urn:ietf:params:oauth:grant-type:device_code',
            );
            expect(request.bodyFields.containsKey('client_secret'), isFalse);
            return http.Response(
              '{"access_token":"test-token","token_type":"bearer"}',
              200,
            );
          }
          expect(request.url.toString(), 'https://api.github.com/user');
          expect(request.headers['authorization'], 'Bearer test-token');
          return http.Response(
            '{"id":1,"login":"user","avatar_url":"https://untrusted.example/avatar"}',
            200,
          );
        }),
      );
      addTearDown(api.close);
      final authorization = await api.requestCode();
      final token = (await api.poll(
        authorization,
        authorization.interval,
      )).token!;
      expect((await api.getUser(token)).avatarUrl, isNull);
      expect(count, 3);
    },
  );

  test(
    'slow_down increases the minimum interval and errors stay sanitized',
    () async {
      final replies = [
        '{"error":"slow_down","interval":3}',
        '{"error":"slow_down","interval":20}',
        '{"error":"access_denied","error_description":"secret content"}',
      ];
      final api = GithubApi(
        clientId: 'test',
        client: MockClient(
          (_) async => http.Response(replies.removeAt(0), 200),
        ),
      );
      addTearDown(api.close);
      expect(
        (await api.poll(code, const Duration(seconds: 5))).nextInterval,
        const Duration(seconds: 10),
      );
      expect(
        (await api.poll(code, const Duration(seconds: 10))).nextInterval,
        const Duration(seconds: 20),
      );
      await expectLater(
        api.poll(code, code.interval),
        throwsA(
          isA<AccountException>()
              .having((e) => e.reason, 'reason', AccountError.denied)
              .having(
                (e) => e.toString(),
                'safe message',
                isNot(contains('secret')),
              ),
        ),
      );
    },
  );

  test('rejects HTTP redirects and invalid verification URLs', () async {
    for (final response in [
      http.Response(
        '',
        302,
        headers: {'location': 'https://untrusted.example'},
      ),
      http.Response(
        '{"device_code":"x","user_code":"ABCD-EFGH","expires_in":900,"verification_uri":"https://untrusted.example"}',
        200,
      ),
    ]) {
      final api = GithubApi(
        clientId: 'test',
        client: MockClient((_) async => response),
      );
      await expectLater(api.requestCode(), throwsA(isA<AccountException>()));
      api.close();
    }
  });

  testWidgets(
    'polls sequentially, honors slow down, saves profile and signs out',
    (tester) async {
      final api = FakeApi()
        ..results = [
          const TokenPoll.pending(nextInterval: Duration(seconds: 10)),
          const TokenPoll.authorized(GithubToken('test-token')),
        ];
      final store = MemoryStore();
      final account = AccountProvider(clientId: 'test', api: api, store: store);
      addTearDown(account.dispose);
      await account.signIn();
      await account.signIn();
      expect(api.requests, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(api.polls, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(api.polls, 1);
      await tester.pump(const Duration(seconds: 9));
      expect(api.polls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(api.polls, 2);
      expect(account.user?.id, 123);
      expect(store.token?.value, 'test-token');
      expect(account.authorization, isNull);
      await account.signOut();
      expect(account.user, isNull);
      expect(store.token, isNull);
      expect(account.phase, AccountPhase.signedOut);
    },
  );

  testWidgets('cancel ignores a late code or token response', (tester) async {
    final api = FakeApi()..request = Completer<DeviceAuthorization>();
    final store = MemoryStore();
    final account = AccountProvider(clientId: 'test', api: api, store: store);
    addTearDown(account.dispose);
    final start = account.signIn();
    account.cancel();
    api.request!.complete(code);
    await start;
    expect(account.authorization, isNull);
    api.request = null;
    api.pendingPoll = Completer<TokenPoll>();
    await account.signIn();
    await tester.pump(const Duration(seconds: 5));
    account.cancel();
    api.pendingPoll!.complete(
      const TokenPoll.authorized(GithubToken('late-token')),
    );
    await tester.pump();
    expect(account.user, isNull);
    expect(store.writes, 0);
    expect(account.phase, AccountPhase.signedOut);
  });

  testWidgets('expiry and disposal stop pending authorization', (tester) async {
    final api = FakeApi()..results = [];
    final account = AccountProvider(
      clientId: 'test',
      api: api,
      store: MemoryStore(),
    );
    await account.signIn();
    await tester.pump(const Duration(seconds: 30));
    expect(account.error, AccountError.expired);
    expect(account.phase, AccountPhase.signedOut);
    await account.signIn();
    account.dispose();
    final polls = api.polls;
    await tester.pump(const Duration(seconds: 40));
    expect(api.polls, polls);
    expect(api.closed, isTrue);
  });

  testWidgets(
    'restore retains offline credentials and clears revoked credentials',
    (tester) async {
      final store = MemoryStore()..token = const GithubToken('saved-token');
      final api = FakeApi()..userFailure = AccountError.network;
      final account = AccountProvider(clientId: 'test', api: api, store: store);
      addTearDown(account.dispose);
      await account.restore();
      expect(account.user, isNull);
      expect(account.canRetryRestore, isTrue);
      expect(store.token, isNotNull);
      api.userFailure = AccountError.expired;
      await account.restore();
      expect(store.token, isNull);
      expect(account.error, AccountError.expired);
      api.userFailure = null;
      store.token = const GithubToken('valid-token');
      await account.restore();
      expect(account.user?.id, 123);
      store.failClear = true;
      await account.signOut();
      expect(account.phase, AccountPhase.signedIn);
      expect(account.error, AccountError.storage);
    },
  );

  testWidgets(
    'missing configuration, browser failure and storage failure are explicit',
    (tester) async {
      final missingApi = FakeApi();
      final missing = AccountProvider(
        clientId: '',
        api: missingApi,
        store: MemoryStore(),
      );
      await missing.signIn();
      expect(missing.error, AccountError.notConfigured);
      expect(missingApi.requests, 0);
      missing.dispose();
      final store = MemoryStore()..failWrites = true;
      final account = AccountProvider(
        clientId: 'test',
        api: FakeApi(),
        store: store,
        openBrowser: (uri) async {
          expect(uri, DeviceAuthorization.verificationUri);
          return false;
        },
      );
      addTearDown(account.dispose);
      await account.signIn();
      await account.openAuthorizationPage();
      expect(account.error, AccountError.browser);
      await tester.pump(const Duration(seconds: 5));
      expect(account.error, AccountError.storage);
      expect(account.user, isNull);
      expect(store.token, isNull);
    },
  );
}
