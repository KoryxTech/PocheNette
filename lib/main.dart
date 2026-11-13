import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';
import 'receipt.dart';
import 'providers.dart';
import 'page_guide.dart';

void main() => runApp(const PocheNette());

typedef RowData = Map<String, dynamic>;

class PocheNette extends StatelessWidget {
  const PocheNette({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PocheNette',
    debugShowCheckedModeBanner: false,
    theme: pocheTheme(),
    home: const Dashboard(),
  );
}

String money(int value) {
  final grouped = value.abs().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  return '${value < 0 ? '−' : ''}$grouped FCFA';
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with WidgetsBindingObserver {
  static const channel = MethodChannel('pochenette/local');
  static const providers = [
    'Orange Money',
    'MTN MoMo',
    'Wave',
    'Espèces',
    'Banque',
  ];
  static const titles = [
    'Accueil',
    'Portefeuilles',
    'Charges',
    'Épargne',
    'Réglages',
  ];

  int tab = 0;
  bool ready = false;
  bool enabled = false;
  bool syncing = false;
  bool rescan = false;
  bool saving = false;
  bool loadFailed = false;
  int since = 0;
  List<RowData> wallets = [];
  List<RowData> operations = [];
  List<RowData> charges = [];
  List<RowData> goals = [];
  List<String> seen = [];
  List<String> categories = ['Alimentation', 'Transport', 'Logement', 'Autre'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'inboxChanged') await sync();
    });
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync();
  }

  Future<void> load() async {
    try {
      final raw = await channel.invokeMethod<String>('load');
      if (!mounted) return;
      if (raw != null) restore(jsonDecode(raw) as RowData);
      setState(() => ready = true);
      await sync();
    } on PlatformException {
      if (mounted) setState(() => loadFailed = true);
    }
  }

  List<RowData> rows(dynamic source) => (source as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  RowData snapshot() => {
    'wallets': wallets,
    'operations': operations,
    'charges': charges,
    'goals': goals,
    'seen': seen,
    'enabled': enabled,
    'since': since,
    'categories': categories,
  };

  void restore(RowData data) {
    wallets = rows(data['wallets']);
    operations = rows(data['operations']);
    charges = rows(data['charges']);
    goals = rows(data['goals']);
    seen = List<String>.from(data['seen'] as List);
    categories = List<String>.from(data['categories'] as List);
    enabled = data['enabled'] as bool;
    since = data['since'] as int;
  }

  Future<void> change(VoidCallback update) async {
    if (saving || !mounted) return;
    final previous = jsonEncode(snapshot());
    setState(() {
      saving = true;
      update();
    });
    try {
      await channel.invokeMethod<void>('save', jsonEncode(snapshot()));
    } on PlatformException {
      if (mounted) {
        setState(() => restore(jsonDecode(previous) as RowData));
        message('Impossible d’enregistrer la modification.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
      if (rescan && !syncing) {
        rescan = false;
        sync();
      }
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> sync({bool manual = false}) async {
    if (!ready || !enabled || !mounted) return;
    if (syncing || saving) {
      rescan = true;
      return;
    }
    setState(() => syncing = true);
    try {
      if (await channel.invokeMethod<bool>('permission') != true) {
        if (manual) {
          message('Autorise la lecture des SMS dans les réglages Android.');
        }
        return;
      }
      final inbox = await channel.invokeListMethod<dynamic>('readInbox', since);
      if (!mounted || !enabled) return;
      if (saving) {
        rescan = true;
        return;
      }
      final imports = <(RowData, RowData, Receipt, String, String)>[];
      final known = seen.toSet();
      for (final sms in inbox ?? []) {
        final receipt = Receipt.parse(
          sms['sender'] as String,
          sms['body'] as String,
        );
        if (receipt == null) continue;
        final index = wallets.indexWhere(
          (wallet) => wallet['provider'] == receipt.provider,
        );
        if (index < 0) continue;
        final wallet = wallets[index];
        if ((sms['date'] as int) < (wallet['created'] as int)) continue;
        final id = 'sms:${sms['id']}';
        final ref = receipt.reference == null
            ? id
            : '${receipt.provider}:${receipt.reference!.toUpperCase()}';
        if (known.contains(id) || known.contains(ref)) continue;
        known.addAll([id, ref]);
        imports.add((
          wallet,
          Map<String, dynamic>.from(sms as Map),
          receipt,
          id,
          ref,
        ));
      }
      if (imports.isNotEmpty) {
        await change(() {
          for (final (wallet, sms, receipt, id, ref) in imports) {
            final at = sms['date'] as int;
            seen.addAll([id, ref]);
            if (at >= (wallet['at'] as int)) {
              wallet['at'] = at;
              wallet['balance'] = receipt.balance;
            }
            operations.add({
              'wallet': wallet['id'],
              'label': 'Reçu ${receipt.provider}',
              'delta': receipt.delta,
              'at': at,
              'sms': true,
              'balance': receipt.balance,
            });
          }
        });
      } else if (manual) {
        message('Aucun nouveau reçu reconnu.');
      }
    } on PlatformException {
      if (manual) message('La lecture des SMS a échoué.');
    } finally {
      if (mounted) setState(() => syncing = false);
      if (rescan) {
        rescan = false;
        sync();
      }
    }
  }

  Future<void> toggleSms() async {
    if (enabled && await channel.invokeMethod<bool>('permission') == true) {
      await change(() => enabled = false);
      return;
    }
    if (!mounted) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mise à jour par SMS'),
        content: const Text(
          'PocheNette demande l’accès à la boîte SMS pour reconnaître les reçus Orange Money et MTN MoMo, enregistrer les opérations reconnues et actualiser les soldes. Le traitement et les données restent sur ce téléphone. Tu peux désactiver la lecture à tout moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    try {
      if (await channel.invokeMethod<bool>('requestPermission') != true) {
        message('Accès aux SMS refusé. La saisie manuelle reste disponible.');
        return;
      }
      await change(() {
        enabled = true;
        since = since == 0 ? DateTime.now().millisecondsSinceEpoch : since;
      });
      await sync(manual: true);
    } on PlatformException {
      message('Impossible d’activer la lecture des SMS.');
    }
  }

  int balance(RowData wallet) {
    var total = wallet['balance'] as int;
    for (final op in operations) {
      if (op['wallet'] == wallet['id'] &&
          op['sms'] != true &&
          (op['at'] as int) > (wallet['at'] as int)) {
        total += op['delta'] as int;
      }
    }
    return total;
  }

  int get total => wallets.fold(0, (sum, wallet) => sum + balance(wallet));
  int get upcoming {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    return charges
        .where((charge) {
          return DateTime.parse(charge['date'] as String).isBefore(nextMonth);
        })
        .fold(0, (sum, charge) => sum + (charge['amount'] as int));
  }

  Future<void> resolveCharge(RowData charge) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(charge['name'] as String),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'paid'),
            child: const Text('Marquer comme réglée'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Supprimer la charge'),
          ),
        ],
      ),
    );
    if (action == null) return;
    await change(() {
      if (action == 'delete' || charge['frequency'] == 'Unique') {
        charges.remove(charge);
        return;
      }
      final date = DateTime.parse(charge['date'] as String);
      final target = DateTime(
        date.year,
        date.month + (charge['frequency'] == 'Annuelle' ? 12 : 1),
      );
      final lastDay = DateTime(target.year, target.month + 1, 0).day;
      final day = charge['day'] as int? ?? date.day;
      charge['day'] = day;
      charge['date'] = DateTime(
        target.year,
        target.month,
        day.clamp(1, lastDay),
      ).toIso8601String();
      charges.sort(
        (a, b) => (a['date'] as String).compareTo(b['date'] as String),
      );
    });
  }

  String id() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<List<String>?> form(
    String title,
    List<({String label, List<String>? choices, String initial, bool number})>
    fields,
  ) async {
    final values = fields.map((field) => field.initial).toList();
    final key = GlobalKey<FormState>();
    return showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: fields[i].choices != null
                        ? DropdownButtonFormField<String>(
                            initialValue: values[i],
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: fields[i].label,
                            ),
                            items: fields[i].choices!
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => values[i] = value!,
                          )
                        : TextFormField(
                            initialValue: values[i],
                            decoration: InputDecoration(
                              labelText: fields[i].label,
                            ),
                            keyboardType: fields[i].number
                                ? const TextInputType.numberWithOptions(
                                    signed: true,
                                  )
                                : TextInputType.text,
                            onChanged: (value) => values[i] = value.trim(),
                            validator: (value) {
                              if (values[i].isEmpty) return 'Champ requis';
                              if (fields[i].number &&
                                  int.tryParse(
                                        values[i].replaceAll(RegExp(r'\s'), ''),
                                      ) ==
                                      null) {
                                return 'Montant entier requis';
                              }
                              return null;
                            },
                          ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                for (var i = 0; i < fields.length; i++) {
                  if (fields[i].number) {
                    values[i] = values[i].replaceAll(RegExp(r'\s'), '');
                  }
                }
                Navigator.pop(context, values);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  ({String label, List<String>? choices, String initial, bool number}) field(
    String label, {
    List<String>? choices,
    String? initial,
    bool number = false,
  }) => (
    label: label,
    choices: choices,
    initial: initial ?? choices?.first ?? '',
    number: number,
  );

  String walletName(RowData wallet) {
    final name = (wallet['bank'] ?? wallet['provider']) as String;
    return name == 'Banque Atlantique' ? 'AFG Bank Cameroun' : name;
  }

  Future<String?> chooseBank() {
    final existing = wallets.map(walletName).toSet();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .85,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              section('Choisir une banque'),
              for (final name in bankNames)
                tile(
                  name,
                  existing.contains(name)
                      ? 'Déjà ajoutée'
                      : name == 'General Bank of Cameroon'
                      ? 'Anciennement Société Générale Cameroun'
                      : name == 'AFG Bank Cameroun'
                      ? 'Anciennement Banque Atlantique Cameroun'
                      : 'Compte bancaire',
                  leading: providerMark(name, bank: true),
                  onTap: existing.contains(name)
                      ? null
                      : () => Navigator.pop(context, name),
                ),
              tile(
                'Autre banque',
                'Saisir le nom de ta banque',
                leading: providerMark('Banque'),
                onTap: () => Navigator.pop(context, ''),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> addWallet() async {
    final available = providers
        .where(
          (name) =>
              name == 'Banque' ||
              !wallets.any((wallet) => wallet['provider'] == name),
        )
        .toList();
    final provider = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            section('Nouveau portefeuille'),
            for (final name in available)
              tile(
                name,
                switch (name) {
                  'Orange Money' || 'MTN MoMo' => 'Mobile Money · Reçus SMS',
                  'Wave' => 'Mobile Money · Saisie manuelle',
                  'Espèces' => 'Argent liquide',
                  _ => 'Choisir ta banque · Saisie manuelle',
                },
                leading: providerMark(name),
                onTap: () => Navigator.pop(context, name),
              ),
          ],
        ),
      ),
    );
    if (provider == null || !mounted) return;
    final bank = provider == 'Banque' ? await chooseBank() : null;
    if (!mounted || (provider == 'Banque' && bank == null)) return;
    final custom = bank == '';
    final values = await form(custom ? 'Autre banque' : bank ?? provider, [
      if (custom) field('Nom de la banque'),
      field('Solde initial en FCFA', initial: '0', number: true),
    ]);
    if (values == null || !mounted) return;
    final name = custom ? values.first : bank;
    final displayName = name ?? provider;
    if (wallets.any(
          (wallet) =>
              walletName(wallet).toLowerCase() == displayName.toLowerCase(),
        ) ||
        (custom &&
            providers.any(
              (value) => value.toLowerCase() == displayName.toLowerCase(),
            ))) {
      message('Ce nom est déjà utilisé. Choisis un autre nom.');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await change(
      () => wallets.add({
        'id': id(),
        'provider': provider,
        'bank': ?name,
        'balance': int.parse(values.last),
        'created': now,
        'at': now,
      }),
    );
  }

  Future<void> addTransaction({String initialType = 'Dépense'}) async {
    if (wallets.isEmpty) {
      await addWallet();
      return;
    }
    final names = wallets.map(walletName).toList();
    final values = await form('Nouvelle transaction', [
      field(
        'Type',
        initial: initialType,
        choices: ['Dépense', 'Revenu', if (wallets.length > 1) 'Transfert'],
      ),
      field('Portefeuille', choices: names),
      field('Montant en FCFA', number: true),
      field('Catégorie', choices: categories),
    ]);
    if (values == null || !mounted) return;
    final amount = int.parse(values[2]);
    if (amount <= 0) {
      message('Entre un montant supérieur à zéro.');
      return;
    }
    final from = wallets.firstWhere(
      (wallet) => walletName(wallet) == values[1],
    );
    RowData? to;
    if (values[0] == 'Transfert') {
      final destination = await form('Vers quel portefeuille ?', [
        field(
          'Destination',
          choices: names.where((name) => name != values[1]).toList(),
        ),
      ]);
      if (destination == null) return;
      to = wallets.firstWhere((wallet) => walletName(wallet) == destination[0]);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await change(() {
      operations.add({
        'wallet': from['id'],
        'label': values[0] == 'Transfert'
            ? 'Transfert vers ${walletName(to!)}'
            : values[3],
        'delta': values[0] == 'Revenu' ? amount : -amount,
        'at': now,
        'transfer': to != null,
      });
      if (to != null) {
        operations.add({
          'wallet': to['id'],
          'label': 'Transfert de ${walletName(from)}',
          'delta': amount,
          'at': now,
          'transfer': true,
        });
      }
    });
  }

  Future<void> editCharge([RowData? charge]) async {
    final now = DateTime.now();
    final currentDate = charge == null
        ? now
        : DateTime.parse(charge['date'] as String);
    final walletsNames = ['Non affecté', ...wallets.map(walletName)];
    final values = await form(
      charge == null ? 'Nouvelle charge' : 'Modifier la charge',
      [
        field('Nom', initial: charge?['name'] as String?),
        field(
          'Montant en FCFA',
          number: true,
          initial: charge?['amount']?.toString(),
        ),
        field(
          'Fréquence',
          choices: ['Unique', 'Mensuelle', 'Annuelle'],
          initial: charge?['frequency'] as String?,
        ),
        field(
          'Portefeuille',
          choices: walletsNames,
          initial: charge?['wallet'] == 'Banque Atlantique'
              ? 'AFG Bank Cameroun'
              : charge?['wallet'] as String?,
        ),
      ],
    );
    if (values == null || !mounted) return;
    final amount = int.parse(values[1]);
    if (amount <= 0) {
      message('Entre un montant supérieur à zéro.');
      return;
    }
    final date = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Choisir la prochaine échéance',
    );
    if (date == null) return;
    await change(() {
      final details = {
        'name': values[0],
        'amount': amount,
        'frequency': values[2],
        'wallet': values[3],
        'date': date.toIso8601String(),
        'day': date.day,
      };
      if (charge == null) {
        charges.add(details);
      } else {
        charge.addAll(details);
      }
      charges.sort(
        (a, b) => (a['date'] as String).compareTo(b['date'] as String),
      );
    });
  }

  Future<void> addGoal() async {
    final values = await form('Nouvel objectif', [
      field('Projet'),
      field('Cible en FCFA', number: true),
    ]);
    if (values == null) return;
    final amount = int.parse(values[1]);
    if (amount <= 0) {
      message('Entre un objectif supérieur à zéro.');
      return;
    }
    await change(
      () => goals.add({
        'name': values[0],
        'amount': amount,
        'payments': <RowData>[],
      }),
    );
  }

  Future<void> contribute(RowData goal) async {
    final values = await form('Ajouter un versement', [
      field('Montant en FCFA', number: true),
    ]);
    if (values == null) return;
    final amount = int.parse(values[0]);
    if (amount <= 0) {
      message('Entre un montant supérieur à zéro.');
      return;
    }
    await change(
      () => (goal['payments'] as List).add({
        'amount': amount,
        'at': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  String dateText(DateTime value) =>
      '${value.day}/${value.month}/${value.year}';

  Widget tile(
    String title,
    String subtitle, {
    Widget? trailing,
    Widget? leading,
    VoidCallback? onTap,
  }) => Card(
    child: ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing:
          trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
      leading: leading,
      onTap: onTap,
    ),
  );

  List<Widget> history({String? wallet, Iterable<RowData>? entries}) {
    final sorted =
        (entries ?? operations)
            .where((op) => wallet == null || op['wallet'] == wallet)
            .toList()
          ..sort((a, b) => (b['at'] as int).compareTo(a['at'] as int));
    return [
      if (sorted.isEmpty)
        tile(
          'Aucune opération',
          'Les transactions de la période apparaîtront ici.',
          leading: const IconPlate(Icons.receipt_long_outlined),
        ),
      for (final op in sorted.take(wallet == null ? 8 : sorted.length))
        tile(
          op['label'] as String,
          dateText(DateTime.fromMillisecondsSinceEpoch(op['at'] as int)),
          leading: IconPlate(
            op['sms'] == true
                ? Icons.sms_outlined
                : Icons.receipt_long_outlined,
            color: (op['delta'] as int? ?? 0) < 0 ? rose : emerald,
          ),
          trailing: Text(
            op['delta'] == null ? 'Solde actualisé' : money(op['delta'] as int),
            style: numberStyle.copyWith(
              color: (op['delta'] as int? ?? 0) < 0 ? rose : emerald,
              fontSize: 12,
            ),
          ),
        ),
    ];
  }

  static const pageIcons = [
    Icons.balance,
    Icons.account_balance_wallet_outlined,
    Icons.event_note_outlined,
    Icons.savings_outlined,
    Icons.settings_outlined,
  ];
  static const months = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];
  static const periods = ['Jour', 'Semaine', 'Mois', 'Année', 'Tous'];
  int period = 2;
  String? selectedCategory;

  Widget section(String title, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
        ?action,
      ],
    ),
  );

  List<RowData> periodOperations() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (period) {
      0 => today,
      1 => DateTime(today.year, today.month, today.day - today.weekday + 1),
      2 => DateTime(now.year, now.month),
      3 => DateTime(now.year),
      _ => null,
    };
    return operations
        .where(
          (op) =>
              from == null || (op['at'] as int) >= from.millisecondsSinceEpoch,
        )
        .toList();
  }

  List<Widget> overview() {
    final entries = periodOperations();
    final income = entries.fold<int>(0, (sum, op) {
      final delta = op['delta'] as int? ?? 0;
      return sum + (op['transfer'] != true && delta > 0 ? delta : 0);
    });
    final expenses = <String, int>{};
    for (final op in entries) {
      final delta = op['delta'] as int? ?? 0;
      if (op['transfer'] == true || delta >= 0) continue;
      final category = op['label'] as String;
      expenses.update(
        category,
        (value) => value - delta,
        ifAbsent: () => -delta,
      );
    }
    final now = DateTime.now();
    final remaining = total - upcoming;
    return [
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 5,
        children: [
          for (var i = 0; i < periods.length; i++)
            ChoiceChip(
              label: Text(periods[i]),
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              shape: const StadiumBorder(),
              labelPadding: const EdgeInsets.symmetric(horizontal: 3),
              selected: period == i,
              showCheckmark: false,
              onSelected: (_) => setState(() {
                period = i;
                selectedCategory = null;
              }),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Center(
        child: Chip(
          avatar: const Icon(Icons.calendar_today_outlined, size: 15),
          label: Text(switch (period) {
            0 => dateText(now),
            1 => 'Semaine en cours',
            2 => '${months[now.month - 1]} ${now.year}',
            3 => '${now.year}',
            _ => 'Toutes les opérations',
          }),
        ),
      ),
      const SizedBox(height: 14),
      Center(
        child: BalanceRing(
          values: expenses.values.toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  child: Text(
                    '↑ ${money(income)}',
                    style: numberStyle.copyWith(color: emerald),
                  ),
                ),
                FittedBox(
                  child: Text(
                    '↓ ${money(expenses.values.fold(0, (sum, value) => sum + value))}',
                    style: numberStyle.copyWith(color: rose),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 5),
                  child: SizedBox(width: 28, child: Divider(height: 1)),
                ),
                const Text(
                  'Solde total',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                FittedBox(
                  child: Text(
                    money(total),
                    style: numberStyle.copyWith(fontSize: 21),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (expenses.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          children: [
            for (final (index, entry) in expenses.entries.indexed)
              FilterChip(
                avatar: Icon(
                  Icons.circle,
                  size: 11,
                  color: categoryColors[index % categoryColors.length],
                ),
                label: Text(entry.key),
                selected: selectedCategory == entry.key,
                onSelected: (active) => setState(
                  () => selectedCategory = active ? entry.key : null,
                ),
              ),
          ],
        ),
      ],
      const SizedBox(height: 18),
      SummaryPanel(
        label: 'Reste après les charges du mois',
        amount: money(remaining),
        footer: '${money(upcoming)} de charges à régler',
      ),
      if (remaining < 0)
        tile(
          'Solde insuffisant',
          'Tes soldes ne couvrent pas les charges du mois.',
          leading: const IconPlate(Icons.warning_amber_rounded, color: rose),
        ),
      if (wallets.isEmpty)
        tile(
          'Ajouter un portefeuille',
          'Orange Money, MTN MoMo, espèces ou banque.',
          leading: const IconPlate(Icons.account_balance_wallet_outlined),
          onTap: addWallet,
        ),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: saving ? null : () => addTransaction(),
              icon: const Icon(Icons.remove),
              label: const Text('Dépense'),
              style: OutlinedButton.styleFrom(
                foregroundColor: rose,
                side: const BorderSide(color: rose),
                minimumSize: const Size(48, 50),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: saving
                  ? null
                  : () => addTransaction(initialType: 'Revenu'),
              icon: const Icon(Icons.add),
              label: const Text('Revenu'),
            ),
          ),
        ],
      ),
      section(selectedCategory ?? 'Dernières opérations'),
      ...history(
        entries: entries.where(
          (op) => selectedCategory == null || op['label'] == selectedCategory,
        ),
      ),
    ];
  }

  int goalSaved(RowData goal) => (goal['payments'] as List).fold<int>(
    0,
    (sum, item) => sum + (item['amount'] as int),
  );

  List<Widget> page() {
    switch (tab) {
      case 0:
        return overview();
      case 1:
        return [
          SummaryPanel(
            label: 'Solde de tes portefeuilles',
            amount: money(total),
            footer: '${wallets.length} portefeuille(s) · FCFA',
          ),
          section('Mes portefeuilles'),
          if (wallets.isEmpty)
            tile(
              'Aucun portefeuille',
              'Ajoute tes espèces, un compte bancaire ou un compte Mobile Money.',
              leading: const IconPlate(Icons.account_balance_wallet_outlined),
            ),
          for (final wallet in wallets)
            tile(
              walletName(wallet),
              money(balance(wallet)),
              leading: providerMark(
                walletName(wallet),
                bank: wallet['provider'] == 'Banque',
              ),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                builder: (context) => SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        walletName(wallet),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      SummaryPanel(
                        label: 'Solde du portefeuille',
                        amount: money(balance(wallet)),
                        footer: walletName(wallet),
                      ),
                      section('Historique'),
                      ...history(wallet: wallet['id'] as String),
                    ],
                  ),
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: saving ? null : addWallet,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un portefeuille'),
          ),
        ];
      case 2:
        final now = DateTime.now();
        return [
          SummaryPanel(
            label: 'Charges à régler ce mois-ci',
            amount: money(upcoming),
            footer: 'Reste après les charges · ${money(total - upcoming)}',
          ),
          section(
            'Prochaines échéances',
            action: Text(
              months[now.month - 1],
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
          if (charges.isEmpty)
            tile(
              'Aucune charge prévue',
              'Ajoute un abonnement ou une échéance pour l’inclure dans ton budget.',
              leading: const IconPlate(Icons.event_available_outlined),
            ),
          for (final charge in charges)
            tile(
              charge['name'] as String,
              '${money(charge['amount'] as int)} · ${dateText(DateTime.parse(charge['date'] as String))}\n${charge['frequency']} · ${charge['wallet']}',
              leading: const IconPlate(Icons.event_note_outlined),
              onTap: () => editCharge(charge),
              trailing: IconButton(
                tooltip: 'Gérer l’échéance',
                onPressed: saving ? null : () => resolveCharge(charge),
                icon: const Icon(Icons.more_vert),
              ),
            ),
          FilledButton.icon(
            onPressed: saving ? null : () => editCharge(),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter une charge'),
          ),
        ];
      case 3:
        final target = goals.fold<int>(
          0,
          (sum, goal) => sum + (goal['amount'] as int),
        );
        final saved = goals.fold<int>(0, (sum, goal) => sum + goalSaved(goal));
        return [
          SummaryPanel(
            label: 'Épargne en projet',
            amount: money(saved),
            footer: 'Objectif total · ${money(target)}',
            progress: target == 0 ? 0 : (saved / target).clamp(0.0, 1.0),
          ),
          section('Mes objectifs'),
          if (goals.isEmpty)
            tile(
              'Aucun objectif d’épargne',
              'Crée un projet et note tes versements au fil du temps.',
              leading: const IconPlate(Icons.flag_outlined),
            ),
          for (final goal in goals)
            Card(
              child: ExpansionTile(
                leading: const IconPlate(Icons.flag_outlined),
                title: Text(goal['name'] as String),

                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5, bottom: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${money(goalSaved(goal))} / ${money(goal['amount'] as int)}',
                      ),
                      const SizedBox(height: 7),
                      PocheProgress(
                        value: (goalSaved(goal) / (goal['amount'] as int))
                            .clamp(0.0, 1.0),
                      ),
                    ],
                  ),
                ),
                children: [
                  for (final payment in (goal['payments'] as List).reversed)
                    ListTile(
                      title: Text(money(payment['amount'] as int)),
                      subtitle: Text(
                        dateText(
                          DateTime.fromMillisecondsSinceEpoch(
                            payment['at'] as int,
                          ),
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: saving ? null : () => contribute(goal),
                    child: const Text('Ajouter un versement'),
                  ),
                ],
              ),
            ),
          FilledButton.icon(
            onPressed: saving ? null : addGoal,
            icon: const Icon(Icons.add),
            label: const Text('Nouvel objectif'),
          ),
        ];
      default:
        return [
          tile(
            'Données sur cet appareil',
            'Soldes, historique et réglages sont stockés localement.',
            leading: const IconPlate(Icons.lock_outline),
          ),
          section('Synchronisation Mobile Money'),
          Card(
            child: SwitchListTile(
              secondary: const IconPlate(Icons.sms_outlined),
              title: const Text('Lecture automatique des SMS'),
              subtitle: const Text(
                'Reçus Orange Money et MTN MoMo. Traitement sur ce téléphone.',
              ),
              value: enabled,
              onChanged: saving ? null : (_) => toggleSms(),
            ),
          ),
          if (enabled)
            tile(
              syncing ? 'Lecture des reçus…' : 'Actualiser les soldes',
              'Vérifier les nouveaux SMS Mobile Money.',
              leading: syncing
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const IconPlate(Icons.sync),
              onTap: syncing ? null : () => sync(manual: true),
            ),
          section('Comptes et budget'),
          tile(
            'Devise principale',
            'Franc CFA d’Afrique centrale',
            leading: const IconPlate(Icons.payments_outlined),
            trailing: const Chip(label: Text('XAF')),
          ),
          tile(
            'Catégories',
            categories.join(' · '),
            leading: const IconPlate(Icons.category_outlined),
            onTap: () async {
              final values = await form('Ajouter une catégorie', [
                field('Nom'),
              ]);
              if (values != null && !categories.contains(values[0])) {
                await change(() => categories.add(values[0]));
              }
            },
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: tab == 0
          ? Center(
              child: Image.asset(
                'assets/brand/poche-mark.png',
                width: 37,
                height: 37,
              ),
            )
          : Icon(pageIcons[tab]),
      titleSpacing: 0,
      title: Text(tab == 0 ? 'PocheNette' : titles[tab]),
      actions: [
        if (tab == 0)
          IconButton(
            tooltip: 'Transfert',
            onPressed: saving || wallets.length < 2
                ? null
                : () => addTransaction(initialType: 'Transfert'),
            icon: const Icon(Icons.swap_horiz),
          ),
        if (tab == 4 && enabled)
          IconButton(
            tooltip: 'Actualiser les soldes',
            onPressed: () => sync(manual: true),
            icon: const Icon(Icons.sync),
          ),
        IconButton(
          tooltip: 'Guide rapide',
          onPressed: () => showPageGuide(context, tab),
          icon: const Icon(Icons.help_outline),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: ready
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: AnimatedSwitcher(
                duration: motionDuration(context, 180),
                child: ListView(
                  key: PageStorageKey(tab),
                  padding: EdgeInsets.fromLTRB(16, 14, 16, tab == 1 ? 96 : 20),
                  children: page(),
                ),
              ),
            ),
          )
        : Center(
            child: loadFailed
                ? const Text('Impossible de charger les données.')
                : const CircularProgressIndicator(),
          ),
    floatingActionButton: ready && tab == 1
        ? FloatingActionButton.extended(
            onPressed: saving ? null : addTransaction,
            icon: const Icon(Icons.add),
            label: const Text('Transaction'),
          )
        : null,
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) => setState(() => tab = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          label: 'Accueil',
        ),
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          label: 'Poches',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_outlined),
          label: 'Charges',
        ),
        NavigationDestination(
          icon: Icon(Icons.savings_outlined),
          label: 'Épargne',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          label: 'Réglages',
        ),
      ],
    ),
  );
}
