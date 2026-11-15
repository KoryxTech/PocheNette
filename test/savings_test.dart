import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pochenette/main.dart';

void main() {
  testWidgets('Un objectif garde ses sources et se ferme dès la cible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now().millisecondsSinceEpoch;
    var state = <String, dynamic>{
      'onboardingDone': true,
      'localeCode': 'fr',
      'wallets': [
        {'id': 'cash', 'provider': 'Espèces', 'balance': 1000, 'at': 0},
      ],
      'operations': [],
      'charges': [],
      'goals': [
        {
          'name': 'Voyage',
          'amount': 350,
          'payments': [
            {'amount': 50, 'at': now},
          ],
        },
      ],
    };
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('pochenette/local'),
      (call) async {
        if (call.method == 'load') return jsonEncode(state);
        if (call.method == 'save') {
          state = jsonDecode(call.arguments as String) as Map<String, dynamic>;
        }
        return null;
      },
    );

    Future<void> tap(String label) async {
      final item = find.text(label).last;
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

    Future<void> openGoal() async {
      await tap('Épargne');
      await tap('Voyage');
    }

    await tester.pumpWidget(const PocheNette());
    await tester.pumpAndSettle();
    await tap('Épargne');
    expect(find.text('300 FCFA à épargner'), findsOneWidget);
    expect(find.text('Ajouter un versement'), findsOneWidget);
    expect(find.text('Historique des versements'), findsNothing);
    await tap('Voyage');
    expect(find.textContaining('Source non renseignée'), findsOneWidget);
    await tap('Ajouter un versement');
    expect(find.text('Portefeuille source'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '100');
    await tap('Enregistrer');
    expect(state['goals'][0]['payments'][1]['wallet'], 'cash');
    expect(find.textContaining('· Espèces'), findsOneWidget);

    await tap('Configurer l’épargne automatique');
    await tester.enterText(find.byType(TextFormField), '25');
    await tap('Enregistrer');
    expect(state['goals'][0]['incomeCategory'], 'Salaire');
    expect(state['goals'][0]['incomePercent'], 25);

    await tap('Accueil');
    await tap('Revenu');
    await tester.enterText(find.byType(TextFormField).first, '1000');
    await tap('Ajouter le revenu');
    expect(state['operations'].single['delta'], 1000);
    expect(state['goals'][0]['payments'][2], containsPair('amount', 200));
    expect(state['goals'][0]['payments'][2], containsPair('automatic', true));

    await tap('Épargne');
    expect(tester.takeException(), isNull);
    expect(find.text('Objectif atteint'), findsOneWidget);
    expect(find.text('Historique des versements'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const PocheNette());
    await tester.pumpAndSettle();
    await openGoal();
    expect(find.text('Objectif atteint'), findsOneWidget);
    expect(find.text('Ajouter un versement'), findsNothing);
    expect(
      find.textContaining('Espèces · Épargne automatique'),
      findsOneWidget,
    );
    await tap('Poches');
    expect(find.text('1 700 FCFA'), findsWidgets);
  });
}
