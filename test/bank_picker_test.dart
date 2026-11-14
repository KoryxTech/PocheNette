import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pochenette/main.dart';

void main() {
  testWidgets('Deux banques apparaissent séparément dans les portefeuilles', (
    tester,
  ) async {
    const channel = MethodChannel('pochenette/local');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'load') {
          return jsonEncode({
            'onboardingDone': true,
            'localeCode': 'fr',
            'wallets': <dynamic>[],
            'operations': <dynamic>[],
            'charges': <dynamic>[],
            'goals': <dynamic>[],
            'seen': <dynamic>[],
            'enabled': false,
            'since': 0,
            'categories': <dynamic>[],
          });
        }
        if (call.method == 'secureGet') return null;
        if (call.method == 'permission') return false;
        if (call.method == 'save') return null;
        return null;
      },
    );
    await tester.pumpWidget(const PocheNette());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poches'));
    await tester.pumpAndSettle();

    for (final bank in ['Afriland First Bank', 'Ecobank']) {
      await tester.tap(find.text('Ajouter un portefeuille'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Banque'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Banque'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(bank));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '12 500');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Afriland First Bank'), findsOneWidget);
    expect(find.text('Ecobank'), findsOneWidget);
    expect(find.text('25 000 FCFA'), findsOneWidget);
  });
}
