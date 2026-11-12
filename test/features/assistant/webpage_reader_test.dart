import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/pinned_https_connection.dart';
import 'package:lilygobox/features/assistant/data/webpage_reader.dart';
import 'package:lilygobox/features/assistant/domain/web_failure.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/error_text.dart';
import 'package:lilygobox/generated/l10n/app_localizations_en.dart';
import 'package:lilygobox/generated/l10n/app_localizations_zh.dart';

void main() {
  late HttpServer server;
  late SecurityContext trust;
  late List<String> resolved;
  late List<Uri> connected;
  late List<String> received;
  late List<String?> cookies;
  var reply = (HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write('<h1>Page</h1>');
  };
  setUp(() async {
    resolved = [];
    connected = [];
    received = [];
    cookies = [];
    trust = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/fixtures/assistant_tls/webpage-cert.pem');
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/assistant_tls/webpage-cert.pem')
      ..usePrivateKey('test/fixtures/assistant_tls/webpage-key.pem');
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    reply = (request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<h1>Page</h1>');
    };
    server.listen((request) async {
      received.add(request.uri.path);
      cookies.add(request.headers.value(HttpHeaders.cookieHeader));
      try {
        await reply(request);
        await request.response.close();
      } on IOException {
        // 取消或超时测试会主动关闭客户端连接。
      }
    });
  });
  tearDown(() => server.close(force: true));

  WebpageReader reader({
    WebAddressResolver? resolve,
    Duration timeout = const Duration(seconds: 3),
    int maxBytes = 1024 * 1024,
  }) => WebpageReader(
    timeout: timeout,
    maxBytes: maxBytes,
    resolveHost: (host) async {
      resolved.add(host);
      return resolve == null
          ? [InternetAddress('8.8.8.8')]
          : await resolve(host);
    },
    connect: (uri, address) {
      connected.add(uri);
      expect(address.address, '8.8.8.8');
      // 仅测试传输映射到隔离的本地 HTTPS 服务；生产仍固定到已验证公网 IP。
      return connectPinnedHttps(
        uri.replace(port: server.port),
        InternetAddress.loopbackIPv4,
        context: trust,
      );
    },
  );
  Matcher fails(AiWebProblem problem) => throwsA(
    isA<AiWebFailure>().having((error) => error.problem, 'problem', problem),
  );

  test('reads static text and reports final source', () async {
    final result = jsonDecode(await reader().read('https://webpage.test'));
    expect(result['ok'], isTrue);
    expect(result['url'], 'https://webpage.test');
    expect(result['untrusted_content'], '<h1>Page</h1>');
  });

  for (final status in [301, 302, 303, 307, 308]) {
    test('follows HTTP $status with fresh validation and no cookies', () async {
      reply = (request) async {
        if (request.uri.path == '/start') {
          request.response.statusCode = status;
          request.response.headers.set(HttpHeaders.locationHeader, '/final');
          request.response.cookies.add(Cookie('secret', 'value'));
        } else {
          request.response.headers.contentType = ContentType.text;
          request.response.write('Final page');
        }
      };
      final result = jsonDecode(
        await reader().read('https://webpage.test/start'),
      );
      expect(result['requested_url'], 'https://webpage.test/start');
      expect(result['url'], 'https://webpage.test/final');
      expect(result['untrusted_content'], 'Final page');
      expect(resolved, ['webpage.test', 'webpage.test']);
      expect(connected, hasLength(2));
      expect(cookies, [null, null]);
    });
  }

  for (final target in [
    'http://example.com',
    'https://127.0.0.1/',
    'https://[::1]/',
    'https://user:password@example.com',
    'https://example.com:8443/',
  ]) {
    test('blocks unsafe redirect target $target before connecting', () async {
      reply = (request) async {
        request.response.statusCode = 302;
        request.response.headers.set(HttpHeaders.locationHeader, target);
      };
      await expectLater(
        reader().read('https://webpage.test/start'),
        throwsA(isA<AiWebFailure>()),
      );
      expect(connected, hasLength(1));
    });
  }

  test('rejects redirect resolving to private or mixed addresses', () async {
    reply = (request) async {
      request.response.statusCode = 302;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'https://private.test/',
      );
    };
    await expectLater(
      reader(
        resolve: (host) async => host == 'private.test'
            ? [InternetAddress('8.8.8.8'), InternetAddress('10.0.0.1')]
            : [InternetAddress('8.8.8.8')],
      ).read('https://webpage.test'),
      fails(AiWebProblem.blockedAddress),
    );
    expect(connected, hasLength(1));
  });

  test('rechecks DNS for redirects to the same hostname', () async {
    reply = (request) async {
      request.response.statusCode = 302;
      request.response.headers.set(HttpHeaders.locationHeader, '/next');
    };
    await expectLater(
      reader(
        resolve: (_) async => [
          InternetAddress(resolved.length == 1 ? '8.8.8.8' : '127.0.0.1'),
        ],
      ).read('https://webpage.test'),
      fails(AiWebProblem.blockedAddress),
    );
    expect(connected, hasLength(1));
  });

  test('detects redirect loops', () async {
    reply = (request) async {
      request.response.statusCode = 302;
      request.response.headers.set(HttpHeaders.locationHeader, '/start');
    };
    await expectLater(
      reader().read('https://webpage.test/start'),
      fails(AiWebProblem.redirectLoop),
    );
    expect(connected, hasLength(1));
  });

  test('bounds redirect chain to five hops', () async {
    reply = (request) async {
      request.response.statusCode = 302;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        '/step' + received.length.toString(),
      );
    };
    await expectLater(
      reader().read('https://webpage.test/start'),
      fails(AiWebProblem.tooManyRedirects),
    );
    expect(connected, hasLength(6));
  });

  test('missing redirect target has a distinct error', () async {
    reply = (request) async {
      request.response.statusCode = 302;
    };
    await expectLater(
      reader().read('https://webpage.test'),
      fails(AiWebProblem.invalidRedirect),
    );
  });

  for (final status in [401, 403, 404, 429, 503]) {
    test('preserves HTTP $status without guessing its cause', () async {
      reply = (request) async {
        request.response.statusCode = status;
      };
      await expectLater(
        reader().read('https://webpage.test'),
        throwsA(
          isA<AiWebFailure>()
              .having((e) => e.problem, 'problem', AiWebProblem.httpStatus)
              .having((e) => e.toJson()['status_code'], 'status', status),
        ),
      );
    });
  }

  test(
    'rejects binary content, empty text and oversized chunked bodies',
    () async {
      reply = (request) async {
        request.response.headers.contentType = ContentType.binary;
        request.response.write('binary');
      };
      await expectLater(
        reader().read('https://webpage.test'),
        fails(AiWebProblem.contentType),
      );
      reply = (request) async {
        request.response.headers.contentType = ContentType.text;
      };
      await expectLater(
        reader().read('https://webpage.test'),
        fails(AiWebProblem.emptyContent),
      );
      reply = (request) async {
        request.response.headers.contentType = ContentType.text;
        request.response.write('a' * 32);
      };
      await expectLater(
        reader(maxBytes: 16).read('https://webpage.test'),
        fails(AiWebProblem.tooLarge),
      );
    },
  );

  test(
    'supports declared Latin-1 and rejects unknown or invalid encoding',
    () async {
      reply = (request) async {
        request.response.headers.contentType = ContentType(
          'text',
          'plain',
          charset: 'iso-8859-1',
        );
        request.response.add([99, 97, 102, 233]);
      };
      expect(
        jsonDecode(
          await reader().read('https://webpage.test'),
        )['untrusted_content'],
        'café',
      );
      reply = (request) async {
        request.response.headers.contentType = ContentType(
          'text',
          'plain',
          charset: 'unknown-encoding',
        );
        request.response.write('text');
      };
      await expectLater(
        reader().read('https://webpage.test'),
        fails(AiWebProblem.encoding),
      );
    },
  );

  test('limits decompressed response size', () async {
    reply = (request) async {
      request.response.headers.contentType = ContentType.text;
      request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.response.add(gzip.encode(utf8.encode('a' * 1024)));
    };
    await expectLater(
      reader(maxBytes: 128).read('https://webpage.test'),
      fails(AiWebProblem.tooLarge),
    );
  });

  test('total timeout covers waiting for response headers', () async {
    final gate = Completer<void>();
    reply = (request) async {
      await gate.future;
      request.response.headers.contentType = ContentType.text;
      request.response.write('Late response');
    };
    try {
      await expectLater(
        reader(
          timeout: const Duration(milliseconds: 150),
        ).read('https://webpage.test'),
        fails(AiWebProblem.timeout),
      );
    } finally {
      gate.complete();
    }
  });

  test('cancellation while awaiting headers is classified correctly', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final abort = Completer<void>();
    reply = (request) async {
      started.complete();
      await gate.future;
      request.response.headers.contentType = ContentType.text;
      request.response.write('Cancelled response');
    };
    final pending = reader().read('https://webpage.test', abort: abort.future);
    final expectation = expectLater(pending, fails(AiWebProblem.cancelled));
    await started.future;
    abort.complete();
    try {
      await expectation;
    } finally {
      gate.complete();
    }
  });

  test('classifies DNS and TLS failures', () async {
    await expectLater(
      reader(
        resolve: (_) async => throw const SocketException('DNS'),
      ).read('https://webpage.test'),
      fails(AiWebProblem.dns),
    );
    await expectLater(
      reader().read('https://wrong.test'),
      fails(AiWebProblem.tls),
    );
  });

  test('timeout during DNS prevents a later connection', () async {
    final dns = Completer<List<InternetAddress>>();
    final pending = reader(
      timeout: const Duration(milliseconds: 30),
      resolve: (_) => dns.future,
    ).read('https://webpage.test');
    await expectLater(pending, fails(AiWebProblem.timeout));
    dns.complete([InternetAddress('8.8.8.8')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(connected, isEmpty);
  });

  test('cancellation during DNS prevents a later connection', () async {
    final dns = Completer<List<InternetAddress>>();
    final abort = Completer<void>();
    final pending = reader(
      resolve: (_) => dns.future,
    ).read('https://webpage.test', abort: abort.future);
    abort.complete();
    await expectLater(
      pending.timeout(const Duration(milliseconds: 200)),
      fails(AiWebProblem.cancelled),
    );
    dns.complete([InternetAddress('8.8.8.8')]);
    await Future<void>.delayed(Duration.zero);
    expect(connected, isEmpty);
  });

  test('reserved IPv4 and all unsupported IPv6 addresses are blocked', () {
    for (final address in [
      '0.0.0.0',
      '10.0.0.1',
      '100.64.0.1',
      '127.0.0.1',
      '169.254.169.254',
      '172.16.0.1',
      '192.168.0.1',
      '192.0.2.1',
      '198.18.0.1',
      '198.51.100.1',
      '203.0.113.1',
      '224.0.0.1',
      '255.255.255.255',
      '::1',
      'fe80::1',
      'fc00::1',
      '::ffff:127.0.0.1',
      '2606:4700:4700::1111',
    ]) {
      expect(
        WebpageReader.isPublicAddress(InternetAddress(address)),
        isFalse,
        reason: address,
      );
    }
    expect(WebpageReader.isPublicAddress(InternetAddress('8.8.8.8')), isTrue);
  });

  test('error reasons are localized and omit credentials', () {
    final en = AppLocalizationsEn();
    final zh = AppLocalizationsZh();
    for (final problem in AiWebProblem.values) {
      final failure = AiWebFailure(problem, statusCode: 403);
      expect(aiErrorText(en, failure), isNot(en.aiRequestFailed));
      expect(aiErrorText(zh, failure), isNot(zh.aiRequestFailed));
    }
    try {
      WebpageReader.validateUri('https://user:secret@example.com');
      fail('Expected rejection');
    } on AiWebFailure catch (error) {
      expect(jsonEncode(error.toJson()), isNot(contains('secret')));
    }
  });
}
