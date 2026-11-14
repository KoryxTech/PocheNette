import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/transfer_bundle.dart';
import 'transfer_crypto.dart';

class TransferPairing {
  const TransferPairing({
    required this.host,
    required this.port,
    required this.token,
    required this.keyBase64Url,
  });

  final String host;
  final int port;
  final String token;
  final String keyBase64Url;

  factory TransferPairing.fromQr(String raw) {
    final uri = Uri.parse(raw.trim());
    if (uri.scheme != 'pochenette' || uri.host != 'transfer') {
      throw const FormatException('QR PocheNette invalide');
    }
    final host = uri.queryParameters['h'];
    final portRaw = uri.queryParameters['p'];
    final token = uri.queryParameters['t'];
    final key = uri.queryParameters['k'];
    final port = int.tryParse(portRaw ?? '');
    if (host == null ||
        host.isEmpty ||
        port == null ||
        port <= 0 ||
        token == null ||
        token.isEmpty ||
        key == null ||
        key.isEmpty) {
      throw const FormatException('QR incomplet');
    }
    return TransferPairing(
      host: host,
      port: port,
      token: token,
      keyBase64Url: key,
    );
  }
}

class TransferClient {
  Future<TransferBundle> fetch(TransferPairing pairing) async {
    final base = 'http://${pairing.host}:${pairing.port}';
    final hello = await http
        .get(Uri.parse('$base/v1/hello'))
        .timeout(const Duration(seconds: 8));
    if (hello.statusCode != 200) {
      throw HttpException('Appareil source injoignable (${hello.statusCode})');
    }
    final helloJson = jsonDecode(hello.body);
    if (helloJson is! Map || helloJson['app'] != 'pochenette') {
      throw const FormatException('Réponse inattendue de l’appareil source');
    }

    final response = await http
        .get(
          Uri.parse('$base/v1/transfer'),
          headers: {'Authorization': 'Bearer ${pairing.token}'},
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw HttpException('Transfert refusé (${response.statusCode})');
    }

    final key = TransferCrypto.fromBase64Url(pairing.keyBase64Url);
    final encrypted = Uint8List.fromList(response.bodyBytes);
    final encodedGzip = TransferCrypto.decryptUtf8(encrypted, key);
    final compressed = base64Decode(encodedGzip);
    final jsonText = utf8.decode(gzip.decode(compressed));
    final map = jsonDecode(jsonText);
    if (map is! Map<String, dynamic>) {
      throw const FormatException('Données de transfert illisibles');
    }
    return TransferBundle.fromJson(map);
  }
}
