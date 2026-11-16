import 'package:flutter_test/flutter_test.dart';
import 'package:pochenette/features/debts/domain/debt_constants.dart';

void main() {
  group('availableBalance', () {
    test('retrait les charges et dettes, ignore les créances', () {
      final debts = <Map<String, dynamic>>[
        {
          'kind': debtKindDette,
          'amount': 20000,
          'status': debtStatusOpen,
          'date': '2026-11-20',
        },
        {
          'kind': debtKindCreance,
          'amount': 50000,
          'status': debtStatusOpen,
          'date': '2026-11-22',
        },
        {
          'kind': debtKindDette,
          'amount': 5000,
          'status': debtStatusSettled,
          'date': '2026-11-10',
        },
      ];

      expect(openDebtsTotal(debts), 20000);
      expect(openReceivablesTotal(debts), 50000);
      expect(
        availableBalance(
          walletTotal: 100000,
          upcomingCharges: 15000,
          debts: debts,
        ),
        65000,
      );
    });

    test('trie les ouvertes avant les réglées', () {
      final debts = <Map<String, dynamic>>[
        {
          'kind': debtKindDette,
          'amount': 1,
          'status': debtStatusSettled,
          'date': '2026-11-01',
        },
        {
          'kind': debtKindCreance,
          'amount': 2,
          'status': debtStatusOpen,
          'date': '2026-12-01',
        },
      ];
      sortDebtsByDueDate(debts);
      expect(debts.first['status'], debtStatusOpen);
    });
  });
}
