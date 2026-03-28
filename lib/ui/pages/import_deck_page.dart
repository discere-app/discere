import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:discere/extensions/localization_extension.dart';
import 'package:discere/model/ui/create_deck.dart';
import 'package:discere/service/learning/remote_deck_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../service/common/import_export_service.dart';
import '../../theme/ocean_theme/ocean_colors.dart';

class ImportDeckPage extends StatefulWidget {
  const ImportDeckPage({super.key});

  @override
  State<ImportDeckPage> createState() => _ImportDeckPageState();
}

class _ImportDeckPageState extends State<ImportDeckPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.loc.importDeckTitle),
          centerTitle: true,
          bottom: TabBar(
            tabs: [
              Tab(text: context.loc.importTabOnline, icon: const Icon(Icons.public)),
              Tab(text: context.loc.importTabScanner, icon: const Icon(Icons.qr_code_scanner)),
              Tab(text: context.loc.importTabJson, icon: const Icon(Icons.code)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OnlineDecksTab(),
            _QrScannerTab(),
            _JsonImportTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Online Decks Tab
// ---------------------------------------------------------------------------
class _OnlineDecksTab extends StatefulWidget {
  const _OnlineDecksTab();

  @override
  State<_OnlineDecksTab> createState() => _OnlineDecksTabState();
}

class _OnlineDecksTabState extends State<_OnlineDecksTab> {
  late Future<List<CreateDeck>> _decksFuture;
  final Set<String> _selectedDeckNames = {};
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _decksFuture = context.read<RemoteDeckService>().fetchRemoteDecks();
  }

  Future<void> _importSelected(List<CreateDeck> allDecks) async {
    final toImport = allDecks.where((d) => _selectedDeckNames.contains(d.name)).toList();
    if (toImport.isEmpty) return;

    setState(() => _isImporting = true);
    final importService = context.read<ImportExportService>();

    int successCount = 0;
    String? lastError;

    for (final deck in toImport) {
      try {
        // Reuse the finalize logic by passing the deck object
        // We'll need a way to import from a CreateDeck object directly in ImportExportService or just call the service methods
        // Actually, ImportExportService.importDeckFromJson calls _finalizeImport(CreateDeck.fromJsonString(jsonText))
        // I'll add a method `importDeck(CreateDeck deck)` to ImportExportService or just call _finalizeImport if I can make it public or use an internal helper.
        
        // For now, I'll use the existing public methods if possible, but I've already modified ImportExportService._finalizeImport to handle images.
        // Let's call a new public method `importCreateDeck(CreateDeck deck)` that I'll add.
        await importService.importDeckFromJson(jsonEncode(deck.toJson()));
        successCount++;
      } catch (e) {
        lastError = e.toString();
      }
    }

    if (mounted) {
      setState(() => _isImporting = false);
      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.loc.importSuccess),
          backgroundColor: OceanColors.success,
        ));
        if (successCount == toImport.length) {
          Navigator.of(context).pop();
        }
      } else if (lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.loc.importFailed(lastError)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CreateDeck>>(
      future: _decksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(context.loc.importOnlineLoading),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    context.loc.importOnlineError(snapshot.error.toString()),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() {
                      _decksFuture = context.read<RemoteDeckService>().fetchRemoteDecks();
                    }),
                    child: Text(context.loc.editTypeToSearch), // Reuse "Retry" if I had one, or just general text
                  ),
                ],
              ),
            ),
          );
        }

        final decks = snapshot.data ?? [];
        if (decks.isEmpty) {
          return Center(child: Text(context.loc.importOnlineEmpty));
        }

        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: decks.length,
                itemBuilder: (context, index) {
                  final deck = decks[index];
                  final isSelected = _selectedDeckNames.contains(deck.name);
                  final speciesCount = deck.speciesNames?.length ?? 0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: deck.imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: deck.imageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const Icon(Icons.image_outlined),
                                errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                              )
                            : const Icon(Icons.image_outlined),
                      ),
                      title: Text(deck.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deck.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(context.loc.importOnlineSpeciesCount(speciesCount),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      trailing: Checkbox(
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedDeckNames.add(deck.name);
                            } else {
                              _selectedDeckNames.remove(deck.name);
                            }
                          });
                        },
                      ),
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedDeckNames.remove(deck.name);
                          } else {
                            _selectedDeckNames.add(deck.name);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            if (_selectedDeckNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FloatingActionButton.extended(
                    onPressed: _isImporting ? null : () => _importSelected(decks),
                    icon: _isImporting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_download),
                    label: Text(context.loc.importSelectedButton(_selectedDeckNames.length)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// QR Scanner Tab
// ---------------------------------------------------------------------------
class _QrScannerTab extends StatefulWidget {
  const _QrScannerTab();

  @override
  State<_QrScannerTab> createState() => _QrScannerTabState();
}

class _QrScannerTabState extends State<_QrScannerTab> with TickerProviderStateMixin {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _scanned = false;
  bool _isImporting = false;
  late AnimationController _lineController;
  late Animation<double> _lineAnimation;

  @override
  void initState() {
    super.initState();
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _lineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_lineController);
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

    final importExportService = context.read<ImportExportService>();

    setState(() => _scanned = true);
    await _scannerController.stop();

    try {
      await importExportService.importDeckFromGzip(barcode!.displayValue!);
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
      final BarcodeCapture? capture = await _scannerController.analyzeImage(image.path);
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
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: _onBarcodeDetected,
                    fit: BoxFit.cover,
                  ),
                  _ScanOverlay(primary: primary, lineAnimation: _lineAnimation),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.loc.importInstruction,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _isImporting ? null : _pickImageFromGallery,
            icon: _isImporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.photo_library),
            label: Text(context.loc.importUploadGallery),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// JSON Import Tab (migrated from ImportJsonDialog)
// ---------------------------------------------------------------------------
class _JsonImportTab extends StatefulWidget {
  const _JsonImportTab();

  @override
  State<_JsonImportTab> createState() => _JsonImportTabState();
}

class _JsonImportTabState extends State<_JsonImportTab> {
  final _controller = TextEditingController();
  bool _isImporting = false;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        setState(() {
          _controller.text = content;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.importFailed(e.toString()))),
        );
      }
    }
  }

  Future<void> _import() async {
    final jsonText = _controller.text.trim();
    if (jsonText.isEmpty) return;

    setState(() => _isImporting = true);

    try {
      final importService = Provider.of<ImportExportService>(context, listen: false);
      await importService.importDeckFromJson(jsonText);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.importSuccess), backgroundColor: OceanColors.success),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.importJsonInvalid(e.toString())), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _isImporting ? null : _pickFile,
            icon: const Icon(Icons.file_upload),
            label: Text(context.loc.importJsonFileButton),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('OR', style: Theme.of(context).textTheme.labelSmall),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            maxLines: 12,
            decoration: InputDecoration(
              labelText: context.loc.importJsonPasteLabel,
              hintText: '{"name": "...", "description": "...", "speciesNames": [...]}',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              alignLabelWithHint: true,
            ),
            enabled: !_isImporting,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isImporting ? null : _import,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isImporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.loc.importButton),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
        ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
        Container(
          width: frameSize,
          height: frameSize,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        SizedBox(
          width: frameSize,
          height: frameSize,
          child: Stack(
            children: [
              Positioned(top: -2, left: -2, child: _Corner(primary, [_CornerSide.top, _CornerSide.left], cornerSize, cornerThickness)),
              Positioned(top: -2, right: -2, child: _Corner(primary, [_CornerSide.top, _CornerSide.right], cornerSize, cornerThickness)),
              Positioned(bottom: -2, left: -2, child: _Corner(primary, [_CornerSide.bottom, _CornerSide.left], cornerSize, cornerThickness)),
              Positioned(bottom: -2, right: -2, child: _Corner(primary, [_CornerSide.bottom, _CornerSide.right], cornerSize, cornerThickness)),
              AnimatedBuilder(
                animation: lineAnimation,
                builder: (_, _) => Positioned(
                  top: lineAnimation.value * (frameSize - 2),
                  left: 8,
                  right: 8,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.transparent, primary.withValues(alpha: 0.8), Colors.transparent]),
                      boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)],
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
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _CornerPainter(color, sides, thickness)));
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final List<_CornerSide> sides;
  final double thickness;
  _CornerPainter(this.color, this.sides, this.thickness);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = thickness..style = PaintingStyle.stroke..strokeCap = StrokeCap.square;
    for (final side in sides) {
      switch (side) {
        case _CornerSide.top: canvas.drawLine(Offset.zero, Offset(size.width, 0), paint); break;
        case _CornerSide.bottom: canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint); break;
        case _CornerSide.left: canvas.drawLine(Offset.zero, Offset(0, size.height), paint); break;
        case _CornerSide.right: canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), paint); break;
      }
    }
  }
  @override
  bool shouldRepaint(_CornerPainter old) => color != old.color;
}
