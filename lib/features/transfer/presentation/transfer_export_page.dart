import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../design.dart';
import '../data/transfer_host.dart';
import '../domain/transfer_bundle.dart';

class TransferExportPage extends StatefulWidget {
  const TransferExportPage({
    super.key,
    required this.buildBundle,
  });

  final Future<TransferBundle> Function() buildBundle;

  @override
  State<TransferExportPage> createState() => _TransferExportPageState();
}

class _TransferExportPageState extends State<TransferExportPage> {
  final TransferHost _host = TransferHost();
  TransferOffer? _offer;
  String? _error;
  bool _busy = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
      _done = false;
    });
    try {
      final bundle = await widget.buildBundle();
      _host.onDownloaded = () {
        if (!mounted) return;
        setState(() => _done = true);
      };
      final offer = await _host.start(bundle: bundle);
      if (!mounted) return;
      setState(() {
        _offer = offer;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  void dispose() {
    _host.onDownloaded = null;
    _host.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(title: const Text('Envoyer les données')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const Text(
            'Sur le nouveau téléphone, ouvre PocheNette → Réglages → '
            'Recevoir un transfert, puis scanne ce QR.',
            style: TextStyle(color: muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text(
            'Les deux appareils doivent être sur le même Wi‑Fi '
            '(ou hotspot). Android ↔ iOS supporté.',
            style: TextStyle(color: muted, height: 1.4, fontSize: 13),
          ),
          const SizedBox(height: 24),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null) ...[
            IconPlate(Icons.wifi_off_rounded, color: rose),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: rose, height: 1.4)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _start, child: const Text('Réessayer')),
          ] else if (offer != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: border),
                ),
                child: QrImageView(
                  data: offer.qrPayload,
                  size: 240,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: ink,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: ink,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                leading: IconPlate(
                  _done ? Icons.check_circle_rounded : Icons.sensors_rounded,
                  color: _done ? mint : emerald,
                ),
                title: Text(
                  _done ? 'Transfert terminé' : 'En attente du scan…',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  _done
                      ? 'Tu peux fermer cet écran. Garde l’ancien téléphone '
                          'allumé jusqu’à confirmation sur le nouveau.'
                      : 'Session locale · ${offer.host}:${offer.port}',
                ),
              ),
            ),
            if (_done)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Terminer'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
