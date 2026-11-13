import 'package:flutter/material.dart';

import 'design.dart';

const bankNames = [
  'Afriland First Bank',
  'BICEC',
  'Ecobank',
  'General Bank of Cameroon',
  'UBA',
  'SCB Cameroun',
  'CCA Bank',
  'Commercial Bank of Cameroon',
  'BGFIBank Cameroun',
  'AFG Bank Cameroun',
];

const providerLogos = {
  'Orange Money': 'orange',
  'MTN MoMo': 'mtn',
  'Wave': 'wave',
  'Afriland First Bank': 'afriland',
  'BICEC': 'bicec',
  'Ecobank': 'ecobank',
  'General Bank of Cameroon': 'gbc',
  'UBA': 'uba',
  'SCB Cameroun': 'scb',
  'CCA Bank': 'cca',
  'Commercial Bank of Cameroon': 'cbc',
  'BGFIBank Cameroun': 'bgfi',
  'AFG Bank Cameroun': 'afg',
  'Banque Atlantique': 'afg',
};

Widget providerMark(String name, {bool bank = false}) {
  final logo = providerLogos[name];
  if (logo != null) {
    return Container(
      width: 72,
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      child: Image.asset('assets/providers/$logo.png', fit: BoxFit.contain),
    );
  }
  return IconPlate(
    bank || name == 'Banque'
        ? Icons.account_balance_outlined
        : Icons.payments_outlined,
  );
}
