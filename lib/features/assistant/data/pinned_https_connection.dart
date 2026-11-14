/*
 * @Description: 为已校验的公网地址建立保留域名校验的 HTTPS 连接。
 */

import 'dart:io';

/// 固定连接地址，同时保留原始域名用于 TLS SNI 和证书验证。
Future<ConnectionTask<Socket>> connectPinnedHttps(
  Uri uri,
  InternetAddress address, {
  SecurityContext? context,
}) async {
  final tcp = await Socket.startConnect(address, uri.port);
  Socket? active;
  var cancelled = false;
  final secured = tcp.socket.then<Socket>((socket) async {
    active = socket;
    if (cancelled) {
      socket.destroy();
      throw const SocketException('Connection cancelled');
    }
    try {
      final secure = await SecureSocket.secure(
        socket,
        host: uri.host,
        context: context,
      );
      active = secure;
      if (cancelled) {
        secure.destroy();
        throw const SocketException('Connection cancelled');
      }
      return secure;
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  });
  return ConnectionTask.fromSocket(secured, () {
    cancelled = true;
    tcp.cancel();
    active?.destroy();
  });
}
