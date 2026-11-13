class Receipt {
  const Receipt(this.provider, this.balance, this.reference, this.delta);

  final String provider;
  final int balance;
  final String? reference;
  final int? delta;

  static final _balance = RegExp(
    r'(?:nouveau solde|solde (?:actuel|disponible)|new balance|available balance|your balance|votre solde)'
    r'(?:\s+(?:orange money|momo|mtn momo))?\s*(?:est(?:\s+de)?|is|:)??\s*:?\s*(-?[0-9]+(?:[ ,\u00a0\u202f.][0-9]{3})*)\s*(?:FCFA|XAF|F\s*CFA)\b',
    caseSensitive: false,
  );
  static final _reference = RegExp(
    r'(?:trans\.?\s*id|transaction\s*id|id\s*(?:de\s*transaction)?|r[eé]f(?:[eé]rence)?\.?)\s*[:#]\s*([a-z0-9][a-z0-9.-]{4,})',
    caseSensitive: false,
  );
  static const _amount =
      r'[−-]?([0-9]+(?:[ ,\u00a0\u202f.][0-9]{3})*)\s*(?:FCFA|XAF|F\s*CFA)\b';

  static int _integer(String value) =>
      int.parse(value.replaceAll(RegExp(r'[^0-9-]'), ''));

  static Receipt? parse(String sender, String body) {
    final provider = switch (sender.trim().toLowerCase()) {
      'orangemoney' || 'orange money' => 'Orange Money',
      'mtnmomo' ||
      'mtn momo' ||
      'momo' ||
      'mobilemoney' ||
      'mobile money' => 'MTN MoMo',
      _ => null,
    };
    if (provider == null) return null;
    if (RegExp(
      r'(?:^|[\s.:])(?:[eé]chou[eé]|[eé]chec|failed|pending|en attente)(?=$|[\s.,:;!])',
      caseSensitive: false,
    ).hasMatch(body)) {
      return null;
    }
    final match = _balance.firstMatch(body);
    if (match == null) return null;
    final debit = RegExp(
      '(?:avez pay[eé]|paiement réussi de|vous avez envoy[eé]|vous avez retir[eé]|you (?:paid|sent|withdrew))\\s+$_amount',
      caseSensitive: false,
    ).firstMatch(body);
    final credit = RegExp(
      '(?:avez re[çc]u|you received)\\s+$_amount',
      caseSensitive: false,
    ).firstMatch(body);
    final fees = RegExp(
      '(?:frais|fees)\\s*:\\s*$_amount',
      caseSensitive: false,
    ).firstMatch(body);
    final fee = fees == null ? 0 : _integer(fees[1]!);
    final delta = debit != null
        ? -_integer(debit[1]!) - fee
        : credit != null
        ? _integer(credit[1]!) - fee
        : null;
    return Receipt(
      provider,
      _integer(match[1]!),
      _reference.firstMatch(body)?[1]?.replaceFirst(RegExp(r'\.+$'), ''),
      delta,
    );
  }
}
