import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/web_failure.dart';
import 'pinned_https_connection.dart';

typedef WebAddressResolver =
    Future<List<InternetAddress>> Function(String host);
typedef WebConnector =
    Future<ConnectionTask<Socket>> Function(Uri uri, InternetAddress address);

/// 读取公开静态文本；逐跳检查地址，禁止代理、凭据与私网连接。
class WebpageReader {
  WebpageReader({
    WebAddressResolver? resolveHost,
    WebConnector? connect,
    this.timeout = const Duration(seconds: 30),
    this.maxBytes = 1024 * 1024,
  }) : _resolveHost = resolveHost ?? _resolveIpv4,
       _connect = connect ?? connectPinnedHttps;

  static const maxRedirects = 5;
  final WebAddressResolver _resolveHost;
  final WebConnector _connect;
  final Duration timeout;
  final int maxBytes;

  static Future<List<InternetAddress>> _resolveIpv4(String host) =>
      InternetAddress.lookup(host, type: InternetAddressType.IPv4);

  static Uri validateUri(Object? value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      throw const AiWebFailure(AiWebProblem.invalidUrl);
    }
    if (uri.userInfo.isNotEmpty) {
      throw const AiWebFailure(AiWebProblem.credentialsNotAllowed);
    }
    if (uri.scheme != 'https') {
      throw const AiWebFailure(AiWebProblem.unsupportedScheme);
    }
    if (uri.port != 443) {
      throw const AiWebFailure(AiWebProblem.unsupportedPort);
    }
    return uri.removeFragment();
  }

  static bool isPublicAddress(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final b = address.rawAddress;
    return !(b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && (b[1] == 168 || b[1] == 0)) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
        (b[0] == 198 && (b[1] == 18 || b[1] == 19)) ||
        (b[0] == 198 && b[1] == 51 && b[2] == 100) ||
        (b[0] == 203 && b[1] == 0 && b[2] == 113));
  }

  Future<String> read(Object? value, {Future<void>? abort}) async {
    final original = validateUri(value);
    var current = original;
    HttpClient? activeClient;
    var cancelled = false;
    var finished = false;
    final cancellation = Completer<String>();
    void checkCancelled() {
      if (cancelled) throw AiWebFailure(AiWebProblem.cancelled, url: current);
    }

    unawaited(
      abort?.then((_) {
        if (!finished) {
          cancelled = true;
          activeClient?.close(force: true);
          cancellation.completeError(
            AiWebFailure(AiWebProblem.cancelled, url: current),
          );
        }
      }),
    );

    Future<String> fetch() async {
      final visited = <Uri>{};
      var redirects = 0;
      while (true) {
        checkCancelled();
        if (!visited.add(current)) {
          throw AiWebFailure(AiWebProblem.redirectLoop, url: current);
        }
        final literal = InternetAddress.tryParse(current.host);
        if (literal != null && !isPublicAddress(literal)) {
          throw AiWebFailure(AiWebProblem.blockedAddress, url: current);
        }
        List<InternetAddress> addresses;
        try {
          addresses = await _resolveHost(
            current.host,
          ).timeout(const Duration(seconds: 10));
        } on SocketException {
          checkCancelled();
          throw AiWebFailure(AiWebProblem.dns, url: current);
        }
        checkCancelled();
        if (addresses.isEmpty) {
          throw AiWebFailure(AiWebProblem.dns, url: current);
        }
        if (addresses.any((address) => !isPublicAddress(address))) {
          throw AiWebFailure(AiWebProblem.blockedAddress, url: current);
        }
        // 每一跳使用新客户端，避免复用旧连接或跨源携带 Cookie。
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15)
          ..findProxy = ((_) => 'DIRECT')
          ..connectionFactory = (uri, _, _) async {
            checkCancelled();
            return _connect(uri, addresses.first);
          };
        activeClient = client;
        try {
          final request = await client.getUrl(current);
          checkCancelled();
          request.followRedirects = false;
          final response = await request.close();
          final status = response.statusCode;
          if (const {301, 302, 303, 307, 308}.contains(status)) {
            final location = response.headers.value(HttpHeaders.locationHeader);
            Uri next;
            try {
              if (location == null || location.trim().isEmpty) {
                throw const FormatException();
              }
              next = validateUri(current.resolve(location).toString());
            } on AiWebFailure catch (error) {
              throw AiWebFailure(
                error.problem,
                url: current,
                statusCode: status,
              );
            } on FormatException {
              throw AiWebFailure(
                AiWebProblem.invalidRedirect,
                url: current,
                statusCode: status,
              );
            }
            if (redirects >= maxRedirects) {
              throw AiWebFailure(AiWebProblem.tooManyRedirects, url: current);
            }
            redirects++;
            current = next;
            continue;
          }
          if (status < 200 || status >= 300) {
            throw AiWebFailure(
              AiWebProblem.httpStatus,
              url: current,
              statusCode: status,
            );
          }
          final contentType = response.headers.contentType;
          final mime = contentType?.mimeType ?? '';
          if (!mime.startsWith('text/') && mime != 'application/json') {
            throw AiWebFailure(AiWebProblem.contentType, url: current);
          }
          if (response.contentLength > maxBytes) {
            throw AiWebFailure(AiWebProblem.tooLarge, url: current);
          }
          final bytes = <int>[];
          await for (final chunk in response) {
            checkCancelled();
            if (bytes.length + chunk.length > maxBytes) {
              throw AiWebFailure(AiWebProblem.tooLarge, url: current);
            }
            bytes.addAll(chunk);
          }
          checkCancelled();
          final charset = contentType?.charset ?? 'utf-8';
          final encoding = Encoding.getByName(charset);
          if (encoding == null) {
            throw AiWebFailure(AiWebProblem.encoding, url: current);
          }
          String content;
          try {
            content = encoding.decode(bytes);
          } on FormatException {
            throw AiWebFailure(AiWebProblem.encoding, url: current);
          }
          if (content.trim().isEmpty) {
            throw AiWebFailure(AiWebProblem.emptyContent, url: current);
          }
          return jsonEncode({
            'ok': true,
            'requested_url': original.toString(),
            'url': current.toString(),
            'content_type': mime,
            'untrusted_content': content,
          });
        } finally {
          client.close(force: true);
        }
      }
    }

    try {
      return await Future.any([fetch(), cancellation.future]).timeout(timeout);
    } on TimeoutException {
      checkCancelled();
      throw AiWebFailure(AiWebProblem.timeout, url: current);
    } on TlsException {
      checkCancelled();
      throw AiWebFailure(AiWebProblem.tls, url: current);
    } on SocketException {
      checkCancelled();
      throw AiWebFailure(AiWebProblem.connection, url: current);
    } on HttpException {
      checkCancelled();
      throw AiWebFailure(AiWebProblem.connection, url: current);
    } finally {
      finished = true;
      // timeout 不会取消异步函数，后续 DNS 完成时仍需阻止建立新连接。
      cancelled = true;
      activeClient?.close(force: true);
    }
  }
}
