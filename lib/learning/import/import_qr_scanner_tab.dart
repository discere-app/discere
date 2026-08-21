import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ImportQrScannerTab extends StatefulWidget {
  final Future<void> Function(String code) onScanResult;

  const ImportQrScannerTab({required this.onScanResult, super.key});

  @override
  State<ImportQrScannerTab> createState() => _ImportQrScannerTabState();
}

class _ImportQrScannerTabState extends State<ImportQrScannerTab> {
  static final _log = Logger.forType(_ImportQrScannerTabState);
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  Future<void> _handleScan(String code) async {
    if (_isProcessing) return;

    _log.debug('QR code detected with ${code.length} chars');
    setState(() => _isProcessing = true);
    try {
      await widget.onScanResult(code);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _importFromGallery() async {
    _log.debug('Opening gallery image picker for QR import');
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    _log.debug('Analyzing picked image: ${image.path}');
    final result = await _scannerController.analyzeImage(image.path);
    if (result == null || result.barcodes.isEmpty) {
      _log.warn('Gallery image contained no readable QR code: ${image.path}');
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
                    _log.debug(
                      'Camera detection produced ${capture.barcodes.length} barcode(s)',
                    );
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
              heroTag: 'fab-import-gallery',
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
