import 'package:flutter/material.dart';

import 'design.dart';
import 'l10n/l10n.dart';

List<({String title, List<(String, String)> steps})> pageGuides(L10n l10n) => [
  (
    title: l10n.t('Lire ton tableau de bord'),
    steps: [
      (
        l10n.t('Choisis une période'),
        l10n.t(
          'La roue répartit les dépenses par catégorie. Touche une catégorie pour filtrer l’historique.',
        ),
      ),
      (
        l10n.t('Lis le solde disponible'),
        l10n.t(
          'Le solde réellement disponible retire les charges du mois et les dettes ouvertes. Les créances restent hors solde tant que tu ne les as pas encaissées.',
        ),
      ),
      (
        l10n.t('Enregistre un mouvement'),
        l10n.t(
          'Utilise Dépense ou Revenu. La double flèche sert à déplacer de l’argent entre tes portefeuilles.',
        ),
      ),
    ],
  ),
  (
    title: l10n.t('Suivre tes portefeuilles'),
    steps: [
      (
        l10n.t('Ajoute un portefeuille'),
        l10n.t(
          'Choisis le type de portefeuille. Pour un compte bancaire, sélectionne ta banque, puis saisis le solde actuel en FCFA.',
        ),
      ),
      (
        l10n.t('Consulte son historique'),
        l10n.t(
          'Touche une carte pour voir son solde et les opérations enregistrées.',
        ),
      ),
      (
        l10n.t('Actualise avec les reçus'),
        l10n.t(
          'Active la lecture des SMS dans Réglages pour mettre à jour tes soldes Mobile Money à partir des nouveaux reçus reconnus.',
        ),
      ),
    ],
  ),
  (
    title: l10n.t('Prévoir tes charges'),
    steps: [
      (
        l10n.t('Ajoute une échéance'),
        l10n.t(
          'Renseigne le montant, la date et la fréquence. Les charges à régler d’ici la fin du mois réduisent le reste affiché sur l’accueil.',
        ),
      ),
      (
        l10n.t('Modifie une charge'),
        l10n.t(
          'Touche sa carte pour corriger le montant, la fréquence ou la date.',
        ),
      ),
      (
        l10n.t('Marque-la comme réglée'),
        l10n.t(
          'Ouvre le menu de la charge. Une charge récurrente passe à sa prochaine échéance. Saisis le paiement dans tes transactions si aucun reçu ne l’a enregistré.',
        ),
      ),
      (
        l10n.t('Gère dettes et créances'),
        l10n.t(
          'Ajoute ce que tu dois ou ce qu’on te doit. À l’échéance, valide le paiement ou l’encaissement et choisis le portefeuille : le solde se met à jour automatiquement.',
        ),
      ),
    ],
  ),
  (
    title: l10n.t('Suivre un projet d’épargne'),
    steps: [
      (
        l10n.t('Fixe une cible'),
        l10n.t(
          'Donne un nom au projet et indique le montant à atteindre.',
        ),
      ),
      (
        l10n.t('Ajoute un versement'),
        l10n.t(
          'Ouvre la carte, choisis le portefeuille source et saisis le montant à réserver.',
        ),
      ),
      (
        l10n.t('Configure l’épargne automatique'),
        l10n.t(
          'Choisis une catégorie de revenu et le pourcentage à mettre de côté à chaque entrée, jusqu’à la cible.',
        ),
      ),
    ],
  ),
  (
    title: l10n.t('Configurer PocheNette'),
    steps: [
      (
        l10n.t('Autorise les SMS'),
        l10n.t(
          'Active la lecture et accepte la demande Android. PocheNette lit les nouveaux reçus des portefeuilles Mobile Money déjà créés.',
        ),
      ),
      (
        l10n.t('Vérifie la synchronisation'),
        l10n.t(
          'Utilise Actualiser les soldes pour rechercher des reçus reconnus. Les données sont traitées et stockées sur le téléphone.',
        ),
      ),
      (
        l10n.t('Adapte tes catégories'),
        l10n.t(
          'Ouvre Catégories pour ajouter un poste à utiliser lors de la saisie des transactions.',
        ),
      ),
    ],
  ),
];

void showPageGuide(BuildContext context, int page) {
  final l10n = context.l10n;
  final guide = pageGuides(l10n)[page];
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
                    backgroundColor: mintWash,
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
              child: Text(l10n.t('Compris')),
            ),
          ],
        ),
      ),
    ),
  );
}
