// Constantes et helpers purs pour dettes / créances.
// Aucune dépendance Flutter — domaine uniquement.

const String debtKindDette = 'dette';
const String debtKindCreance = 'creance';
const String debtStatusOpen = 'open';
const String debtStatusSettled = 'settled';

const String debtExpenseLabel = 'Remboursement dette';
const String debtIncomeLabel = 'Encaissement créance';

bool isOpenDebt(Map<String, dynamic> debt) =>
    (debt['status'] as String? ?? debtStatusOpen) == debtStatusOpen;

bool isDette(Map<String, dynamic> debt) =>
    (debt['kind'] as String? ?? debtKindDette) == debtKindDette;

bool isCreance(Map<String, dynamic> debt) =>
    (debt['kind'] as String? ?? '') == debtKindCreance;

int debtAmount(Map<String, dynamic> debt) {
  final value = debt['amount'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.replaceAll(' ', '')) ?? 0;
  return 0;
}

/// Dettes ouvertes (je dois) — traitées comme charges sur le solde disponible.
int openDebtsTotal(List<Map<String, dynamic>> debts) {
  var sum = 0;
  for (final debt in debts) {
    if (isOpenDebt(debt) && isDette(debt)) {
      sum += debtAmount(debt);
    }
  }
  return sum;
}

/// Créances ouvertes (on me doit) — non réalisées tant que non validées.
int openReceivablesTotal(List<Map<String, dynamic>> debts) {
  var sum = 0;
  for (final debt in debts) {
    if (isOpenDebt(debt) && isCreance(debt)) {
      sum += debtAmount(debt);
    }
  }
  return sum;
}

/// Solde réellement disponible : liquidités − charges du mois − dettes ouvertes.
int availableBalance({
  required int walletTotal,
  required int upcomingCharges,
  required List<Map<String, dynamic>> debts,
}) {
  return walletTotal - upcomingCharges - openDebtsTotal(debts);
}

List<Map<String, dynamic>> openDebtsOfKind(
  List<Map<String, dynamic>> debts,
  String kind,
) {
  return debts
      .where(
        (debt) =>
            isOpenDebt(debt) &&
            (debt['kind'] as String? ?? debtKindDette) == kind,
      )
      .toList();
}

void sortDebtsByDueDate(List<Map<String, dynamic>> debts) {
  debts.sort((a, b) {
    final aOpen = isOpenDebt(a);
    final bOpen = isOpenDebt(b);
    if (aOpen != bOpen) return aOpen ? -1 : 1;
    return (a['date'] as String? ?? '').compareTo(b['date'] as String? ?? '');
  });
}
