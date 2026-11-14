import 'package:flutter/material.dart';

// Catégories et modèles courants au Cameroun (FCFA).

const expenseCategories = [
  'Marché / courses',
  'Maquis / restaurant',
  'Transport (taxi, okada)',
  'Carburant',
  'Crédit téléphone',
  'Internet / data',
  'Loyer',
  'Eau (Camwater)',
  'Électricité (ENEO)',
  'Canal+ / TV',
  'Scolarité',
  'Santé / pharmacie',
  'Tontine (cotisation)',
  'Cérémonie / deuil',
  'Cadeaux',
  'Habillage',
  'Domestique / boy',
  'Autre dépense',
];

const incomeCategories = [
  'Salaire',
  'Acompte / avance',
  'Business / vente',
  'Tontine (réception)',
  'Transfert famille',
  'Freelance / prestation',
  'Agriculture / vente',
  'Cadeau reçu',
  'Remboursement',
  'Autre revenu',
];

const chargeTemplates = [
  'Loyer',
  'Électricité ENEO',
  'Eau Camwater',
  'Internet / fibre',
  'Crédit téléphone',
  'Canal+ / TV',
  'Cotisation tontine',
  'Frais de scolarité',
  'Assurance moto',
  'Assurance véhicule',
  'Gardiennage',
  'Syndic / copropriété',
  'Abonnement sport',
  'Autre charge',
];

const _categoryIcons = <String, IconData>{
  'Marché / courses': Icons.shopping_basket_outlined,
  'Maquis / restaurant': Icons.restaurant_outlined,
  'Transport (taxi, okada)': Icons.two_wheeler_outlined,
  'Carburant': Icons.local_gas_station_outlined,
  'Crédit téléphone': Icons.phone_android_outlined,
  'Internet / data': Icons.wifi_outlined,
  'Loyer': Icons.home_outlined,
  'Eau (Camwater)': Icons.water_drop_outlined,
  'Électricité (ENEO)': Icons.bolt_outlined,
  'Canal+ / TV': Icons.tv_outlined,
  'Scolarité': Icons.school_outlined,
  'Santé / pharmacie': Icons.medical_services_outlined,
  'Tontine (cotisation)': Icons.groups_outlined,
  'Cérémonie / deuil': Icons.church_outlined,
  'Cadeaux': Icons.card_giftcard_outlined,
  'Habillage': Icons.checkroom_outlined,
  'Domestique / boy': Icons.cleaning_services_outlined,
  'Autre dépense': Icons.payments_outlined,
  'Salaire': Icons.work_outline,
  'Acompte / avance': Icons.payments_outlined,
  'Business / vente': Icons.storefront_outlined,
  'Tontine (réception)': Icons.savings_outlined,
  'Transfert famille': Icons.family_restroom_outlined,
  'Freelance / prestation': Icons.handshake_outlined,
  'Agriculture / vente': Icons.agriculture_outlined,
  'Cadeau reçu': Icons.redeem_outlined,
  'Remboursement': Icons.replay_outlined,
  'Autre revenu': Icons.trending_up_outlined,
  'Électricité ENEO': Icons.bolt_outlined,
  'Eau Camwater': Icons.water_drop_outlined,
  'Internet / fibre': Icons.router_outlined,
  'Cotisation tontine': Icons.groups_outlined,
  'Frais de scolarité': Icons.school_outlined,
  'Assurance moto': Icons.two_wheeler_outlined,
  'Assurance véhicule': Icons.directions_car_outlined,
  'Gardiennage': Icons.security_outlined,
  'Syndic / copropriété': Icons.apartment_outlined,
  'Abonnement sport': Icons.fitness_center_outlined,
  'Autre charge': Icons.event_note_outlined,
};

