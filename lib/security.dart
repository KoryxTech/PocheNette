import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'design.dart';
import 'l10n/l10n.dart';

String hashPin(String pin) =>
    sha256.convert(utf8.encode('pochenette:$pin')).toString();

class AppLock {
  AppLock(this.channel);
  final MethodChannel channel;
  final LocalAuthentication auth = LocalAuthentication();

  Future<String?> read(String key) async {
    try {
      return await channel.invokeMethod<String>('secureGet', key);
    } on PlatformException {
      return null;
    }
  }

  Future<bool> write(String key, String? value) async {
    try {
      await channel.invokeMethod<void>('secureSet', {
        'key': key,
        'value': value,
      });
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> get lockEnabled async => (await read('lockEnabled')) == '1';
  Future<bool> get biometricEnabled async =>
      (await read('biometricEnabled')) == '1';
  Future<String?> get pinHash => read('pinHash');

  Future<bool> setLockEnabled(bool value) =>
      write('lockEnabled', value ? '1' : '0');
  Future<bool> setBiometricEnabled(bool value) =>
      write('biometricEnabled', value ? '1' : '0');
  Future<bool> setPin(String pin) => write('pinHash', hashPin(pin));

  Future<void> clearPin() async {
    await write('pinHash', null);
    await setLockEnabled(false);
    await setBiometricEnabled(false);
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await pinHash;
    return stored != null && stored == hashPin(pin);
  }

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      final enrolled = await auth.getAvailableBiometrics();
      return supported && canCheck && enrolled.isNotEmpty;
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  Future<bool> unlockWithBiometrics({String? reason}) async {
    try {
      return await auth.authenticate(
        localizedReason:
            reason ?? 'Déverrouille PocheNette avec ta biométrie',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }
}

/// Full-screen PIN gate — more reliable than bottom sheets on gesture nav.
Future<String?> showPinSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  bool showBiometric = false,
  Future<bool> Function()? onBiometric,
}) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      opaque: true,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondary) => _PinGate(
        title: title,
        subtitle: subtitle,
        showBiometric: showBiometric,
        onBiometric: onBiometric,
      ),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

Future<String?> setupPinFlow(BuildContext context) async {
  final l10n = context.l10n;
  final first = await showPinSheet(
    context,
    title: l10n.t('Crée ton code'),
    subtitle: l10n.t('Choisis 4 chiffres pour protéger PocheNette.'),
  );
  if (first == null || !context.mounted) return null;
  final second = await showPinSheet(
    context,
    title: l10n.t('Confirme ton code'),
    subtitle: l10n.t('Saisis le même code une seconde fois.'),
  );
  if (second == null) return null;
  if (first != second) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('Les codes ne correspondent pas.'))),
      );
    }
    return null;
  }
  return first;
}

Future<String?> askPin(
  BuildContext context, {
  required String title,
  String? confirmTitle,
}) async {
  if (confirmTitle != null) return setupPinFlow(context);
  return showPinSheet(
    context,
    title: title,
    subtitle: context.l10n.t('Saisis ton code à 4 chiffres.'),
  );
}

class _PinGate extends StatefulWidget {
  const _PinGate({
    required this.title,
    required this.subtitle,
    this.showBiometric = false,
    this.onBiometric,
  });

  final String title;
  final String subtitle;
  final bool showBiometric;
  final Future<bool> Function()? onBiometric;

  @override
  State<_PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<_PinGate> {
  String pin = '';
  String? error;
  bool busy = false;

  Future<void> _bio() async {
    if (busy || widget.onBiometric == null) return;
    setState(() => busy = true);
    final ok = await widget.onBiometric!();
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context, '__bio__');
  }

