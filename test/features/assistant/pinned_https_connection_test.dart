import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/pinned_https_connection.dart';

void main() {
  late HttpServer server;
  late HttpClient client;
  setUp(() async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/assistant_tls/webpage-cert.pem')
      ..usePrivateKey('test/fixtures/assistant_tls/webpage-key.pem');
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    server.listen((request) async {
      request.response.write('HTTPS response');
      await request.response.close();
    });
    client = HttpClient()..findProxy = (_) => 'DIRECT';
  });
  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  test(
    'pinned connection performs TLS and preserves certificate hostname',
    () async {
      final trust = SecurityContext(
        withTrustedRoots: false,
      )..setTrustedCertificates('test/fixtures/assistant_tls/webpage-cert.pem');
      client.connectionFactory = (uri, _, _) =>
          connectPinnedHttps(uri, InternetAddress.loopbackIPv4, context: trust);
      final uri = Uri(scheme: 'https', host: 'webpage.test', port: server.port);
      final request = await client.getUrl(uri);
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(
        await response.transform(SystemEncoding().decoder).join(),
        'HTTPS response',
      );
    },
  );

  test('trusted certificate for another hostname is rejected', () async {
    final trust = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/fixtures/assistant_tls/webpage-cert.pem');
    client.connectionFactory = (uri, _, _) =>
        connectPinnedHttps(uri, InternetAddress.loopbackIPv4, context: trust);
    await expectLater(
      client.getUrl(Uri.parse('https://different.test:${server.port}')),
      throwsA(isA<HandshakeException>()),
    );
  });

  test('untrusted certificate is rejected', () async {
    client.connectionFactory = (uri, _, _) =>
        connectPinnedHttps(uri, InternetAddress.loopbackIPv4);
    await expectLater(
      client.getUrl(Uri.parse('https://localhost:${server.port}')),
      throwsA(isA<HandshakeException>()),
    );
  });
  test('cancelling during TLS handshake closes the connection', () async {
    final tcpServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<Socket>();
    final subscription = tcpServer.listen(accepted.complete);
    final task = await connectPinnedHttps(
      Uri.parse('https://webpage.test:${tcpServer.port}'),
      InternetAddress.loopbackIPv4,
    );
    final completion = expectLater(task.socket, throwsA(isA<Exception>()));
    final peer = await accepted.future;
    task.cancel();
    await completion.timeout(const Duration(seconds: 3));
    peer.destroy();
    await subscription.cancel();
    await tcpServer.close();
  });
}
