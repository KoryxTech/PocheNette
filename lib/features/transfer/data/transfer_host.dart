import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:network_info_plus/network_info_plus.dart';

import '../domain/transfer_bundle.dart';
import 'transfer_crypto.dart';

typedef TransferDownloaded = void Function();

class TransferHost {
  HttpServer? _server;
  TransferDownloaded? onDownloaded;

  Future<String?> _localIpv4() async {
    try {
      final wifi = await NetworkInfo().getWifiIP();
      if (wifi != null && wifi.isNotEmpty && wifi != '0.0.0.0') {
        return wifi;
      }
    } catch (_) {}
    for (final interface in await NetworkInterface.list(
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    )) {
      for (final addr in interface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return null;
  }

  Future<TransferOffer> start({
    required TransferBundle bundle,
  }) async {
    await stop();
    final host = await _localIpv4();
    if (host == null) {
      throw StateError(
        'Impossible de trouver l’IP Wi‑Fi. '
        'Connecte les deux téléphones au même Wi‑Fi '
        '(ou active un hotspot).',
      );
    }

    final tokenBytes = TransferCrypto.randomBytes(16);
    final keyBytes = TransferCrypto.randomBytes(32);
    final token = TransferCrypto.toBase64Url(tokenBytes);
    final key = TransferCrypto.toBase64Url(keyBytes);
    final plaintext = jsonEncode(bundle.toJson());
    final compressed = gzip.encode(utf8.encode(plaintext));
    final encrypted = TransferCrypto.encryptUtf8(
      base64Encode(compressed),
      keyBytes,
    );

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    unawaited(_serve(server, token: token, body: encrypted));

    final port = server.port;
    final qr =
        'pochenette://transfer?v=1&h=${Uri.encodeComponent(host)}'
        '&p=$port&t=${Uri.encodeComponent(token)}'
        '&k=${Uri.encodeComponent(key)}';

    return TransferOffer(
      host: host,
      port: port,
      token: token,
      keyBase64Url: key,
      qrPayload: qr,
    );
  }

  Future<void> _serve(
    HttpServer server, {
    required String token,
    required Uint8List body,
  }) async {
    await for (final request in server) {
      try {
        if (request.method == 'GET' && request.uri.path == '/v1/hello') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'app': 'pochenette', 'ok': true}));
          await request.response.close();
          continue;
        }
        if (request.method == 'GET' && request.uri.path == '/v1/transfer') {
          final auth = request.headers.value(HttpHeaders.authorizationHeader);
          if (auth != 'Bearer $token') {
            request.response.statusCode = HttpStatus.forbidden;
            await request.response.close();
            continue;
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.binary
            ..headers.contentLength = body.length
            ..add(body);
          await request.response.close();
          onDownloaded?.call();
          continue;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
