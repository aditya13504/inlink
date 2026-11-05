import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scans one QR code and returns its raw content to the caller.
/// The caller must validate the bundle and complete fingerprint verification.
class ContactQrScannerPage extends StatefulWidget {
  const ContactQrScannerPage({super.key});

  @override
  State<ContactQrScannerPage> createState() => _ContactQrScannerPageState();
}

class _ContactQrScannerPageState extends State<ContactQrScannerPage> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (value.isEmpty) return;

    setState(() {
      _handled = true;
    });
    Navigator.of(context).pop<String>(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan contact QR')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Scan an InLink public identity QR code. Scanning only imports public data; '
                'it does not verify or trust the person.',
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: _onDetect,
                errorBuilder: (context, error, child) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.no_photography_outlined, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'Camera unavailable. Check camera permission and try again, '
                            'or return and paste the public bundle instead.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.errorCode.name,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                label: const Text('Cancel scan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
