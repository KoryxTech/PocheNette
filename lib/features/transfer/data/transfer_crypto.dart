import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

class TransferCrypto {
  TransferCrypto._();

  static final _random = Random.secure();

  static Uint8List randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  static String toBase64Url(Uint8List bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static Uint8List fromBase64Url(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final mod = normalized.length % 4;
    if (mod > 0) {
      normalized += '=' * (4 - mod);
    }
    return Uint8List.fromList(base64Decode(normalized));
  }

  /// AES-256-CBC : IV (16) + ciphertext.
  static Uint8List encryptUtf8(String plaintext, Uint8List keyBytes) {
    final key = enc.Key(keyBytes);
    final iv = enc.IV(randomBytes(16));
    final encryptor = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encryptor.encrypt(plaintext, iv: iv);
    return Uint8List.fromList([...iv.bytes, ...encrypted.bytes]);
  }

  static String decryptUtf8(Uint8List blob, Uint8List keyBytes) {
    if (blob.length < 17) {
      throw const FormatException('Paquet de transfert invalide');
    }
    final iv = enc.IV(blob.sublist(0, 16));
    final data = enc.Encrypted(blob.sublist(16));
    final key = enc.Key(keyBytes);
    final encryptor = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encryptor.decrypt(data, iv: iv);
  }
}
