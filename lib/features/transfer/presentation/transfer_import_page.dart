import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../design.dart';
import '../data/transfer_client.dart';
import '../domain/transfer_bundle.dart';

class TransferImportPage extends StatefulWidget {
  const TransferImportPage({
    super.key,
    required this.onReceived,
  });

  final Future<void> Function(TransferBundle bundle) onReceived;

  @override
  State<TransferImportPage> createState() => _TransferImportPageState();
}

class _TransferImportPageState extends State<TransferImportPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  final TransferClient _client = TransferClient();
  bool _handling = false;
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ensureCamera();
  }

  Future<void> _ensureCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted && mounted) {
      setState(() => _error = 'Autorise la caméra pour scanner le QR.');
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || _busy) return;
    String? raw;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.startsWith('pochenette://transfer')) {
        raw = value;
        break;
      }
    }
    if (raw == null) return;

    _handling = true;
    await _controller.stop();
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remplacer les données ?'),
        content: const Text(
          'Le transfert écrasera les données actuelles de ce téléphone '
          '(poches, historique, charges, épargne, réglages et code PIN).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      _handling = false;
      await _controller.start();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Connexion à l’autre téléphone…';
    });

    try {
      final pairing = TransferPairing.fromQr(raw);
      setState(() => _status = 'Téléchargement chiffré…');
      final bundle = await _client.fetch(pairing);
      setState(() => _status = 'Restauration…');
      await widget.onReceived(bundle);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _handling = false;
        _status = null;
        _error = '$error';
      });
      await _controller.start();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink,
      appBar: AppBar(
        title: const Text('Recevoir un transfert'),
        backgroundColor: ink,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
                if (_busy)
                  ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 16),
                          Text(
                            _status ?? 'Transfert…',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scanne le QR affiché sur l’ancien téléphone.',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Même Wi‑Fi / hotspot. Fonctionne Android ↔ iOS.',
                  style: TextStyle(color: muted, height: 1.35),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: rose)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
