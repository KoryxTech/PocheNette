import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'alerts.dart';
import 'calendar_page.dart';
import 'catalog.dart';
import 'design.dart';
import 'l10n/l10n.dart';
import 'onboarding.dart';
import 'page_guide.dart';
import 'providers.dart';
import 'receipt.dart';
import 'security.dart';
import 'stats_page.dart';
import 'features/about/presentation/about_page.dart';
import 'features/debts/domain/debt_constants.dart';
import 'features/demo/demo_seed.dart';
import 'features/splash/presentation/splash_view.dart';
import 'core/config/brand_constants.dart';
import 'package:url_launcher/url_launcher.dart';
import 'features/transfer/domain/transfer_bundle.dart';
import 'features/transfer/presentation/transfer_export_page.dart';
import 'features/transfer/presentation/transfer_import_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PocheNette());
}

typedef RowData = Map<String, dynamic>;

class PocheNette extends StatefulWidget {
  const PocheNette({super.key});

  static PocheNetteState? of(BuildContext context) =>
      context.findAncestorStateOfType<PocheNetteState>();

  @override
  State<PocheNette> createState() => PocheNetteState();
}

class PocheNetteState extends State<PocheNette> {
  Locale? _locale;

  Locale? get locale => _locale;

  void setLocale(Locale? locale) {
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PocheNette',
    debugShowCheckedModeBanner: false,
    theme: pocheTheme(),
    locale: _locale,
    supportedLocales: L10n.supported,
    localeResolutionCallback: (device, supported) {
      if (_locale != null) return _locale;
      if (device == null) return const Locale('fr');
      for (final locale in supported) {
        if (locale.languageCode == device.languageCode) return locale;
      }
      return const Locale('fr');
    },
    localizationsDelegates: const [
      L10nDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
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

  late final AppLock lock = AppLock(channel);
  int tab = 0;
  bool ready = false;
  bool showSplash = true;
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
  String? localeCode;
  int since = 0;
  int thresholdAmount = 10000;
  List<RowData> wallets = [];
  List<RowData> operations = [];
  List<RowData> charges = [];
  List<RowData> debts = [];
  List<RowData> goals = [];
  List<String> seen = [];
  List<String> categories = List<String>.from(defaultCategories());
  List<String> extraExpenseCategories = [];
  List<String> extraIncomeCategories = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'inboxChanged') await sync();
    });
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    await load();
    final elapsed = DateTime.now().difference(started);
    final remaining = BrandConstants.splashMinDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (mounted) setState(() => showSplash = false);
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
      if (!mounted) return;
      if (localeCode != null) {
        PocheNette.of(context)?.setLocale(Locale(localeCode!));
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

  Future<void> loadDemoData({bool confirm = true}) async {
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Charger le jeu de démo')),
          content: Text(
            tr(
              'Cela remplace portefeuilles, opérations, charges, dettes et épargne par un exemple complet.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Annuler')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Charger')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await change(() => restore(buildDemoSeed()));
    message(tr('Jeu de démo chargé.'));
  }

  List<RowData> rows(dynamic source) => (source as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  RowData snapshot() => {
    'wallets': wallets,
    'operations': operations,
    'charges': charges,
    'debts': debts,
    'goals': goals,
    'seen': seen,
    'enabled': enabled,
    'since': since,
    'categories': categories,
    'extraExpenseCategories': extraExpenseCategories,
    'extraIncomeCategories': extraIncomeCategories,
    'onboardingDone': onboardingDone,
    'thresholdEnabled': thresholdEnabled,
    'thresholdAmount': thresholdAmount,
    'alertsEnabled': alertsEnabled,
    'localeCode': localeCode,
  };

  void restore(RowData data) {
    wallets = rows(data['wallets']);
    operations = rows(data['operations']);
    charges = rows(data['charges']);
    debts = rows(data['debts'] ?? const []);
    sortDebtsByDueDate(debts);
    goals = rows(data['goals']).map(normalizeGoal).toList();
    seen = List<String>.from(data['seen'] as List? ?? const []);
    categories = List<String>.from(
      data['categories'] as List? ?? defaultCategories(),
    );
    mergeDefaultCategories(categories);
    extraExpenseCategories = List<String>.from(
      data['extraExpenseCategories'] as List? ?? const [],
    );
    extraIncomeCategories = List<String>.from(
      data['extraIncomeCategories'] as List? ?? const [],
    );
    enabled = data['enabled'] as bool? ?? false;
    since = asInt(data['since']);
    onboardingDone = data['onboardingDone'] as bool? ?? false;
    thresholdEnabled = data['thresholdEnabled'] as bool? ?? false;
    thresholdAmount = asInt(data['thresholdAmount'] ?? 10000);
    alertsEnabled = data['alertsEnabled'] as bool? ?? true;
    localeCode = data['localeCode'] as String?;
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
                  if (payment['wallet'] is String) 'wallet': payment['wallet'],
                  if (payment['walletName'] is String)
                    'walletName': payment['walletName'],
                  if (payment['automatic'] == true) 'automatic': true,
                },
              )
              .toList()
        : <RowData>[];
    return goal;
  }

  Future<TransferBundle> buildTransferBundle() async {
    return TransferBundle(
      version: 1,
      exportedAtMs: DateTime.now().millisecondsSinceEpoch,
      state: Map<String, dynamic>.from(snapshot()),
      secure: {
        'pinHash': await lock.pinHash,
        'lockEnabled': (await lock.lockEnabled) ? '1' : '0',
        // Biométrie à réactiver sur le nouvel appareil.
        'biometricEnabled': '0',
      },
    );
  }

  Future<void> applyTransferBundle(TransferBundle bundle) async {
    restore(bundle.state);
    onboardingDone = true;
    final pinHash = bundle.secure['pinHash'];
    final lockOn = bundle.secure['lockEnabled'] == '1' &&
        pinHash != null &&
        pinHash.isNotEmpty;
    if (lockOn) {
      await lock.write('pinHash', pinHash);
      await lock.setLockEnabled(true);
    } else {
      await lock.clearPin();
    }
    await lock.setBiometricEnabled(false);
    await channel.invokeMethod<void>('save', jsonEncode(snapshot()));
    if (!mounted) return;
    setState(() {
      lockEnabled = lockOn;
      biometricEnabled = false;
      unlocked = !lockOn;
      ready = true;
    });
    if (localeCode != null) {
      PocheNette.of(context)?.setLocale(Locale(localeCode!));
    }
    await refreshAlerts();
  }

  Future<void> openTransferExport() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => TransferExportPage(buildBundle: buildTransferBundle),
      ),
    );
    if (ok == true && mounted) {
      message('Transfert envoyé.');
    }
  }

  Future<void> openTransferImport() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => TransferImportPage(onReceived: applyTransferBundle),
      ),
    );
    if (ok == true && mounted) {
      message('Données importées. Bienvenue sur ton nouveau téléphone.');
    }
  }

  Future<void> refreshAlerts() async {
    if (!alertsEnabled || !ready) return;
    if (thresholdEnabled && total < thresholdAmount) {
      await notifyThreshold(thresholdAmount, l10n: l10n);
    }
    final today = DateTime.now();
    for (final charge in charges) {
      final date = DateTime.parse(charge['date'] as String);
      if (date.year == today.year &&
          date.month == today.month &&
          date.day == today.day) {
        await notifyChargeDue(
          charge['name'] as String,
          charge['amount'] as int,
          l10n: l10n,
        );
      }
    }
    for (final debt in debts) {
      if (!isOpenDebt(debt) || debt['reminder'] == false) continue;
      final date = DateTime.parse(debt['date'] as String);
      if (date.year == today.year &&
          date.month == today.month &&
          date.day == today.day) {
        await notifyDebtDue(
          person: debt['person'] as String? ?? '',
          amount: debtAmount(debt),
          isReceivable: isCreance(debt),
          l10n: l10n,
        );
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

  L10n get l10n => L10n.of(context);
  String tr(String source) => l10n.t(source);
  bool get isIos => defaultTargetPlatform == TargetPlatform.iOS;

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(text))),
      );
    }
  }

  Future<void> setAppLocale(String? code) async {
    localeCode = code;
    PocheNette.of(context)?.setLocale(code == null ? null : Locale(code));
    await change(() {});
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
          message(
            isIos
                ? 'La lecture SMS n’est pas disponible sur iOS. Utilise la saisie manuelle.'
                : 'Autorise la lecture des SMS dans les réglages Android.',
          );
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
        title: Text(tr('Mise à jour par SMS')),
        content: Text(
          tr('PocheNette demande l’accès à la boîte SMS pour reconnaître les reçus Orange Money et MTN MoMo, enregistrer les opérations reconnues et actualiser les soldes. Le traitement et les données restent sur ce téléphone. Tu peux désactiver la lecture à tout moment.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Continuer')),
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
    for (final goal in goals) {
      for (final payment in goal['payments'] as List) {
        if (payment['wallet'] == wallet['id']) {
          total -= asInt(payment['amount']);
        }
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

  int get openDebtsAmount => openDebtsTotal(debts);
  int get openReceivablesAmount => openReceivablesTotal(debts);

  /// Liquidités moins charges du mois et dettes encore dues.
  int get realAvailable => availableBalance(
    walletTotal: total,
    upcomingCharges: upcoming,
    debts: debts,
  );

  Future<void> resolveCharge(RowData charge) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(charge['name'] as String),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'paid'),
            child: Text(tr('Marquer comme réglée')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: Text(tr('Supprimer la charge')),
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
        final sheetL10n = L10n.of(context);
        String sheetTr(String source) => sheetL10n.t(source);
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
                        color: mintWash,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: emerald,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      sheetTr(title),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        sheetTr(subtitle),
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
                                  labelText: sheetTr(fields[i].label),
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
                                          translate: sheetTr,
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
                                          translate: sheetTr,
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
                                  labelText: sheetTr(fields[i].label),
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
                                        : sheetTr('Champ requis');
                                  }
                                  if (fields[i].number &&
                                      int.tryParse(
                                            values[i].replaceAll(
                                              RegExp(r'\s'),
                                              '',
                                            ),
                                          ) ==
                                          null) {
                                    return sheetTr('Montant entier requis');
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
                        child: Text(sheetTr(confirmLabel)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(sheetTr('Annuler')),
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
    if (lower.contains('catégorie') ||
        lower.contains('categorie') ||
        lower.contains('category')) {
      return Icons.category_outlined;
    }
    if (lower.contains('charge') || lower.contains('bill')) {
      return Icons.event_note_outlined;
    }
    if (lower.contains('personne') ||
        lower.contains('person') ||
        lower.contains('rappel') ||
        lower.contains('remind')) {
      return Icons.person_outline;
    }
    if (lower.contains('portefeuille') ||
        lower.contains('wallet') ||
        lower == 'depuis' ||
        lower == 'from' ||
        lower == 'vers' ||
        lower == 'to' ||
        lower.contains('destination')) {
      return Icons.account_balance_wallet_outlined;
    }
    if (lower.contains('fréquence') ||
        lower.contains('frequence') ||
        lower.contains('frequency')) {
      return Icons.repeat_outlined;
    }
    if (lower == 'type') return Icons.tune_outlined;
    if (lower.contains('montant') || lower.contains('amount')) {
      return Icons.payments_outlined;
    }
    if (lower.contains('détail') ||
        lower.contains('detail') ||
        lower.contains('details')) {
      return Icons.notes_outlined;
    }
    if (lower.contains('nom') ||
        lower.contains('name') ||
        lower.contains('projet') ||
        lower.contains('project')) {
      return Icons.edit_outlined;
    }
    return Icons.edit_outlined;
  }

  Widget _choiceLabel(
    String fieldLabel,
    String value, {
    String Function(String)? translate,
  }) {
    final lower = fieldLabel.toLowerCase();
    final labelOf = translate ?? tr;
    late final IconData icon;
    if (lower.contains('catégorie') ||
        lower.contains('categorie') ||
        lower.contains('category') ||
        lower.contains('charge') ||
        lower.contains('bill')) {
      icon = categoryIcon(value);
    } else if (lower.contains('portefeuille') ||
        lower.contains('wallet') ||
        lower == 'depuis' ||
        lower == 'from' ||
        lower == 'vers' ||
        lower == 'to' ||
        lower.contains('destination')) {
      icon = Icons.account_balance_wallet_outlined;
    } else if (lower.contains('fréquence') ||
        lower.contains('frequence') ||
        lower.contains('frequency')) {
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
        Expanded(child: Text(labelOf(value), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  String walletName(RowData wallet) {
    final name = (wallet['bank'] ?? wallet['provider']) as String;
    return name == 'Banque Atlantique' ? 'AFG Bank Cameroun' : name;
  }

  bool isCashWallet(RowData wallet) {
    final name = walletName(wallet).toLowerCase();
    final provider = (wallet['provider'] as String? ?? '').toLowerCase();
    bool cash(String value) =>
        value == 'espèces' ||
        value == 'especes' ||
        value == 'cash' ||
        value.contains('espèce') ||
        value.contains('espece');
    return cash(name) || cash(provider);
  }

  bool _nameLooksCash(String value) {
    final lower = value.toLowerCase();
    return lower.contains('espèce') ||
        lower.contains('espece') ||
        lower == 'cash';
  }

  /// OM / MoMo / banque → espèces = retrait ; l’inverse = dépôt.
  ({String fromLabel, String toLabel, String type}) transferLabels({
    required RowData from,
    required RowData to,
  }) {
    final fromName = walletName(from);
    final toName = walletName(to);
    final fromCash = isCashWallet(from);
    final toCash = isCashWallet(to);
    if (!fromCash && toCash) {
      return (
        fromLabel: 'Retrait vers $toName',
        toLabel: 'Retrait de $fromName',
        type: 'Retrait',
      );
    }
    if (fromCash && !toCash) {
      return (
        fromLabel: 'Dépôt vers $toName',
        toLabel: 'Dépôt de $fromName',
        type: 'Dépôt',
      );
    }
    return (
      fromLabel: 'Transfert vers $toName',
      toLabel: 'Transfert de $fromName',
      type: 'Transfert',
    );
  }

  String displayOperationLabel(RowData op) {
    final label = op['label'] as String? ?? '';
    if (op['transfer'] != true) return label;
    if (label.startsWith('Retrait') || label.startsWith('Dépôt')) {
      return label;
    }
    RowData? wallet;
    for (final item in wallets) {
      if (item['id'] == op['wallet']) {
        wallet = item;
        break;
      }
    }
    final thisIsCash = wallet != null && isCashWallet(wallet);
    if (label.startsWith('Transfert vers ')) {
      final dest = label.substring('Transfert vers '.length);
      if (_nameLooksCash(dest)) return 'Retrait vers $dest';
      if (thisIsCash) return 'Dépôt vers $dest';
      return label;
    }
    if (label.startsWith('Transfert de ')) {
      final source = label.substring('Transfert de '.length);
      if (_nameLooksCash(source)) return 'Dépôt de $source';
      if (thisIsCash) return 'Retrait de $source';
      return label;
    }
    return label;
  }

  String operationKind(RowData op) {
    final stored = op['type'] as String?;
    if (stored == 'Retrait' || stored == 'Dépôt' || stored == 'Transfert') {
      return stored!;
    }
    if (op['transfer'] == true) {
      final label = displayOperationLabel(op);
      if (label.startsWith('Retrait')) return 'Retrait';
      if (label.startsWith('Dépôt')) return 'Dépôt';
      return 'Transfert';
    }
    final delta = asInt(op['delta']);
    return delta < 0 ? 'Dépense' : 'Revenu';
  }

  IconData operationIcon(RowData op) {
    if (op['sms'] == true) return Icons.sms_outlined;
    final kind = operationKind(op);
    return switch (kind) {
      'Retrait' => Icons.outbox_outlined,
      'Dépôt' => Icons.move_to_inbox_outlined,
      'Transfert' => Icons.swap_horiz_outlined,
      _ => categoryIcon(op['label'] as String?),
    };
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
      final labels = transferLabels(from: from, to: to);
      await change(() {
        operations.add({
          'wallet': from['id'],
          'label': labels.fromLabel,
          'type': labels.type,
          'delta': -amount,
          'at': now,
          'transfer': true,
          'note': note,
        });
        operations.add({
          'wallet': to['id'],
          'label': labels.toLabel,
          'type': labels.type,
          'delta': amount,
          'at': now,
          'transfer': true,
          'note': note,
        });
      });
      return;
    }

    final isIncome = initialType == 'Revenu';
    final categoryChoices = categoriesForTransaction(
      isIncome: isIncome,
      stored: categories,
      extraExpenses: extraExpenseCategories,
      extraIncomes: extraIncomeCategories,
    );
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
    final index = wallets.indexWhere(
      (wallet) => walletName(wallet) == values[0],
    );
    if (index < 0) return;
    final from = wallets[index];
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
      if (isIncome) allocateIncome(from, values[2], amount, now);
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

  Future<void> editDebt([RowData? debt]) async {
    final now = DateTime.now();
    final currentDate = debt == null
        ? now
        : DateTime.parse(debt['date'] as String);
    final kindInitial = debt == null
        ? 'Dette (je dois)'
        : (isCreance(debt) ? 'Créance (on me doit)' : 'Dette (je dois)');
    final values = await form(
      debt == null ? 'Nouvelle dette / créance' : 'Modifier l’obligation',
      [
        field(
          'Type',
          choices: const ['Dette (je dois)', 'Créance (on me doit)'],
          initial: kindInitial,
        ),
        field(
          'Personne',
          initial: debt?['person'] as String?,
        ),
        field(
          'Montant en FCFA',
          number: true,
          initial: debt?['amount']?.toString(),
        ),
        field(
          'Rappel à l’échéance',
          choices: const ['Oui', 'Non'],
          initial: debt == null || debt['reminder'] != false ? 'Oui' : 'Non',
        ),
        field(
          'Détails',
          optional: true,
          initial: debt?['note'] as String?,
        ),
      ],
      subtitle: 'Qui te doit, ou à qui tu dois — avec date d’échéance.',
    );
    if (values == null || !mounted) return;
    final person = values[1].trim();
    if (person.isEmpty) {
      message('Indique le nom de la personne.');
      return;
    }
    final amount = int.parse(values[2]);
    if (amount <= 0) {
      message('Entre un montant supérieur à zéro.');
      return;
    }
    final date = await showDatePicker(
      context: context,
      initialDate: currentDate.isBefore(DateTime(2000))
          ? now
          : currentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Choisir la date d’échéance',
    );
    if (date == null) return;
    final kind = values[0].startsWith('Créance')
        ? debtKindCreance
        : debtKindDette;
    await change(() {
      final details = <String, dynamic>{
        'id': debt?['id'] as String? ?? id(),
        'kind': kind,
        'person': person,
        'amount': amount,
        'date': date.toIso8601String(),
        'reminder': values[3] == 'Oui',
        'note': values[4],
        'status': debt?['status'] as String? ?? debtStatusOpen,
      };
      if (debt == null) {
        debts.add(details);
      } else {
        debt
          ..remove('settledAt')
          ..remove('settledWallet')
          ..remove('settledWalletName');
        debt.addAll(details);
      }
      sortDebtsByDueDate(debts);
    });
  }

  Future<void> settleDebt(RowData debt) async {
    if (!isOpenDebt(debt)) return;
    if (wallets.isEmpty) {
      await addWallet();
      if (!mounted || wallets.isEmpty) return;
    }
    final receivable = isCreance(debt);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          receivable
              ? tr('Encaisser la créance')
              : tr('Rembourser la dette'),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              '${debt['person']} · ${money(debtAmount(debt))}',
              style: const TextStyle(color: muted),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'settle'),
            child: Text(
              receivable
                  ? tr('Marquer comme perçu')
                  : tr('Marquer comme payé'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: Text(tr('Modifier')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: Text(tr('Supprimer')),
          ),
        ],
      ),
    );
    if (action == null) return;
    if (action == 'edit') {
      await editDebt(debt);
      return;
    }
    if (action == 'delete') {
      await change(() => debts.remove(debt));
      return;
    }

    final names = wallets.map(walletName).toList();
    final values = await form(
      receivable
          ? 'Portefeuille de réception'
          : 'Portefeuille de paiement',
      [
        field(
          'Portefeuille',
          choices: names,
        ),
      ],
      subtitle: receivable
          ? 'Les fonds seront ajoutés à ce portefeuille.'
          : 'Le montant sera débité de ce portefeuille.',
      confirmLabel: receivable ? 'Valider l’encaissement' : 'Valider le paiement',
    );
    if (values == null) return;
    final index = wallets.indexWhere(
      (wallet) => walletName(wallet) == values[0],
    );
    if (index < 0) return;
    final wallet = wallets[index];
    final amount = debtAmount(debt);
    if (!receivable && balance(wallet) < amount) {
      message('Le solde disponible de ce portefeuille est insuffisant.');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final label = receivable ? debtIncomeLabel : debtExpenseLabel;
    final extraNote = (debt['note'] as String? ?? '').trim();
    final operationNote = extraNote.isEmpty
        ? '${debt['person']}'
        : '${debt['person']} · $extraNote';
    await change(() {
      operations.add({
        'id': id(),
        'wallet': wallet['id'],
        'label': label,
        'type': receivable ? 'Revenu' : 'Dépense',
        'delta': receivable ? amount : -amount,
        'at': now,
        'transfer': false,
        'note': operationNote,
        'debtId': debt['id'],
      });
      debt['status'] = debtStatusSettled;
      debt['settledAt'] = now;
      debt['settledWallet'] = wallet['id'];
      debt['settledWalletName'] = walletName(wallet);
      sortDebtsByDueDate(debts);
      if (receivable) {
        allocateIncome(wallet, label, amount, now);
      }
    });
    message(
      receivable
          ? tr('Créance encaissée — solde actualisé.')
          : tr('Dette remboursée — solde actualisé.'),
    );
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

  int goalRemaining(RowData goal) => asInt(goal['amount']) - goalSaved(goal);

  void recordContribution(
    RowData goal,
    RowData wallet,
    int amount,
    int at, {
    bool automatic = false,
  }) {
    (goal['payments'] as List).add({
      'amount': amount,
      'at': at,
      'wallet': wallet['id'],
      'walletName': walletName(wallet),
      if (automatic) 'automatic': true,
    });
  }

  void allocateIncome(RowData wallet, String category, int income, int at) {
    var available = balance(wallet).clamp(0, income);
    for (final goal in goals) {
      if (available == 0) break;
      final percent = asInt(goal['incomePercent']);
      final remaining = goalRemaining(goal);
      if (goal['incomeCategory'] != category ||
          percent < 1 ||
          percent > 100 ||
          remaining <= 0) {
        continue;
      }
      final amount = (income * percent ~/ 100)
          .clamp(0, remaining)
          .clamp(0, available);
      if (amount == 0) continue;
      recordContribution(goal, wallet, amount, at, automatic: true);
      available -= amount;
    }
  }

  Future<void> configureAutomaticSaving(RowData goal) async {
    final categoriesForIncome = categoriesForTransaction(
      isIncome: true,
      stored: categories,
      extraExpenses: extraExpenseCategories,
      extraIncomes: extraIncomeCategories,
    );
    final category = goal['incomeCategory'] as String?;
    final percent = asInt(goal['incomePercent']);
    final values = await form(
      'Épargne automatique',
      [
        field(
          'Catégorie',
          choices: categoriesForIncome,
          initial: categoriesForIncome.contains(category) ? category : null,
        ),
        field(
          'Pourcentage du revenu',
          number: true,
          initial: percent.toString(),
        ),
      ],
      subtitle:
          'À chaque revenu de cette catégorie, la part est réservée dans le portefeuille crédité. Saisis 0 pour désactiver.',
    );
    if (values == null || !mounted || !goals.contains(goal)) return;
    final selectedPercent = int.parse(values[1]);
    if (selectedPercent < 0 || selectedPercent > 100) {
      message('Entre un pourcentage entre 0 et 100.');
      return;
    }
    await change(() {
      if (selectedPercent == 0) {
        goal.remove('incomeCategory');
        goal.remove('incomePercent');
      } else {
        goal['incomeCategory'] = values[0];
        goal['incomePercent'] = selectedPercent;
      }
    });
  }

  Future<void> contribute(RowData goal) async {
    if (goalRemaining(goal) <= 0) return;
    if (wallets.isEmpty) {
      message('Crée un portefeuille avant de verser de l’argent.');
      return;
    }
    final sources = {
      for (final wallet in wallets) walletName(wallet): wallet['id'],
    };
    final values = await form('Ajouter un versement', [
      field('Portefeuille source', choices: sources.keys.toList()),
      field('Montant en FCFA', number: true),
    ]);
    if (values == null || !mounted || !goals.contains(goal)) return;
    final amount = int.parse(values[1]);
    if (amount <= 0) {
      message('Entre un montant supérieur à zéro.');
      return;
    }
    if (amount > goalRemaining(goal)) {
      message('Le montant dépasse ce qu’il reste à épargner.');
      return;
    }
    final index = wallets.indexWhere(
      (wallet) => wallet['id'] == sources[values[0]],
    );
    if (index < 0) return;
    final wallet = wallets[index];
    if (amount > balance(wallet)) {
      message('Le solde disponible de ce portefeuille est insuffisant.');
      return;
    }
    await change(
      () => recordContribution(
        goal,
        wallet,
        amount,
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> deleteWallet(RowData wallet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer ${walletName(wallet)} ?'),
        content: Text(
          tr('Le portefeuille et ses opérations liées seront retirés de PocheNette.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Supprimer')),
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
        content: Text(
          tr(
            'Supprimer cet objectif libère les montants réservés dans les portefeuilles sources.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Supprimer')),
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
      title: tr('Désactiver le verrouillage'),
      subtitle: tr('Confirme ton code pour retirer la protection.'),
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
      final ok = await lock.unlockWithBiometrics(
        reason: tr('Déverrouille PocheNette avec ta biométrie'),
      );
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
      title: Text(tr(title), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(tr(subtitle), maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing:
          trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
      leading: leading,
      onTap: onTap,
    ),
  );

  Widget debtStatusChip(bool open, {bool overdue = false}) {
    final label = open
        ? (overdue ? tr('En retard') : tr('En attente'))
        : tr('Réglé');
    final color = open ? (overdue ? rose : const Color(0xffc27803)) : emerald;
    final background = open
        ? (overdue ? const Color(0xffffe4e8) : const Color(0xfffff3d6))
        : mintWash;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget debtCard(RowData debt) {
    final receivable = isCreance(debt);
    final open = isOpenDebt(debt);
    final due = DateTime.parse(debt['date'] as String);
    final today = DateTime.now();
    final dueDay = DateTime(due.year, due.month, due.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    final overdue = open && dueDay.isBefore(todayDay);
    final settledWallet = debt['settledWalletName'] as String?;
    final settledAt = debt['settledAt'];
    final detail = open
        ? '${money(debtAmount(debt))} · ${dateText(due)}'
        : '${money(debtAmount(debt))}'
            '${settledWallet != null ? ' · $settledWallet' : ''}'
            '${settledAt is int ? ' · ${dateText(DateTime.fromMillisecondsSinceEpoch(settledAt))}' : ''}';
    final actionColor = receivable ? emerald : rose;
    return Card(
      child: InkWell(
        onTap: open && !saving ? () => editDebt(debt) : null,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconPlate(
                receivable ? Icons.south_west : Icons.north_east,
                color: open ? actionColor : muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      debt['person'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, height: 1.3),
                    ),
                    if ((debt['note'] as String?)?.trim().isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 2),
                      Text(
                        debt['note'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  debtStatusChip(open, overdue: overdue),
                  if (open) ...[
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: saving ? null : () => settleDebt(debt),
                      style: FilledButton.styleFrom(
                        backgroundColor: actionColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        receivable ? tr('Encaisser') : tr('Payer'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          displayOperationLabel(op),
          dateText(DateTime.fromMillisecondsSinceEpoch(asInt(op['at']))),
          leading: IconPlate(
            operationIcon(op),
            color: asInt(op['delta']) < 0 ? rose : emerald,
          ),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 118),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                op['delta'] == null
                    ? tr('Solde actualisé')
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
  int period = 2;
  String? selectedCategory;

  Widget section(String title, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            tr(title),
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

  ({List<Widget> balance, List<Widget> activity}) overview({
    required bool wide,
  }) {
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
    final remaining = realAvailable;
    final receivables = openReceivablesAmount;
    final debtsDue = openDebtsAmount;
    // Légende : noms courts, 2 lignes max (~8 chips).
    const maxLegendChips = 8;
    const autresLegendKey = '__autres__';
    final sortedExpenses = expenses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final legendOverflow = sortedExpenses.length > maxLegendChips;
    final legendVisible = legendOverflow
        ? sortedExpenses.take(maxLegendChips - 1).toList()
        : sortedExpenses;
    final legendAutresKeys = legendOverflow
        ? sortedExpenses.skip(maxLegendChips - 1).map((e) => e.key).toSet()
        : <String>{};
    final balanceOverview = <Widget>[
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 5,
        children: [
          for (var i = 0; i < l10n.periods.length; i++)
            ChoiceChip(
              label: Text(l10n.periods[i]),
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
            1 => tr('Semaine en cours'),
            2 => '${l10n.month(now.month)} ${now.year}',
            3 => '${now.year}',
            _ => tr('Toutes les opérations'),
          }),
        ),
      ),
      const SizedBox(height: 14),
      Center(
        child: BalanceRing(
          values: expenses.values.toList(),
          diameter: wide ? 270 : 206,
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
                Text(
                  tr('Solde total'),
                  style: const TextStyle(fontSize: 11, color: muted),
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
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 2,
          children: [
            for (final (index, entry) in legendVisible.indexed)
              FilterChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.only(right: 6),
                avatar: Icon(
                  categoryIcon(entry.key),
                  size: 14,
                  color: categoryColors[index % categoryColors.length],
                ),
                label: Text(
                  tr(shortCategoryLabel(entry.key)),
                  style: const TextStyle(fontSize: 11),
                ),
                selected: selectedCategory == entry.key,
                onSelected: (active) => setState(
                  () => selectedCategory = active ? entry.key : null,
                ),
              ),
            if (legendOverflow)
              FilterChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.only(right: 6),
                avatar: Icon(
                  categoryIcon('Autre dépense'),
                  size: 14,
                  color: categoryColors[
                      legendVisible.length % categoryColors.length],
                ),
                label: Text(tr('Autres'), style: const TextStyle(fontSize: 11)),
                selected: selectedCategory == autresLegendKey,
                onSelected: (active) => setState(
                  () => selectedCategory =
                      active ? autresLegendKey : null,
                ),
              ),
          ],
        ),
      ],
      const SizedBox(height: 18),
      SummaryPanel(
        label: tr('Solde réellement disponible'),
        amount: money(remaining),
        footer: l10n.isEnglish
            ? '${money(upcoming)} bills · ${money(debtsDue)} debts owed'
            : '${money(upcoming)} charges · ${money(debtsDue)} dettes dues',
      ),
      if (remaining < 0)
        tile(
          'Solde insuffisant',
          'Tes liquidités ne couvrent pas les charges et dettes prévues.',
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
              label: Text(tr('Dépense')),
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
              label: Text(tr('Revenu')),
            ),
          ),
        ],
      ),
      if (receivables > 0) ...[
        const SizedBox(height: 10),
        tile(
          'Créances à recevoir',
          '${money(receivables)} ${tr('non réalisées jusqu’à encaissement')}',
          leading: const IconPlate(Icons.south_west, color: emerald),
        ),
      ],
    ];
    final recentOperations = <Widget>[
      section(
        selectedCategory == null
            ? 'Dernières opérations'
            : selectedCategory == autresLegendKey
                ? 'Autres'
                : shortCategoryLabel(selectedCategory!),
      ),
      ...history(
        entries: entries.where((op) {
          if (selectedCategory == null) return true;
          final label = op['label'] as String?;
          if (selectedCategory == autresLegendKey) {
            return label != null && legendAutresKeys.contains(label);
          }
          return label == selectedCategory;
        }),
      ),
    ];
    return (balance: balanceOverview, activity: recentOperations);
  }

  Widget tabletPage() {
    final (left, right, leftAction, rightAction) = switch (tab) {
      0 => () {
        final overviewContent = overview(wide: true);
        // Garde Dépense/Revenu dans le flux : les créances restent sous les boutons.
        final balance = overviewContent.balance;
        final actionIndex = balance.lastIndexWhere((widget) => widget is Row);
        if (actionIndex < 0) {
          return (balance, overviewContent.activity, null, null);
        }
        return (
          [
            ...balance.take(actionIndex),
            ...balance.skip(actionIndex + 1),
          ],
          overviewContent.activity,
          balance[actionIndex],
          null,
        );
      }(),
      _ => () {
        final content = page();
        return (
          content.take(1).toList(),
          content.sublist(1, content.length - 1),
          null,
          content.last,
        );
      }(),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, tab == 1 ? 76 : 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: tabletPane(left, 'summary', action: leftAction),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 6,
            child: tabletPane(right, 'detail', action: rightAction),
          ),
        ],
      ),
    );
  }

  Widget tabletPane(List<Widget> children, String pane, {Widget? action}) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xffeaf0f6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xffdce6ef)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                key: PageStorageKey((tab, pane)),
                primary: false,
                padding: const EdgeInsets.all(20),
                children: children,
              ),
            ),
            if (action != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: action,
              ),
          ],
        ),
      );

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
    final type = operationKind(op);
    final note = (op['note'] as String?)?.trim() ?? '';
    final at = DateTime.fromMillisecondsSinceEpoch(asInt(op['at']));
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final title = displayOperationLabel(op);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final sheetTr = context.l10n.t;
        return Container(
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
                    operationIcon(op),
                    color: delta < 0 ? rose : emerald,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sheetTr(title),
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
                            Text(
                              sheetTr(type),
                              style: const TextStyle(color: muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                op['delta'] == null ? sheetTr('Solde actualisé') : money(delta),
                style: numberStyle.copyWith(
                  fontSize: 28,
                  color: delta < 0 ? rose : emerald,
                ),
              ),
              const SizedBox(height: 16),
              _detailRow(
                sheetTr('Portefeuille'),
                wallet == null ? sheetTr('Inconnu') : walletName(wallet),
              ),
              _detailRow(
                sheetTr('Date'),
                '${dateText(at)} · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
              ),
              if (op['sms'] == true)
                _detailRow(
                  sheetTr('Source'),
                  sheetTr('Reçu SMS Mobile Money'),
                ),
              if (note.isNotEmpty) _detailRow(sheetTr('Détails'), note),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(sheetTr('Fermer')),
              ),
            ],
          ),
        );
      },
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

  List<Widget> savingsPage() {
    final target = goals.fold<int>(
      0,
      (sum, goal) => sum + asInt(goal['amount']),
    );
    final saved = goals.fold<int>(0, (sum, goal) => sum + goalSaved(goal));
    return [
      if (goals.isNotEmpty)
        SummaryPanel(
          label: tr('Total mis de côté'),
          amount: money(saved),
          footer: '${tr('Objectif total')} · ${money(target)}',
          progress: target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0),
        ),
      section('Mes objectifs'),
      if (goals.isEmpty)
        tile(
          'Aucun objectif d’épargne',
          'Crée un projet pour commencer à mettre de côté.',
          leading: const IconPlate(Icons.savings_outlined),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FilledButton.icon(
          onPressed: saving ? null : addGoal,
          icon: const Icon(Icons.add),
          label: Text(tr('Nouvel objectif')),
        ),
      ),
      for (final goal in goals) savingsGoalCard(goal),
    ];
  }

  Widget savingsGoalCard(RowData goal) {
    final saved = goalSaved(goal);
    final target = asInt(goal['amount']);
    final remaining = target - saved;
    final complete = remaining <= 0;
    final percent = asInt(goal['incomePercent']);
    final category = tr(goal['incomeCategory'] as String? ?? '');
    final payments = goal['payments'] as List;
    final progress = target <= 0 ? 1.0 : (saved / target).clamp(0.0, 1.0);
    const detailStyle = TextStyle(color: muted, fontSize: 12);
    return Card(
      key: PageStorageKey(goal),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpansionTile(
            tilePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Row(
              children: [
                IconPlate(
                  complete ? Icons.check_rounded : Icons.flag_outlined,
                  color: complete ? emerald : navyMid,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    goal['name'] as String? ?? tr('Objectif'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        money(saved),
                        style: numberStyle.copyWith(fontSize: 18, color: navy),
                      ),
                      Text(
                        '${tr('Cible')} · ${money(target)}',
                        style: detailStyle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  PocheProgress(value: progress, color: emerald),
                  const SizedBox(height: 7),
                  Text(
                    complete
                        ? tr('Objectif atteint')
                        : '${money(remaining)} ${tr('à épargner')}',
                    style: complete
                        ? detailStyle.copyWith(
                            color: navy,
                            fontWeight: FontWeight.w800,
                          )
                        : detailStyle,
                  ),
                ],
              ),
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            children: [
              const Divider(height: 16),
              Text(
                tr('Historique des versements'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(tr('Aucun versement'), style: detailStyle),
                ),
              for (final payment in payments.reversed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    payment['automatic'] == true
                        ? Icons.autorenew_rounded
                        : Icons.south_west_rounded,
                    color: navyMid,
                    size: 20,
                  ),
                  title: Text(money(asInt(payment['amount']))),
                  subtitle: Text(
                    [
                      dateText(
                        DateTime.fromMillisecondsSinceEpoch(
                          asInt(payment['at']),
                        ),
                      ),
                      payment['walletName'] as String? ??
                          tr('Source non renseignée'),
                      if (payment['automatic'] == true)
                        tr('Épargne automatique'),
                    ].join(' · '),
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: saving ? null : () => deleteGoal(goal),
                  child: Text(
                    tr('Supprimer l’objectif'),
                    style: const TextStyle(color: rose),
                  ),
                ),
              ),
            ],
          ),
          if (!complete)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: saving ? null : () => contribute(goal),
                    icon: const Icon(Icons.add),
                    label: Text(tr('Ajouter un versement')),
                  ),
                  TextButton.icon(
                    onPressed: saving
                        ? null
                        : () => configureAutomaticSaving(goal),
                    icon: const Icon(Icons.autorenew_rounded, size: 18),
                    style: TextButton.styleFrom(foregroundColor: navyMid),
                    label: Text(
                      percent > 0
                          ? '${tr('Épargne automatique')} · $percent % · $category'
                          : tr('Configurer l’épargne automatique'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> page() {
    switch (tab) {
      case 0:
        final content = overview(wide: false);
        return [...content.balance, ...content.activity];
      case 1:
        return [
          SummaryPanel(
            label: tr('Solde de tes portefeuilles'),
            amount: money(total),
            footer: l10n.isEnglish
              ? '${wallets.length} wallet(s) · FCFA'
              : '${wallets.length} portefeuille(s) · FCFA',
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
                        label: Text(
                          tr('Supprimer ce portefeuille'),
                          style: const TextStyle(color: rose),
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
            label: Text(tr('Ajouter un portefeuille')),
          ),
        ];
      case 2:
        final now = DateTime.now();
        final dettes = debts.where(isDette).toList();
        final creances = debts.where(isCreance).toList();
        sortDebtsByDueDate(dettes);
        sortDebtsByDueDate(creances);
        return [
          SummaryPanel(
            label: tr('Solde réellement disponible'),
            amount: money(realAvailable),
            footer: l10n.isEnglish
                ? 'Wallets ${money(total)} · bills ${money(upcoming)} · debts ${money(openDebtsAmount)}'
                : 'Poches ${money(total)} · charges ${money(upcoming)} · dettes ${money(openDebtsAmount)}',
          ),
          if (openReceivablesAmount > 0)
            tile(
              'Créances en attente',
              '${money(openReceivablesAmount)} ${tr('non comptées dans le disponible')}',
              leading: const IconPlate(Icons.hourglass_empty, color: emerald),
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
                l10n.isEnglish
                    ? 'Calendar · ${l10n.month(now.month)}'
                    : 'Calendrier · ${l10n.month(now.month)}',
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
              '${money(charge['amount'] as int)} · ${dateText(DateTime.parse(charge['date'] as String))}\n${tr(charge['frequency'] as String)} · ${charge['wallet']}',
              leading: IconPlate(categoryIcon(charge['name'] as String?)),
              onTap: () => editCharge(charge),
              trailing: IconButton(
                tooltip: tr('Gérer l’échéance'),
                onPressed: saving ? null : () => resolveCharge(charge),
                icon: const Icon(Icons.more_vert),
              ),
            ),
          OutlinedButton.icon(
            onPressed: saving ? null : () => editCharge(),
            icon: const Icon(Icons.add),
            label: Text(tr('Ajouter une charge')),
          ),
          section('Dettes (je dois)'),
          if (dettes.isEmpty)
            tile(
              'Aucune dette',
              'Enregistre ce que tu dois pour le réserver dans ton disponible.',
              leading: const IconPlate(Icons.north_east, color: rose),
            ),
          for (final debt in dettes) debtCard(debt),
          section('Créances (on me doit)'),
          if (creances.isEmpty)
            tile(
              'Aucune créance',
              'Ce que l’on te doit reste hors solde jusqu’à encaissement.',
              leading: const IconPlate(Icons.south_west, color: emerald),
            ),
          for (final debt in creances) debtCard(debt),
          FilledButton.icon(
            onPressed: saving ? null : () => editDebt(),
            icon: const Icon(Icons.add),
            label: Text(tr('Ajouter dette / créance')),
          ),
        ];
      case 3:
        return savingsPage();
      default:
        return [
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
                            Text(
                              tr('Protection de l’app'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lockEnabled
                                  ? (l10n.isEnglish
                                      ? 'PIN enabled${biometricEnabled ? ' · biometrics on' : ''}'
                                      : 'Code PIN actif${biometricEnabled ? ' · biométrie on' : ''}')
                                  : tr('Aucun verrouillage pour l’instant'),
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
                              ? mintWash
                              : const Color(0xfff1f5f9),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          lockEnabled ? tr('Actif') : tr('Off'),
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
                            ? tr('Désactiver le verrouillage')
                            : tr('Définir un code PIN'),
                      ),
                    ),
                  ),
                  if (lockEnabled) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.fingerprint, color: emerald),
                      title: Text(tr('Biométrie')),
                      subtitle: Text(tr('Empreinte ou visage')),
                      value: biometricEnabled,
                      onChanged: saving ? null : toggleBiometric,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.password_outlined, color: emerald),
                      title: Text(tr('Changer le code PIN')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: saving
                          ? null
                          : () async {
                              final current = await showPinSheet(
                                context,
                                title: tr('Code actuel'),
                                subtitle: tr('Entre ton code pour continuer.'),
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
          section('Notifications'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined, color: emerald),
                  title: Text(tr('Notifications')),
                  subtitle: Text(tr('Échéances et seuils')),
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
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.warning_amber_rounded, color: emerald),
                  title: Text(tr('Seuil de solde')),
                  subtitle: Text(
                    thresholdEnabled
                        ? (l10n.isEnglish
                            ? 'Under ${money(thresholdAmount)}'
                            : 'Sous ${money(thresholdAmount)}')
                        : tr('Désactivé'),
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
              ],
            ),
          ),
          section('Mobile Money'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.sms_outlined, color: emerald),
              title: Text(tr('Lecture SMS auto')),
              subtitle: Text(
                tr(
                  isIos
                      ? 'Indisponible sur iOS'
                      : 'Orange Money et MTN MoMo',
                ),
              ),
              value: enabled,
              onChanged: saving ? null : (_) => toggleSms(),
            ),
          ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: syncing ? null : () => sync(manual: true),
                icon: syncing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  syncing ? tr('Lecture…') : tr('Actualiser les soldes'),
                ),
              ),
            ),
          section('Budget'),
          tile(
            'Devise',
            'Franc CFA (Afrique centrale)',
            leading: const IconPlate(Icons.payments_outlined),
            trailing: const Chip(label: Text('XAF')),
          ),
          tile(
            'Catégories',
            l10n.isEnglish
                ? '${expenseCategories.length} expenses · ${incomeCategories.length} income'
                : '${expenseCategories.length} dépenses · ${incomeCategories.length} revenus',
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
              if (values != null) {
                final name = values[1].trim();
                final asExpense = values[0] == 'Dépense';
                if (name.isEmpty) return;
                await change(() {
                  if (!categories.contains(name)) categories.add(name);
                  if (asExpense) {
                    if (!extraExpenseCategories.contains(name)) {
                      extraExpenseCategories.add(name);
                    }
                    extraIncomeCategories.remove(name);
                  } else {
                    if (!extraIncomeCategories.contains(name)) {
                      extraIncomeCategories.add(name);
                    }
                    extraExpenseCategories.remove(name);
                  }
                });
                message(
                  l10n.isEnglish
                      ? 'Category « $name » added.'
                      : 'Catégorie « $name » ajoutée.',
                );
              }
            },
          ),
          section('Données'),
          tile(
            'Jeu de démo',
            'Peuple l’app avec un exemple complet (FCFA).',
            leading: const IconPlate(Icons.auto_awesome_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: saving ? null : () => loadDemoData(),
          ),
          Row(
            children: [
              Expanded(
                child: _SettingsPairCard(
                  icon: Icons.qr_code_2_rounded,
                  title: tr('Envoyer'),
                  subtitle: tr('Afficher le QR'),
                  onTap: saving ? null : openTransferExport,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SettingsPairCard(
                  icon: Icons.qr_code_scanner_rounded,
                  title: tr('Recevoir'),
                  subtitle: tr('Scanner le QR'),
                  onTap: saving ? null : openTransferImport,
                ),
              ),
            ],
          ),
          section('Application'),
          tile(
            'À propos de PocheNette',
            'Édité par Koryx · www.koryx.net',
            leading: const IconPlate(Icons.info_outline_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AboutPage()),
            ),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (showSplash || !ready) {
      return SplashView(
        failed: loadFailed,
        errorText: tr('Impossible de charger les données.'),
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
          tab == 0 ? 'PocheNette' : l10n.tabTitles[tab],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (tab == 0)
            IconButton(
              tooltip: tr('Transfert'),
              onPressed: saving || wallets.length < 2
                  ? null
                  : () => addTransaction(initialType: 'Transfert'),
              icon: const Icon(Icons.swap_horiz),
            ),
          if (tab == 4 && enabled)
            IconButton(
              tooltip: tr('Actualiser les soldes'),
              onPressed: () => sync(manual: true),
              icon: const Icon(Icons.sync),
            ),
          PopupMenuButton<String>(
            tooltip: tr('Menu'),
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) async {
              switch (value) {
                case 'guide':
                  showPageGuide(context, tab);
                case 'calendar':
                  if (!mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ChargesCalendarPage(charges: charges, money: money),
                    ),
                  );
                case 'stats':
                  if (!mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => StatsPage(
                        operations: operations,
                        money: money,
                        categories: categories,
                      ),
                    ),
                  );
                case 'lang_fr':
                  await setAppLocale('fr');
                case 'lang_en':
                  await setAppLocale('en');
                case 'about':
                  if (!mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                  );
                case 'terms':
                  final uri = Uri.parse(BrandConstants.termsUrl);
                  final ok = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok && mounted) {
                    message('Impossible d’ouvrir les CGU.');
                  }
                case 'settings':
                  setState(() => tab = 4);
              }
            },
            itemBuilder: (context) {
              final currentLocale =
                  localeCode ?? Localizations.localeOf(context).languageCode;
              final isEnglish = currentLocale.startsWith('en');
              return [
                PopupMenuItem(
                  value: 'calendar',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text(tr('Calendrier')),
                  ),
                ),
                PopupMenuItem(
                  value: 'stats',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insights_outlined),
                    title: Text(tr('Stats')),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'lang_fr',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Text('🇫🇷', style: TextStyle(fontSize: 20)),
                    title: Text(tr('Français')),
                    trailing: isEnglish
                        ? null
                        : const Icon(Icons.check_rounded, color: emerald),
                  ),
                ),
                PopupMenuItem(
                  value: 'lang_en',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Text('🇬🇧', style: TextStyle(fontSize: 20)),
                    title: const Text('English'),
                    trailing: isEnglish
                        ? const Icon(Icons.check_rounded, color: emerald)
                        : null,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'guide',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.help_outline_rounded),
                    title: Text(tr('Guide rapide')),
                  ),
                ),
                PopupMenuItem(
                  value: 'about',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(tr('À propos')),
                  ),
                ),
                PopupMenuItem(
                  value: 'terms',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(tr('CGU')),
                  ),
                ),
                if (tab != 4)
                  PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.settings_outlined),
                      title: Text(tr('Réglages')),
                    ),
                  ),
              ];
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final tablet = wide && constraints.maxHeight >= 420 && tab < 4;
            return AnimatedSwitcher(
              duration: motionDuration(context, 180),
              child: tablet
                  ? KeyedSubtree(
                      key: ValueKey(('tablet', tab)),
                      child: tabletPage(),
                    )
                  : ListView(
                      key: PageStorageKey(tab),
                      padding: EdgeInsets.fromLTRB(
                        wide ? 28 : 16,
                        wide ? 24 : 14,
                        wide ? 28 : 16,
                        24 + (tab == 1 ? 72 : 8),
                      ),
                      children: page(),
                    ),
            );
          },
        ),
      ),
      floatingActionButton: tab == 1
          ? FloatingActionButton.extended(
              onPressed: saving ? null : addTransaction,
              icon: const Icon(Icons.add),
              label: Text(tr('Transaction')),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navLabels[0],
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: l10n.navLabels[1],
          ),
          NavigationDestination(
            icon: const Icon(Icons.event_outlined),
            selectedIcon: const Icon(Icons.event),
            label: l10n.navLabels[2],
          ),
          NavigationDestination(
            icon: const Icon(Icons.savings_outlined),
            selectedIcon: const Icon(Icons.savings),
            label: l10n.navLabels[3],
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navLabels[4],
          ),
        ],
      ),
    );
  }
}

class _SettingsPairCard extends StatelessWidget {
  const _SettingsPairCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: emerald, size: 22),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
