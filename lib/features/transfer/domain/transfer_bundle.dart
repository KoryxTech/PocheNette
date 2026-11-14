/// Bundle de transfert cross-platform (Android ↔ iOS).
class TransferBundle {
  const TransferBundle({
    required this.version,
    required this.exportedAtMs,
    required this.state,
    required this.secure,
  });

  final int version;
  final int exportedAtMs;
  final Map<String, dynamic> state;
  final Map<String, String?> secure;

  Map<String, dynamic> toJson() => {
        'v': version,
        'exportedAt': exportedAtMs,
        'app': 'pochenette',
        'state': state,
        'secure': secure,
      };

  factory TransferBundle.fromJson(Map<String, dynamic> json) {
    final secureRaw = json['secure'];
    final secure = <String, String?>{};
    if (secureRaw is Map) {
      for (final entry in secureRaw.entries) {
        final value = entry.value;
        secure['${entry.key}'] = value?.toString();
      }
    }
    return TransferBundle(
      version: (json['v'] as num?)?.toInt() ?? 1,
      exportedAtMs: (json['exportedAt'] as num?)?.toInt() ?? 0,
      state: Map<String, dynamic>.from(json['state'] as Map? ?? const {}),
      secure: secure,
    );
  }
}

class TransferOffer {
  const TransferOffer({
    required this.host,
    required this.port,
    required this.token,
    required this.keyBase64Url,
    required this.qrPayload,
  });

  final String host;
  final int port;
  final String token;
  final String keyBase64Url;
  final String qrPayload;
}