  void _tap(String digit) {
    if (busy || pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      pin += digit;
      error = null;
    });
    if (pin.length == 4) {
      Future<void>.delayed(const Duration(milliseconds: 140), () {
        if (mounted) Navigator.pop(context, pin);
      });
    }
  }

  void _delete() {
    if (busy || pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => pin = pin.substring(0, pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom.clamp(0, 48)),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    minimumSize: const Size(96, 48),
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(context.l10n.t('Fermer')),
                ),
              ),
              const Spacer(flex: 2),
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                error ?? widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: error != null
                      ? const Color(0xffffb4c0)
                      : mint,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final filled = index < pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: filled ? 16 : 14,
                    height: filled ? 16 : 14,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? Colors.white
                          : Colors.white.withValues(alpha: .22),
                      boxShadow: filled
                          ? [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: .35),
                                blurRadius: 10,
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    for (final row in [
                      ['1', '2', '3'],
                      ['4', '5', '6'],
                      ['7', '8', '9'],
                      ['bio', '0', 'del'],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (final key in row)
                              _KeyButton(
                                label: key,
                                enabled: !busy,
                                showBio:
                                    widget.showBiometric &&
                                    widget.onBiometric != null,
                                onDigit: _tap,
                                onDelete: _delete,
                                onBio: _bio,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.enabled,
    required this.showBio,
    required this.onDigit,
    required this.onDelete,
    required this.onBio,
  });

  final String label;
  final bool enabled;
  final bool showBio;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onBio;

  @override
  Widget build(BuildContext context) {
    if (label == 'bio') {
      if (!showBio) return const SizedBox(width: 78, height: 78);
      return _round(
        semanticLabel: context.l10n.t('Biométrie'),
        onTap: enabled ? onBio : null,
        child: const Icon(Icons.fingerprint, size: 30, color: emerald),
      );
    }
    if (label == 'del') {
      return _round(
        semanticLabel: context.l10n.t('Effacer'),
        onTap: enabled ? onDelete : null,
        child: const Icon(Icons.backspace_outlined, size: 24, color: ink),
      );
    }
    return _round(
      semanticLabel: label,
      onTap: enabled ? () => onDigit(label) : null,
      child: Text(
        label,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _round({
    required Widget child,
    required String semanticLabel,
    VoidCallback? onTap,
  }) => Semantics(
    button: true,
    enabled: onTap != null,
    label: semanticLabel,
    child: Material(
      color: const Color(0xffeef2f7),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 78,
          height: 78,
          child: ExcludeSemantics(child: Center(child: child)),
        ),
      ),
    ),
  );
}

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.lock,
    required this.onUnlocked,
  });

  final AppLock lock;
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String pin = '';
  String? error;
  bool biometric = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final enabled = await widget.lock.biometricEnabled;
    final available = enabled && await widget.lock.canUseBiometrics();
    if (!mounted) return;
    setState(() => biometric = available);
    if (available) {
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (mounted) await _biometric();
    }
  }

  Future<void> _biometric() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final ok = await widget.lock.unlockWithBiometrics(
      reason: context.l10n.t('Déverrouille PocheNette avec ta biométrie'),
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(
        () => error = context.l10n.t('Biométrie annulée — utilise ton code'),
      );
    }
  }

  Future<void> _submit() async {
    if (pin.length != 4 || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final ok = await widget.lock.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      widget.onUnlocked();
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() {
      busy = false;
      pin = '';
      error = context.l10n.t('Code incorrect');
    });
  }

  void _tap(String digit) {
    if (pin.length >= 4 || busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      pin += digit;
      error = null;
    });
    if (pin.length == 4) _submit();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: navy,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 20 + bottom.clamp(0, 48)),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 76,
                  height: 76,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Image.asset(
                    'assets/brand/poche-mark.png',
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                'PocheNette',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error ?? context.l10n.t('Entre ton code pour continuer'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: error != null
                      ? const Color(0xffffb4c0)
                      : mint,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final filled = index < pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? Colors.white
                          : Colors.white.withValues(alpha: .22),
                    ),
                  );
                }),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(
                  children: [
                    for (final row in [
                      ['1', '2', '3'],
                      ['4', '5', '6'],
                      ['7', '8', '9'],
                      ['bio', '0', 'del'],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (final key in row)
                              _KeyButton(
                                label: key,
                                enabled: !busy,
                                showBio: biometric,
                                onDigit: _tap,
                                onDelete: () => setState(() {
                                  if (pin.isNotEmpty) {
                                    pin = pin.substring(0, pin.length - 1);
                                  }
                                }),
                                onBio: _biometric,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
