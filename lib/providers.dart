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
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/providers/$logo.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }
  return IconPlate(
    bank || name == 'Banque'
        ? Icons.account_balance_outlined
        : Icons.payments_outlined,
  );
}
