import 'package:flutter_test/flutter_test.dart';
import 'package:pochenette/receipt.dart';

void main() {
  test('Orange Money avec référence et montant signé', () {
    final receipt = Receipt.parse(
      'Orange Money',
      'Paiement effectue avec succes. Vous avez paye -8 500 FCFA à la pharmacie. Frais: 0 FCFA. Nouveau solde Orange Money: 124 300 FCFA. Ref: MP260311.1204.C00452.',
    );
    expect(receipt?.balance, 124300);
    expect(receipt?.delta, -8500);
    expect(receipt?.reference, 'MP260311.1204.C00452');
  });

  test('MTN MoMo avec un espace fine insécable', () {
    final receipt = Receipt.parse(
      'MoMo',
      'Trans. ID: 8941208920. Paiement réussi de 14 500 FCFA. Nouveau solde MoMo: 300 700 FCFA.',
    );
    expect(receipt?.balance, 300700);
    expect(receipt?.delta, -14500);
    expect(receipt?.reference, '8941208920');
  });

  test('Rejette les messages inconnus, échoués ou sans solde', () {
    expect(Receipt.parse('Particulier', 'Nouveau solde : 10 FCFA'), isNull);
    expect(
      Receipt.parse('MoMo', 'Paiement échoué. Nouveau solde : 10 FCFA'),
      isNull,
    );
    expect(Receipt.parse('MoMo', 'Vous avez payé 10 FCFA'), isNull);
  });
}
