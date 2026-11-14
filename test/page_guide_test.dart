import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pochenette/main.dart';

void main() {
  testWidgets('Les cinq onglets ouvrent chacun leur guide', (tester) async {
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
        return null;
      },
    );
    await tester.pumpWidget(const PocheNette());
    await tester.pumpAndSettle();

    const guides = {
      'Accueil': 'Lire ton tableau de bord',
      'Poches': 'Suivre tes portefeuilles',
      'Charges': 'Prévoir tes charges',
      'Épargne': 'Suivre un projet d’épargne',
      'Réglages': 'Configurer PocheNette',
    };

    for (final entry in guides.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(entry.key),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Guide rapide'));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      await tester.ensureVisible(find.text('Compris'));
      await tester.tap(find.text('Compris'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
