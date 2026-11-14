import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'alerts.dart';
import 'calendar_page.dart';
import 'catalog.dart';
import 'design.dart';
import 'onboarding.dart';
import 'page_guide.dart';
import 'providers.dart';
import 'receipt.dart';
import 'security.dart';
import 'stats_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PocheNette());
}

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

int asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.replaceAll(' ', '')) ?? 0;
  return 0;
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

  late final AppLock lock = AppLock(channel);
  int tab = 0;
  bool ready = false;
  bool enabled = false;
  bool syncing = false;
  bool rescan = false;
  bool saving = false;
  bool loadFailed = false;
  bool onboardingDone = false;
  bool unlocked = false;
  bool suppressAutoLock = false;
  bool lockEnabled = false;
  bool biometricEnabled = false;
  bool thresholdEnabled = false;
  bool alertsEnabled = true;
  int since = 0;
  int thresholdAmount = 10000;
  List<RowData> wallets = [];
  List<RowData> operations = [];
  List<RowData> charges = [];
  List<RowData> goals = [];
  List<String> seen = [];
  List<String> categories = List<String>.from(defaultCategories());
  Map<String, String> ussdCodes = {
    'Orange Money': '#150#',
    'MTN MoMo': '*126#',
    'Wave': '*831#',
  };

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
    if (state == AppLifecycleState.paused &&
        lockEnabled &&
        !suppressAutoLock) {
      setState(() => unlocked = false);
    }
    if (state == AppLifecycleState.resumed) sync();
  }

  Future<void> load() async {
    try {
      final raw = await channel.invokeMethod<String>('load');
      if (!mounted) return;
      if (raw != null) restore(jsonDecode(raw) as RowData);
      lockEnabled = await lock.lockEnabled;
      biometricEnabled = await lock.biometricEnabled;
      final pinHash = await lock.pinHash;
      if (lockEnabled && (pinHash == null || pinHash.isEmpty)) {
        await lock.clearPin();
        lockEnabled = false;
        biometricEnabled = false;
      }
      setState(() {
        ready = true;
        unlocked = !lockEnabled;
      });
      await setupNotifications();
      await sync();
      await refreshAlerts();
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
    'onboardingDone': onboardingDone,
    'thresholdEnabled': thresholdEnabled,
    'thresholdAmount': thresholdAmount,
    'alertsEnabled': alertsEnabled,
    'ussdCodes': ussdCodes,
  };

  void restore(RowData data) {
    wallets = rows(data['wallets']);
    operations = rows(data['operations']);
    charges = rows(data['charges']);
    goals = rows(data['goals']).map(normalizeGoal).toList();
    seen = List<String>.from(data['seen'] as List? ?? const []);
    categories = List<String>.from(
      data['categories'] as List? ?? defaultCategories(),
    );
    mergeDefaultCategories(categories);
    enabled = data['enabled'] as bool? ?? false;
    since = asInt(data['since']);
    onboardingDone = data['onboardingDone'] as bool? ?? false;
    thresholdEnabled = data['thresholdEnabled'] as bool? ?? false;
    thresholdAmount = asInt(data['thresholdAmount'] ?? 10000);
    alertsEnabled = data['alertsEnabled'] as bool? ?? true;
    final codes = data['ussdCodes'];
    if (codes is Map) {
      ussdCodes = codes.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
  }

  RowData normalizeGoal(RowData goal) {
    final payments = goal['payments'];
    goal['amount'] = asInt(goal['amount']);
    goal['payments'] = payments is List
        ? payments
              .whereType<Map>()
              .map(
                (payment) => <String, dynamic>{
                  'amount': asInt(payment['amount']),
                  'at': asInt(payment['at']),
                },
              )
              .toList()
        : <RowData>[];
    return goal;
  }

  Future<void> refreshAlerts() async {
    if (!alertsEnabled || !ready) return;
    if (thresholdEnabled && total < thresholdAmount) {
      await notifyThreshold(thresholdAmount);
    }
    final today = DateTime.now();
    for (final charge in charges) {
      final date = DateTime.parse(charge['date'] as String);
      if (date.year == today.year &&
          date.month == today.month &&
          date.day == today.day) {
        await notifyChargeDue(charge['name'] as String, charge['amount'] as int);
      }
    }
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
    List<
      ({
        String label,
        List<String>? choices,
        String initial,
        bool number,
        bool optional,
      })
    >
    fields, {
    String? subtitle,
    String confirmLabel = 'Enregistrer',
  }) async {
    final values = fields.map((field) => field.initial).toList();
    final key = GlobalKey<FormState>();
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final inset = MediaQuery.viewInsetsOf(context).bottom;
        final safeBottom = MediaQuery.paddingOf(context).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: Container(
            margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + safeBottom.clamp(0, 24)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x220f172a),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Form(
              key: key,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xffc5f6e3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: emerald,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(color: muted, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 18),
                    for (var i = 0; i < fields.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: fields[i].choices != null
                            ? DropdownButtonFormField<String>(
                                initialValue:
                                    fields[i].choices!.contains(values[i])
                                    ? values[i]
                                    : fields[i].choices!.first,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: fields[i].label,
                                  filled: true,
                                  fillColor: canvas,
                                  prefixIcon: Icon(
                                    _fieldIcon(fields[i].label),
                                  ),
                                ),
                                selectedItemBuilder: (context) => fields[i]
                                    .choices!
                                    .map(
                                      (value) => Align(
                                        alignment: Alignment.centerLeft,
                                        child: _choiceLabel(
                                          fields[i].label,
                                          value,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                items: fields[i].choices!
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: _choiceLabel(
                                          fields[i].label,
                                          value,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) values[i] = value;
                                },
                              )
                            : TextFormField(
                                initialValue: values[i],
                                decoration: InputDecoration(
                                  labelText: fields[i].label,
                                  filled: true,
                                  fillColor: canvas,
                                  prefixIcon: Icon(
                                    fields[i].number
                                        ? Icons.payments_outlined
                                        : _fieldIcon(fields[i].label),
                                  ),
                                ),
                                keyboardType: fields[i].number
                                    ? const TextInputType.numberWithOptions(
                                        signed: true,
                                      )
                                    : TextInputType.text,
                                textInputAction: i == fields.length - 1
                                    ? TextInputAction.done
                                    : TextInputAction.next,
                                onChanged: (value) => values[i] = value.trim(),
                                validator: (value) {
                                  if (values[i].isEmpty) {
                                    return fields[i].optional
                                        ? null
                                        : 'Champ requis';
                                  }
                                  if (fields[i].number &&
                                      int.tryParse(
                                            values[i].replaceAll(
                                              RegExp(r'\s'),
                                              '',
                                            ),
                                          ) ==
                                          null) {
                                    return 'Montant entier requis';
                                  }
                                  return null;
                                },
                              ),
                      ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: () {
                          if (key.currentState!.validate()) {
                            for (var i = 0; i < fields.length; i++) {
                              if (fields[i].number) {
                                values[i] = values[i].replaceAll(
                                  RegExp(r'\s'),
                                  '',
                                );
                              }
                            }
                            Navigator.pop(context, values);
                          }
                        },
                        child: Text(confirmLabel),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Annuler'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  ({
    String label,
    List<String>? choices,
    String initial,
    bool number,
    bool optional,
  })
  field(
    String label, {
    List<String>? choices,
    String? initial,
    bool number = false,
    bool optional = false,
  }) => (
    label: label,
    choices: choices,
    initial: initial ?? choices?.first ?? '',
    number: number,
    optional: optional,
  );

  IconData _fieldIcon(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('catégorie') || lower.contains('categorie')) {
      return Icons.category_outlined;
    }
    if (lower.contains('charge')) return Icons.event_note_outlined;
    if (lower.contains('portefeuille') ||
        lower == 'depuis' ||
        lower == 'vers' ||
        lower.contains('destination')) {
      return Icons.account_balance_wallet_outlined;
    }
    if (lower.contains('fréquence') || lower.contains('frequence')) {
      return Icons.repeat_outlined;
    }
    if (lower == 'type') return Icons.tune_outlined;
    if (lower.contains('montant')) return Icons.payments_outlined;
    if (lower.contains('détail') || lower.contains('detail')) {
      return Icons.notes_outlined;
    }
    if (lower.contains('nom') || lower.contains('projet')) {
      return Icons.edit_outlined;
    }
    return Icons.edit_outlined;
  }

  Widget _choiceLabel(String fieldLabel, String value) {
    final lower = fieldLabel.toLowerCase();
    late final IconData icon;
    if (lower.contains('catégorie') ||
        lower.contains('categorie') ||
        lower.contains('charge')) {
      icon = categoryIcon(value);
    } else if (lower.contains('portefeuille') ||
        lower == 'depuis' ||
        lower == 'vers' ||
        lower.contains('destination')) {
      icon = Icons.account_balance_wallet_outlined;
    } else if (lower.contains('fréquence') || lower.contains('frequence')) {
      icon = switch (value) {
        'Mensuelle' => Icons.calendar_month_outlined,
        'Annuelle' => Icons.event_repeat_outlined,
        _ => Icons.event_outlined,
      };
    } else if (lower == 'type') {
      icon = value == 'Revenu'
          ? Icons.trending_up_outlined
          : value == 'Dépense'
          ? Icons.trending_down_outlined
          : Icons.swap_horiz_outlined;
    } else {
      icon = categoryIcon(value);
    }
    return Row(
      children: [
        Icon(icon, size: 18, color: emerald),
        const SizedBox(width: 10),
        Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
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
    if (initialType == 'Transfert') {
      if (wallets.length < 2) {
        message('Il faut au moins deux portefeuilles pour un transfert.');
        return;
      }
      final values = await form(
        'Nouveau transfert',
        [
          field('Depuis', choices: names),
          field(
            'Vers',
            choices: names.length > 1 ? names.sublist(1) : names,
          ),
          field('Montant en FCFA', number: true),
          field('Détails', optional: true),
        ],
        subtitle: 'Déplace de l’argent entre tes poches.',
      );
      if (values == null || !mounted) return;
      if (values[0] == values[1]) {
        message('Choisis deux portefeuilles différents.');
        return;
      }
      final amount = int.parse(values[2]);
      if (amount <= 0) {
        message('Entre un montant supérieur à zéro.');
        return;
      }
      final from = wallets.firstWhere((w) => walletName(w) == values[0]);
      final to = wallets.firstWhere((w) => walletName(w) == values[1]);
      final now = DateTime.now().millisecondsSinceEpoch;
      final note = values[3];
      await change(() {
        operations.add({
          'wallet': from['id'],
          'label': 'Transfert vers ${walletName(to)}',
          'type': 'Transfert',
          'delta': -amount,
          'at': now,
          'transfer': true,
          'note': note,
        });
        operations.add({
          'wallet': to['id'],
          'label': 'Transfert de ${walletName(from)}',
          'type': 'Transfert',
          'delta': amount,
          'at': now,
          'transfer': true,
          'note': note,
        });
      });
      return;
    }

    final isIncome = initialType == 'Revenu';
    final categoryChoices = isIncome
        ? [
            ...incomeCategories,
            ...categories.where((c) => !incomeCategories.contains(c)),
          ]
        : [
            ...expenseCategories,
            ...categories.where((c) => !expenseCategories.contains(c)),
          ];
    final values = await form(
      isIncome ? 'Nouveau revenu' : 'Nouvelle dépense',
      [
        field('Portefeuille', choices: names),
        field('Montant en FCFA', number: true),
        field('Catégorie', choices: categoryChoices),
        field('Détails', optional: true),
      ],
      subtitle: isIncome
          ? 'Salaire, tontine, business…'
          : 'Marché, transport, factures…',
      confirmLabel: isIncome ? 'Ajouter le revenu' : 'Ajouter la dépense',
    );
    if (values == null || !mounted) return;
    final amount = int.parse(values[1]);
    if (amount <= 0) {
      message('Entre un montant supérieur à zéro.');
      return;
    }
    final from = wallets.firstWhere((wallet) => walletName(wallet) == values[0]);
    final now = DateTime.now().millisecondsSinceEpoch;
    await change(() {
      if (!categories.contains(values[2])) categories.add(values[2]);
      operations.add({
        'wallet': from['id'],
        'label': values[2],
        'type': isIncome ? 'Revenu' : 'Dépense',
        'delta': isIncome ? amount : -amount,
        'at': now,
        'transfer': false,
        'note': values[3],
      });
    });
  }

  Future<void> editCharge([RowData? charge]) async {
    final now = DateTime.now();
    final currentDate = charge == null
        ? now
        : DateTime.parse(charge['date'] as String);
    final walletsNames = ['Non affecté', ...wallets.map(walletName)];
    final nameChoices = [
      ...chargeTemplates,
      if (charge != null &&
          charge['name'] is String &&
          !chargeTemplates.contains(charge['name']))
        charge['name'] as String,
    ];
    final values = await form(
      charge == null ? 'Nouvelle charge' : 'Modifier la charge',
      [
        field(
          'Type de charge',
          choices: nameChoices,
          initial: charge?['name'] as String? ?? chargeTemplates.first,
        ),
        field(
          'Montant en FCFA',
          number: true,
          initial: charge?['amount']?.toString(),
        ),
        field(
          'Fréquence',
          choices: ['Unique', 'Mensuelle', 'Annuelle'],
          initial: charge?['frequency'] as String? ?? 'Mensuelle',
        ),
        field(
          'Portefeuille',
          choices: walletsNames,
          initial: charge?['wallet'] == 'Banque Atlantique'
              ? 'AFG Bank Cameroun'
              : charge?['wallet'] as String?,
        ),
        field('Détails', optional: true, initial: charge?['note'] as String?),
      ],
      subtitle: 'Loyer, ENEO, Camwater, tontine…',
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
        'name': values[0] == 'Autre charge' && values[4].isNotEmpty
            ? values[4]
            : values[0],
        'amount': amount,
        'frequency': values[2],
        'wallet': values[3],
        'date': date.toIso8601String(),
        'day': date.day,
        'note': values[4],
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

  Future<void> deleteWallet(RowData wallet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer ${walletName(wallet)} ?'),
        content: const Text(
          'Le portefeuille et ses opérations liées seront retirés de PocheNette.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await change(() {
      final id = wallet['id'];
      wallets.remove(wallet);
      operations.removeWhere((op) => op['wallet'] == id);
    });
    message('Portefeuille supprimé.');
  }

  Future<void> deleteGoal(RowData goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer ${goal['name']} ?'),
        content: const Text(
          'L’objectif et ses versements enregistrés seront retirés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await change(() => goals.remove(goal));
    message('Objectif supprimé.');
  }

  Future<void> toggleAppLock(bool value) async {
    if (value) {
      final pin = await setupPinFlow(context);
      if (pin == null || !mounted) return;
      final saved = await lock.setPin(pin);
      final enabled = saved && await lock.setLockEnabled(true);
      if (!enabled) {
        message('Impossible d’enregistrer le code.');
        return;
      }
      setState(() {
        lockEnabled = true;
        unlocked = true;
      });
      message('Verrouillage activé.');
      return;
    }
    final pin = await showPinSheet(
      context,
      title: 'Désactiver le verrouillage',
      subtitle: 'Confirme ton code pour retirer la protection.',
    );
    if (pin == null) return;
    if (!await lock.verifyPin(pin)) {
      message('Code incorrect.');
      return;
    }
    await lock.clearPin();
    setState(() {
      lockEnabled = false;
      biometricEnabled = false;
      unlocked = true;
    });
    message('Verrouillage désactivé.');
  }

  Future<void> toggleBiometric(bool value) async {
    if (!lockEnabled) {
      message('Active d’abord un code PIN.');
      return;
    }
    if (value) {
      if (!await lock.canUseBiometrics()) {
        message('Aucune biométrie configurée sur cet appareil.');
        return;
      }
      setState(() => suppressAutoLock = true);
      final ok = await lock.unlockWithBiometrics();
      if (!mounted) return;
      setState(() => suppressAutoLock = false);
      if (!ok) {
        message('Biométrie non validée.');
        return;
      }
      await lock.setBiometricEnabled(true);
      setState(() {
        biometricEnabled = true;
        unlocked = true;
      });
      message('Biométrie activée.');
      return;
    }
    await lock.setBiometricEnabled(false);
    setState(() => biometricEnabled = false);
    message('Biométrie désactivée.');
  }

  Future<void> dialUssd(String provider) async {
    final code = ussdCodes[provider];
    if (code == null || code.isEmpty) {
      message('Aucun code USSD configuré.');
      return;
    }
    try {
      await channel.invokeMethod<void>('dialUssd', code);
    } on PlatformException {
      message('Impossible d’ouvrir le composeur.');
    }
  }

  Future<void> editUssd(String provider) async {
    final values = await form('Code USSD · $provider', [
      field('Code', initial: ussdCodes[provider] ?? ''),
    ]);
    if (values == null) return;
    await change(() => ussdCodes[provider] = values[0]);
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
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
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
          dateText(DateTime.fromMillisecondsSinceEpoch(asInt(op['at']))),
          leading: IconPlate(
            op['sms'] == true
                ? Icons.sms_outlined
                : op['transfer'] == true
                ? Icons.swap_horiz_outlined
                : categoryIcon(op['label'] as String?),
            color: asInt(op['delta']) < 0 ? rose : emerald,
          ),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 118),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                op['delta'] == null
                    ? 'Solde actualisé'
                    : money(asInt(op['delta'])),
                maxLines: 1,
                textAlign: TextAlign.right,
                style: numberStyle.copyWith(
                  color: asInt(op['delta']) < 0 ? rose : emerald,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          onTap: () => showOperationDetail(op),
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
      final delta = asInt(op['delta']);
      return sum + (op['transfer'] != true && delta > 0 ? delta : 0);
    });
    final expenses = <String, int>{};
    for (final op in entries) {
      final delta = asInt(op['delta']);
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
                  categoryIcon(entry.key),
                  size: 16,
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

  int goalSaved(RowData goal) {
    final payments = goal['payments'];
    if (payments is! List) return 0;
    return payments.fold<int>(0, (sum, item) {
      if (item is! Map) return sum;
      return sum + asInt(item['amount']);
    });
  }

  Future<void> showOperationDetail(RowData op) async {
    final delta = asInt(op['delta']);
    RowData? wallet;
    for (final item in wallets) {
      if (item['id'] == op['wallet']) {
        wallet = item;
        break;
      }
    }
    final type =
        op['type'] as String? ??
        (op['transfer'] == true
            ? 'Transfert'
            : delta < 0
            ? 'Dépense'
            : 'Revenu');
    final note = (op['note'] as String?)?.trim() ?? '';
    final at = DateTime.fromMillisecondsSinceEpoch(asInt(op['at']));
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + safeBottom.clamp(0, 24)),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
              color: Color(0x220f172a),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                IconPlate(
                  op['sms'] == true
                      ? Icons.sms_outlined
                      : op['transfer'] == true
                      ? Icons.swap_horiz_outlined
                      : categoryIcon(op['label'] as String?),
                  color: delta < 0 ? rose : emerald,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        op['label'] as String? ?? 'Opération',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            type == 'Revenu'
                                ? Icons.trending_up_outlined
                                : type == 'Transfert'
                                ? Icons.swap_horiz_outlined
                                : Icons.trending_down_outlined,
                            size: 16,
                            color: muted,
                          ),
                          const SizedBox(width: 6),
                          Text(type, style: const TextStyle(color: muted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              op['delta'] == null ? 'Solde actualisé' : money(delta),
              style: numberStyle.copyWith(
                fontSize: 28,
                color: delta < 0 ? rose : emerald,
              ),
            ),
            const SizedBox(height: 16),
            _detailRow(
              'Portefeuille',
              wallet == null ? 'Inconnu' : walletName(wallet),
            ),
            _detailRow('Date', '${dateText(at)} · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'),
            if (op['sms'] == true) _detailRow('Source', 'Reçu SMS Mobile Money'),
            if (note.isNotEmpty) _detailRow('Détails', note),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(color: muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
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
                isScrollControlled: true,
                useSafeArea: true,
                builder: (context) => SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      Text(
                        walletName(wallet),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      SummaryPanel(
                        label: 'Solde du portefeuille',
                        amount: money(balance(wallet)),
                        footer: walletName(wallet),
                      ),
                      if (ussdCodes.containsKey(wallet['provider']))
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              dialUssd(wallet['provider'] as String),
                          icon: const Icon(Icons.dialpad),
                          label: Text(
                            'USSD ${ussdCodes[wallet['provider']]}',
                          ),
                        ),
                      section('Historique'),
                      ...history(wallet: wallet['id'] as String),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                Navigator.pop(context);
                                await deleteWallet(wallet);
                              },
                        icon: const Icon(Icons.delete_outline, color: rose),
                        label: const Text(
                          'Supprimer ce portefeuille',
                          style: TextStyle(color: rose),
                        ),
                      ),
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
            action: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChargesCalendarPage(
                    charges: charges,
                    money: money,
                  ),
                ),
              ),
              child: Text(
                'Calendrier · ${months[now.month - 1]}',
                style: const TextStyle(fontSize: 12),
              ),
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
              leading: IconPlate(categoryIcon(charge['name'] as String?)),
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
          (sum, goal) => sum + asInt(goal['amount']),
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
              leading: const IconPlate(Icons.savings_outlined),
            ),
          for (final goal in goals)
            Card(
              child: ExpansionTile(
                leading: const IconPlate(Icons.flag_outlined),
                title: Text(
                  goal['name'] as String? ?? 'Objectif',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5, bottom: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${money(goalSaved(goal))} / ${money(asInt(goal['amount']))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: numberStyle.copyWith(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 7),
                      PocheProgress(
                        value: asInt(goal['amount']) <= 0
                            ? 0
                            : (goalSaved(goal) / asInt(goal['amount']))
                                  .clamp(0.0, 1.0),
                      ),
                    ],
                  ),
                ),
                children: [
                  for (final payment
                      in ((goal['payments'] as List?) ?? const []).reversed)
                    ListTile(
                      title: Text(
                        money(asInt((payment as Map)['amount'])),
                      ),
                      subtitle: Text(
                        dateText(
                          DateTime.fromMillisecondsSinceEpoch(
                            asInt(payment['at']),
                          ),
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: saving ? null : () => contribute(goal),
                    child: const Text('Ajouter un versement'),
                  ),
                  TextButton(
                    onPressed: saving ? null : () => deleteGoal(goal),
                    child: const Text(
                      'Supprimer l’objectif',
                      style: TextStyle(color: rose),
                    ),
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
          section('Sécurité'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const IconPlate(Icons.shield_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Protection de l’app',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lockEnabled
                                  ? 'Code PIN actif${biometricEnabled ? ' · biométrie on' : ''}'
                                  : 'Aucun verrouillage pour l’instant',
                              style: const TextStyle(color: muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: lockEnabled
                              ? const Color(0xffc5f6e3)
                              : const Color(0xfff1f5f9),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          lockEnabled ? 'Actif' : 'Off',
                          style: TextStyle(
                            color: lockEnabled ? emerald : muted,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.tonal(
                      onPressed: saving
                          ? null
                          : () => toggleAppLock(!lockEnabled),
                      child: Text(
                        lockEnabled
                            ? 'Désactiver le verrouillage'
                            : 'Définir un code PIN',
                      ),
                    ),
                  ),
                  if (lockEnabled) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.fingerprint, color: emerald),
                      title: const Text('Biométrie'),
                      subtitle: const Text('Empreinte ou visage'),
                      value: biometricEnabled,
                      onChanged: saving ? null : toggleBiometric,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.password_outlined, color: emerald),
                      title: const Text('Changer le code PIN'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: saving
                          ? null
                          : () async {
                              final current = await showPinSheet(
                                context,
                                title: 'Code actuel',
                                subtitle: 'Entre ton code pour continuer.',
                              );
                              if (current == null) return;
                              if (!await lock.verifyPin(current)) {
                                message('Code incorrect.');
                                return;
                              }
                              if (!mounted) return;
                              final next = await setupPinFlow(context);
                              if (next == null) return;
                              if (!await lock.setPin(next)) {
                                message(
                                  'Impossible d’enregistrer le nouveau code.',
                                );
                                return;
                              }
                              message('Code mis à jour.');
                            },
                    ),
                  ],
                ],
              ),
            ),
          ),
          section('Alertes'),
          Card(
            child: SwitchListTile(
              secondary: const IconPlate(Icons.notifications_outlined),
              title: const Text('Notifications locales'),
              subtitle: const Text(
                'Rappels d’échéances et alertes de seuil.',
              ),
              value: alertsEnabled,
              onChanged: saving
                  ? null
                  : (value) async {
                      if (value) {
                        await setupNotifications(requestPermission: true);
                      }
                      await change(() => alertsEnabled = value);
                    },
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const IconPlate(Icons.warning_amber_rounded),
              title: const Text('Seuil de solde'),
              subtitle: Text(
                thresholdEnabled
                    ? 'Alerte sous ${money(thresholdAmount)}'
                    : 'Désactivé',
              ),
              value: thresholdEnabled,
              onChanged: saving
                  ? null
                  : (value) async {
                      if (value) {
                        await setupNotifications(requestPermission: true);
                        final values = await form('Seuil d’alerte', [
                          field(
                            'Montant en FCFA',
                            number: true,
                            initial: thresholdAmount.toString(),
                          ),
                        ]);
                        if (values == null) return;
                        await change(() {
                          thresholdEnabled = true;
                          thresholdAmount = int.parse(values[0]);
                        });
                        await refreshAlerts();
                        return;
                      }
                      await change(() => thresholdEnabled = false);
                    },
            ),
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
          section('Codes USSD'),
          for (final provider in ['Orange Money', 'MTN MoMo'])
            tile(
              provider,
              ussdCodes[provider] ?? 'Non défini',
              leading: providerMark(provider),
              trailing: IconButton(
                tooltip: 'Composer',
                onPressed: () => dialUssd(provider),
                icon: const Icon(Icons.dialpad),
              ),
              onTap: () => editUssd(provider),
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
            '${expenseCategories.length} dépenses · ${incomeCategories.length} revenus',
            leading: const IconPlate(Icons.category_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final values = await form(
                'Ajouter une catégorie',
                [
                  field(
                    'Type',
                    choices: ['Dépense', 'Revenu'],
                  ),
                  field('Nom'),
                ],
                subtitle: 'Ex. tontine, maquis, salaire…',
              );
              if (values != null && !categories.contains(values[1])) {
                await change(() => categories.add(values[1]));
                message('Catégorie « ${values[1]} » ajoutée.');
              }
            },
          ),
          tile(
            'Calendrier des échéances',
            'Voir le mois en cours',
            leading: const IconPlate(Icons.calendar_month_outlined),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    ChargesCalendarPage(charges: charges, money: money),
              ),
            ),
          ),
          tile(
            'Statistiques avancées',
            'Répartition du mois',
            leading: const IconPlate(Icons.insights_outlined),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => StatsPage(
                  operations: operations,
                  money: money,
                  categories: categories,
                ),
              ),
            ),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return Scaffold(
        body: Center(
          child: loadFailed
              ? const Text('Impossible de charger les données.')
              : const CircularProgressIndicator(),
        ),
      );
    }
    if (!onboardingDone) {
      return OnboardingScreen(
        onDone: () {
          setState(() => onboardingDone = true);
          change(() {});
        },
      );
    }
    if (lockEnabled && !unlocked) {
      return LockScreen(
        lock: lock,
        onUnlocked: () => setState(() => unlocked = true),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: tab == 0
            ? Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Center(
                  child: Image.asset(
                    'assets/brand/poche-mark.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              )
            : Icon(pageIcons[tab]),
        titleSpacing: 4,
        title: Text(
          tab == 0 ? 'PocheNette' : titles[tab],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: AnimatedSwitcher(
            duration: motionDuration(context, 180),
            child: ListView(
              key: PageStorageKey(tab),
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                24 + (tab == 1 ? 72 : 8),
              ),
              children: page(),
            ),
          ),
        ),
      ),
      floatingActionButton: tab == 1
          ? FloatingActionButton.extended(
              onPressed: saving ? null : addTransaction,
              icon: const Icon(Icons.add),
              label: const Text('Transaction'),
            )
          : null,
      bottomNavigationBar: Material(
        color: Colors.white,
        elevation: 0,
        child: Padding(
          // Remonte les onglets hors de la barre de gestes Xiaomi / Android.
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 10,
          ),
          child: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (value) => setState(() => tab = value),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Accueil',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Poches',
              ),
              NavigationDestination(
                icon: Icon(Icons.event_outlined),
                selectedIcon: Icon(Icons.event),
                label: 'Charges',
              ),
              NavigationDestination(
                icon: Icon(Icons.savings_outlined),
                selectedIcon: Icon(Icons.savings),
                label: 'Épargne',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Réglages',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
