import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pochenette/l10n/l10n.dart';

void main() {
  test('L10n traduit les libellés clés en anglais', () {
    const en = L10n(Locale('en'));
    const fr = L10n(Locale('fr'));

    expect(fr.t('Accueil'), 'Accueil');
    expect(en.t('Accueil'), 'Home');
    expect(en.t('Réglages'), 'Settings');
    expect(en.t('Dépense'), 'Expense');
    expect(en.navLabels.first, 'Home');
    expect(en.month(1), 'January');
    expect(fr.month(1), 'Janvier');
  });
}
