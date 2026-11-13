# PocheNette

Application Android Flutter de suivi des portefeuilles en FCFA. Les données sont conservées dans le stockage privé de l’appareil.

## Essai sur Android

1. Ajouter un portefeuille Orange Money ou MTN MoMo et indiquer son solde initial.
2. Dans **Réglages**, activer **Lecture automatique des SMS** et accorder l’autorisation Android.
3. Recevoir un reçu pris en charge, puis ouvrir PocheNette. Le reçu doit contenir un solde en FCFA ou XAF.
4. Vérifier le portefeuille et son historique. Un même SMS ou une même référence opérateur est importé une seule fois.

La boîte SMS est vérifiée à l’ouverture, au retour dans l’application et lorsqu’elle change pendant que le processus observe la boîte. Si Android a arrêté le processus, les nouveaux reçus sont rattrapés à la prochaine ouverture. Les SMS antérieurs à l’activation ou à la création du portefeuille sont ignorés. Le texte brut des reçus n’est pas enregistré dans PocheNette. Un portefeuille est pris en charge par prestataire.

Les formats de lecture sont vérifiés avec les reçus des maquettes. Il faut encore les confronter aux reçus et identifiants d’expéditeur réellement utilisés par Orange et MTN. La publication Google Play avec la permission SMS demande une déclaration et une approbation.

## Développement

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Si Flutter échoue à générer son lanceur de test à cause de l’apostrophe dans le chemin du dossier parent, lancer les tests depuis une copie dans un chemin sans apostrophe.

## Sources des logos

- [Orange Money Cameroun](https://orangemoney.orange.cm/orange-money/resources/img/slogo_15.png)
- [MTN MoMo](https://momoapi.mtn.com/content/momo_mtnb.png)
- [Wave](https://www.wave.com/img/nav-logo.png)
- [Afriland First Bank, visuel publié par Genetec](https://www.genetec.com/industries/banking)
- [BICEC](https://www.bicec.com/images/logo.png)
- [Ecobank, logo extrait d’une publication de la banque](https://commons.wikimedia.org/wiki/File:Ecobank_Logo.svg)
- [General Bank of Cameroon, emblème présenté dans L’Économie](https://leconomie.info/article/general-bank-of-cameroon-rompt-visuellement-avec-societe-generale-et-mise-sur-lagilite)
- [UBA Cameroun](https://www.ubacameroon.com/wp-content/uploads/sites/8/2018/10/cropped-UBA-Favicon-192x192.png)
- [SCB Cameroun](https://fr.wikipedia.org/wiki/Fichier:Logo_SCB_Cameroun.png)
- [CCA Bank](https://www.cca-bank.com/assets/logos/logo1.png)
- [Commercial Bank Cameroun](https://commercialbank-cm.com/wp-content/uploads/2019/09/logo_commercialBank.png)
- [BGFIBank](https://groupebgfibank.com/wp-content/uploads/2025/05/BGFI_logo.png)
- [AFG Bank Cameroun](https://afgbank.cm/template/images/logo.png)