const _keywordIcons = <String, IconData>{
  'marché': Icons.shopping_basket_outlined,
  'course': Icons.shopping_basket_outlined,
  'maquis': Icons.restaurant_outlined,
  'restaurant': Icons.restaurant_outlined,
  'taxi': Icons.local_taxi_outlined,
  'okada': Icons.two_wheeler_outlined,
  'transport': Icons.directions_bus_outlined,
  'carburant': Icons.local_gas_station_outlined,
  'téléphone': Icons.phone_android_outlined,
  'telephone': Icons.phone_android_outlined,
  'internet': Icons.wifi_outlined,
  'data': Icons.wifi_outlined,
  'fibre': Icons.router_outlined,
  'loyer': Icons.home_outlined,
  'eau': Icons.water_drop_outlined,
  'camwater': Icons.water_drop_outlined,
  'électricité': Icons.bolt_outlined,
  'electricite': Icons.bolt_outlined,
  'eneo': Icons.bolt_outlined,
  'canal': Icons.tv_outlined,
  'scolarit': Icons.school_outlined,
  'santé': Icons.medical_services_outlined,
  'sante': Icons.medical_services_outlined,
  'pharmacie': Icons.local_pharmacy_outlined,
  'tontine': Icons.groups_outlined,
  'cérémonie': Icons.church_outlined,
  'ceremonie': Icons.church_outlined,
  'deuil': Icons.church_outlined,
  'cadeau': Icons.card_giftcard_outlined,
  'habillage': Icons.checkroom_outlined,
  'domestique': Icons.cleaning_services_outlined,
  'salaire': Icons.work_outline,
  'acompte': Icons.payments_outlined,
  'business': Icons.storefront_outlined,
  'vente': Icons.storefront_outlined,
  'famille': Icons.family_restroom_outlined,
  'freelance': Icons.handshake_outlined,
  'agriculture': Icons.agriculture_outlined,
  'rembourse': Icons.replay_outlined,
  'assurance': Icons.verified_user_outlined,
  'moto': Icons.two_wheeler_outlined,
  'véhicule': Icons.directions_car_outlined,
  'vehicule': Icons.directions_car_outlined,
  'gardien': Icons.security_outlined,
  'syndic': Icons.apartment_outlined,
  'sport': Icons.fitness_center_outlined,
  'transfert': Icons.swap_horiz_outlined,
  'revenu': Icons.trending_up_outlined,
  'dépense': Icons.payments_outlined,
  'depense': Icons.payments_outlined,
};

List<String> defaultCategories() => [
  ...expenseCategories,
  ...incomeCategories,
];

void mergeDefaultCategories(List<String> categories) {
  for (final name in defaultCategories()) {
    if (!categories.contains(name)) categories.add(name);
  }
  categories.removeWhere(
    (name) =>
        name == 'Alimentation' ||
        name == 'Transport' ||
        name == 'Logement' ||
        name == 'Autre',
  );
  if (!categories.contains('Autre dépense')) {
    categories.add('Autre dépense');
  }
}

/// Catégories proposées selon le type d’opération (dépense vs revenu).
List<String> categoriesForTransaction({
  required bool isIncome,
  required List<String> stored,
  List<String> extraExpenses = const [],
  List<String> extraIncomes = const [],
}) {
  final defaults = isIncome ? incomeCategories : expenseCategories;
  final opposite = isIncome ? expenseCategories : incomeCategories;
  final extras = isIncome ? extraIncomes : extraExpenses;
  final oppositeExtras = isIncome ? extraExpenses : extraIncomes;
  final result = <String>[...defaults];
  for (final name in extras) {
    if (!result.contains(name)) result.add(name);
  }
  for (final name in stored) {
    if (defaults.contains(name) || opposite.contains(name)) continue;
    if (oppositeExtras.contains(name)) continue;
    if (!result.contains(name)) result.add(name);
  }
  return result;
}

const _shortCategoryLabels = <String, String>{
  'Marché / courses': 'Marché',
  'Maquis / restaurant': 'Maquis',
  'Transport (taxi, okada)': 'Transport',
  'Carburant': 'Carburant',
  'Crédit téléphone': 'Crédit',
  'Internet / data': 'Internet',
  'Loyer': 'Loyer',
  'Eau (Camwater)': 'Eau',
  'Électricité (ENEO)': 'ENEO',
  'Canal+ / TV': 'Canal+',
  'Scolarité': 'Scolarité',
  'Santé / pharmacie': 'Santé',
  'Tontine (cotisation)': 'Tontine',
  'Cérémonie / deuil': 'Cérémonie',
  'Cadeaux': 'Cadeaux',
  'Habillage': 'Habillage',
  'Domestique / boy': 'Domestique',
  'Autre dépense': 'Autres',
  'Salaire': 'Salaire',
  'Acompte / avance': 'Acompte',
  'Business / vente': 'Business',
  'Tontine (réception)': 'Tontine',
  'Transfert famille': 'Famille',
  'Freelance / prestation': 'Freelance',
  'Agriculture / vente': 'Agriculture',
  'Cadeau reçu': 'Cadeau',
  'Remboursement': 'Rembours.',
  'Autre revenu': 'Autres',
  'Électricité ENEO': 'ENEO',
  'Eau Camwater': 'Eau',
  'Internet / fibre': 'Fibre',
  'Cotisation tontine': 'Tontine',
  'Frais de scolarité': 'Scolarité',
  'Assurance moto': 'Ass. moto',
  'Assurance véhicule': 'Ass. auto',
  'Gardiennage': 'Gardien',
  'Syndic / copropriété': 'Syndic',
  'Abonnement sport': 'Sport',
  'Autre charge': 'Autres',
};

/// Libellé court pour légendes / chips (données inchangées).
String shortCategoryLabel(String name) =>
    _shortCategoryLabels[name] ?? name;

IconData categoryIcon(String? name) {
  if (name == null || name.trim().isEmpty) {
    return Icons.label_outline;
  }
  final exact = _categoryIcons[name];
  if (exact != null) return exact;
  final lower = name.toLowerCase();
  for (final entry in _keywordIcons.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return Icons.label_outline;
}
