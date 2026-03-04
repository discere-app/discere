import 'dart:async';
import 'package:discere/extensions/localization_extension.dart';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../service/learning/decks_service.dart';
import '../../theme/ocean_theme/ocean_colors.dart';

class ImportDeckPage extends StatefulWidget {
  const ImportDeckPage({super.key});

  @override
  State<ImportDeckPage> createState() => _ImportDeckPageState();
}

class _ImportDeckPageState extends State<ImportDeckPage>
    with TickerProviderStateMixin {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _scanned = false;
  bool _isImporting = false;

  // Animate the scan line
  late AnimationController _lineController;
  late Animation<double> _lineAnimation;

  @override
  void initState() {
    super.initState();
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _lineAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_lineController);
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _lineController.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_scanned || _isImporting) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.displayValue == null) return;

    setState(() => _scanned = true);
    await _scannerController.stop();

    try {
      await context
          .read<DecksService>()
          .createDeckFromQrCode(barcode!);
      if (mounted) {
        _showSuccess();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
        setState(() => _scanned = false);
        _scannerController.start();
      }
    }
  }

  void _showSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.loc.importSuccess),
      backgroundColor: OceanColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.loc.importFailed(message)),
      backgroundColor: Theme.of(context).colorScheme.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _pickImageFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    setState(() => _isImporting = true);
    try {
      final BarcodeCapture? capture =
          await _scannerController.analyzeImage(image.path);
      if (capture == null || capture.barcodes.isEmpty) {
        if (mounted) _showError(context.loc.importNoQrCode);
      } else {
        await _onBarcodeDetected(capture);
      }
    } catch (e) {
      if (mounted) _showError(context.loc.importErrorAnalyzing(e.toString()));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.importDeckTitle),
        centerTitle: true,
      ),
      body: _QrScannerTab(
        scannerController: _scannerController,
        lineAnimation: _lineAnimation,
        onDetect: _onBarcodeDetected,
        onPickImage: _pickImageFromGallery,
        isImporting: _isImporting,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QR Scanner View
// ---------------------------------------------------------------------------
class _QrScannerTab extends StatelessWidget {
  final MobileScannerController scannerController;
  final Animation<double> lineAnimation;
  final void Function(BarcodeCapture) onDetect;
  final VoidCallback onPickImage;
  final bool isImporting;

  const _QrScannerTab({
    required this.scannerController,
    required this.lineAnimation,
    required this.onDetect,
    required this.onPickImage,
    required this.isImporting,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Camera feed
                  MobileScanner(
                    controller: scannerController,
                    onDetect: onDetect,
                    fit: BoxFit.cover,
                  ),
                  // Dark overlay outside frame
              _ScanOverlay(primary: primary, lineAnimation: lineAnimation),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.loc.importInstruction,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: isImporting ? null : onPickImage,
            icon: isImporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library),
            label: Text(context.loc.importUploadGallery),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  final Color primary;
  final Animation<double> lineAnimation;
  const _ScanOverlay({required this.primary, required this.lineAnimation});

  @override
  Widget build(BuildContext context) {
    const frameSize = 240.0;
    const cornerSize = 28.0;
    const cornerThickness = 4.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Semi-transparent overlay
        ColoredBox(color: Colors.black.withOpacity(0.45)),
        // Cut-out frame
        Container(
          width: frameSize,
          height: frameSize,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        // Corner brackets
        SizedBox(
          width: frameSize,
          height: frameSize,
          child: Stack(
            children: [
              // Top-left
              Positioned(
                top: -2,
                left: -2,
                child: _Corner(primary, [_CornerSide.top, _CornerSide.left],
                    cornerSize, cornerThickness),
              ),
              // Top-right
              Positioned(
                top: -2,
                right: -2,
                child: _Corner(primary, [_CornerSide.top, _CornerSide.right],
                    cornerSize, cornerThickness),
              ),
              // Bottom-left
              Positioned(
                bottom: -2,
                left: -2,
                child: _Corner(primary, [_CornerSide.bottom, _CornerSide.left],
                    cornerSize, cornerThickness),
              ),
              // Bottom-right
              Positioned(
                bottom: -2,
                right: -2,
                child: _Corner(primary, [_CornerSide.bottom, _CornerSide.right],
                    cornerSize, cornerThickness),
              ),
              // Animated scan line
              AnimatedBuilder(
                animation: lineAnimation,
                builder: (_, __) => Positioned(
                  top: lineAnimation.value * (frameSize - 2),
                  left: 8,
                  right: 8,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        primary.withOpacity(0.8),
                        Colors.transparent,
                      ]),
                      boxShadow: [
                        BoxShadow(
                            color: primary.withOpacity(0.4),
                            blurRadius: 6,
                            spreadRadius: 1),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _CornerSide { top, bottom, left, right }

class _Corner extends StatelessWidget {
  final Color color;
  final List<_CornerSide> sides;
  final double size;
  final double thickness;
  const _Corner(this.color, this.sides, this.size, this.thickness);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(color, sides, thickness),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final List<_CornerSide> sides;
  final double thickness;
  _CornerPainter(this.color, this.sides, this.thickness);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    for (final side in sides) {
      switch (side) {
        case _CornerSide.top:
          canvas.drawLine(Offset(0, 0), Offset(size.width, 0), paint);
        case _CornerSide.bottom:
          canvas.drawLine(
              Offset(0, size.height), Offset(size.width, size.height), paint);
        case _CornerSide.left:
          canvas.drawLine(Offset(0, 0), Offset(0, size.height), paint);
        case _CornerSide.right:
          canvas.drawLine(
              Offset(size.width, 0), Offset(size.width, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => color != old.color;
}
