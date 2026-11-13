import 'package:flutter/material.dart';

import 'design.dart';

const pageGuides = [
  (
    title: 'Lire ton tableau de bord',
    steps: [
      (
        'Choisis une période',
        'La roue répartit les dépenses par catégorie. Touche une catégorie pour filtrer l’historique.',
      ),
      (
        'Lis le reste du mois',
        'PocheNette soustrait les charges à régler du total de tes portefeuilles. Le total des soldes reste affiché dans la roue.',
      ),
      (
        'Enregistre un mouvement',
        'Utilise Dépense ou Revenu. La double flèche sert à déplacer de l’argent entre tes portefeuilles.',
      ),
    ],
  ),
  (
    title: 'Suivre tes portefeuilles',
    steps: [
      (
        'Ajoute un portefeuille',
        'Choisis le type de portefeuille. Pour un compte bancaire, sélectionne ta banque, puis saisis le solde actuel en FCFA.',
      ),
      (
        'Consulte son historique',
        'Touche une carte pour voir son solde et les opérations enregistrées.',
      ),
      (
        'Actualise avec les reçus',
        'Active la lecture des SMS dans Réglages pour mettre à jour tes soldes Mobile Money à partir des nouveaux reçus reconnus.',
      ),
    ],
  ),
  (
    title: 'Prévoir tes charges',
    steps: [
      (
        'Ajoute une échéance',
        'Renseigne le montant, la date et la fréquence. Les charges à régler d’ici la fin du mois réduisent le reste affiché sur l’accueil.',
      ),
      (
        'Modifie une charge',
        'Touche sa carte pour corriger le montant, la fréquence ou la date.',
      ),
      (
        'Marque-la comme réglée',
        'Ouvre le menu de la charge. Une charge récurrente passe à sa prochaine échéance. Saisis le paiement dans tes transactions si aucun reçu ne l’a enregistré.',
      ),
    ],
  ),
  (
    title: 'Suivre un projet d’épargne',
    steps: [
      (
        'Fixe une cible',
        'Donne un nom au projet et indique le montant à atteindre.',
      ),
      (
        'Ajoute un versement',
        'Ouvre la carte et note le montant que tu as mis de côté. PocheNette suit ta progression sans déplacer l’argent.',
      ),
      (
        'Retrouve tes versements',
        'Ouvre la carte pour voir les dates et montants enregistrés.',
      ),
    ],
  ),
  (
    title: 'Configurer PocheNette',
    steps: [
      (
        'Autorise les SMS',
        'Active la lecture et accepte la demande Android. PocheNette lit les nouveaux reçus des portefeuilles Mobile Money déjà créés.',
      ),
      (
        'Vérifie la synchronisation',
        'Utilise Actualiser les soldes pour rechercher des reçus reconnus. Les données sont traitées et stockées sur le téléphone.',
      ),
      (
        'Adapte tes catégories',
        'Ouvre Catégories pour ajouter un poste à utiliser lors de la saisie des transactions.',
      ),
    ],
  ),
];

void showPageGuide(BuildContext context, int page) {
  final guide = pageGuides[page];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: IconPlate(Icons.lightbulb_outline),
            ),
            const SizedBox(height: 12),
            Text(
              guide.title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            for (final (index, step) in guide.steps.indexed)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xffc5f6e3),
                    foregroundColor: emerald,
                    radius: 16,
                    child: Text('${index + 1}', style: numberStyle),
                  ),
                  title: Text(step.$1),
                  subtitle: Text(step.$2),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Compris'),
            ),
          ],
        ),
      ),
    ),
  );
}
