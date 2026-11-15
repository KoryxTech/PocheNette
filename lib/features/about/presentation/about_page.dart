import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/brand_constants.dart';
import '../../../design.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.appVersion = '1.0.0'});

  final String appVersion;

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir le lien.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(title: const Text('À propos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: navy,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Image.asset(
                'assets/brand/poche-mark.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Poche',
                    style: TextStyle(
                      color: navy,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: 'Nette',
                    style: TextStyle(
                      color: emerald,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Version $appVersion',
              style: const TextStyle(color: muted, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Suivi de budget et Mobile Money, conçu pour le Cameroun.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.4),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Édité par',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    BrandConstants.publisherName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    BrandConstants.publisherHost,
                    style: TextStyle(
                      color: emerald,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          _open(context, BrandConstants.publisherUrl),
                      icon: const Icon(Icons.language_rounded),
                      label: const Text('Visiter www.koryx.net'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const IconPlate(Icons.description_outlined),
              title: const Text('Conditions générales d’utilisation'),
              subtitle: const Text('Lire les CGU sur koryx.net'),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => _open(context, BrandConstants.termsUrl),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '© ${DateTime.now().year} ${BrandConstants.publisherName}. Tous droits réservés.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
