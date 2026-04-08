import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../theme/app_spacing.dart';

class ImportQrScannerTab extends StatefulWidget {
  final Future<void> Function(String jsonText) onImportJson;

  const ImportQrScannerTab({required this.onImportJson, super.key});

  @override
  State<ImportQrScannerTab> createState() => _ImportQrScannerTabState();
}

class _ImportQrScannerTabState extends State<ImportQrScannerTab> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  Future<void> _handleScan(String code) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      await widget.onImportJson(code);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _importFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final result = await _scannerController.analyzeImage(image.path);
    if (result == null || result.barcodes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.loc.importNoQrCode),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final code = result.barcodes.first.rawValue;
    if (code != null) {
      await _handleScan(code);
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(
            height: 400,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    for (final barcode in capture.barcodes) {
                      final code = barcode.rawValue;
                      if (code != null) {
                        _handleScan(code);
                      }
                    }
                  },
                ),
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppSpacing.emptyStatePaddingAll,
            child: FloatingActionButton(
              onPressed: _isProcessing ? null : _importFromGallery,
              child: const Icon(Icons.photo_library),
            ),
          ),
          if (_isProcessing)
            const Padding(
              padding: AppSpacing.screenPaddingAll,
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
