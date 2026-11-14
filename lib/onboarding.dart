import 'package:flutter/material.dart';

import 'design.dart';
import 'l10n/l10n.dart';

List<({IconData icon, String title, String body})> onboardingPages(L10n l10n) => [
  (
    icon: Icons.account_balance_wallet_outlined,
    title: l10n.t('Tes poches, en un coup d’œil'),
    body: l10n.t(
      'Centralise Orange Money, MTN MoMo, Wave, espèces et banques. Suis ton solde total en FCFA sans quitter ton téléphone.',
    ),
  ),
  (
    icon: Icons.sms_outlined,
    title: l10n.t('SMS optionnels, données locales'),
    body: l10n.t(
      'Active la lecture des reçus Mobile Money si tu veux. Tout reste sur cet appareil : pas de compte, pas d’abonnement.',
    ),
  ),
  (
    icon: Icons.lock_outline,
    title: l10n.t('Protège PocheNette'),
    body: l10n.t(
      'Tu pourras activer un code PIN et la biométrie dans Réglages. Gratuit, privé, à ton rythme.',
    ),
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int page = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = onboardingPages(l10n);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: canvas,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 28 + bottomInset),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  button: true,
                  label: l10n.t('Passer'),
                  child: Material(
                    color: const Color(0xffe7f8f0),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: widget.onDone,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        child: Text(
                          l10n.t('Passer'),
                          style: const TextStyle(
                            color: emerald,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: controller,
                  itemCount: pages.length,
                  onPageChanged: (value) => setState(() => page = value),
                  itemBuilder: (context, index) {
                    final item = pages[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconPlate(item.icon, color: emerald),
                        const SizedBox(height: 20),
                        Image.asset(
                          'assets/brand/poche-mark.png',
                          width: 64,
                          height: 64,
                          filterQuality: FilterQuality.medium,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          item.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: i == page ? 18 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == page ? emerald : border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Semantics(
                button: true,
                label: page >= pages.length - 1
                    ? l10n.t('Commencer')
                    : l10n.t('Continuer'),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () {
                      if (page >= pages.length - 1) {
                        widget.onDone();
                        return;
                      }
                      controller.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: Text(
                      page >= pages.length - 1
                          ? l10n.t('Commencer')
                          : l10n.t('Continuer'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
