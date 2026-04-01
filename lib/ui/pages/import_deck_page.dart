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

import 'package:discere/model/common/app_exception.dart';
import '../../service/common/import_export_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/ocean_theme/ocean_colors.dart';
import '../components/inat_download_dialog.dart';

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
              Tab(
                key: const ValueKey('import-tab-online'),
                text: context.loc.importTabOnline,
                icon: const Icon(Icons.public),
              ),
              Tab(
                key: const ValueKey('import-tab-scanner'),
                text: context.loc.importTabScanner,
                icon: const Icon(Icons.qr_code_scanner),
              ),
              Tab(
                key: const ValueKey('import-tab-json'),
                text: context.loc.importTabJson,
                icon: const Icon(Icons.code),
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_OnlineDecksTab(), _QrScannerTab(), _JsonImportTab()],
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
    final toImport = allDecks
        .where((d) => _selectedDeckNames.contains(d.name))
        .toList();
    if (toImport.isEmpty) return;

    setState(() => _isImporting = true);
    final importService = context.read<ImportExportService>();

    int successCount = 0;
    String? lastError;
    final List<String> importedDeckIds = [];

    for (final deck in toImport) {
      try {
        final deckId = await importService.importDeckFromJson(jsonEncode(deck.toJson()));
        importedDeckIds.add(deckId);
        successCount++;
      } catch (e) {
        lastError = e.toString();
      }
    }

    if (mounted) {
      setState(() => _isImporting = false);
      if (successCount > 0) {
        // Ask user to download photos for all imported decks at once.
        if (mounted) {
          await showINatDownloadFlow(context, importedDeckIds);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.loc.importSuccess),
              backgroundColor: OceanColors.success,
            ),
          );
          if (successCount == toImport.length) {
            Navigator.of(context).pop();
          }
        }
      } else if (lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.importFailed(lastError)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CreateDeck>>(
      future: _decksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          final errorMessage = error is AppException ? error.message : context.loc.importOnlineError(error.toString());

          return Center(
            child: Padding(
              padding: AppSpacing.emptyStatePaddingAll,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_off,
                    size: AppSpacing.emptyStateIconSize,
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
                  ),
                  AppSpacing.heightS24,
                  Text(
                    context.loc.error,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                  AppSpacing.heightS12,
                  Text(
                    errorMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  AppSpacing.heightS32,
                  SizedBox(
                    width: 200,
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() {
                        _decksFuture = context
                            .read<RemoteDeckService>()
                            .fetchRemoteDecks();
                      }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final decks = snapshot.data ?? [];
        if (decks.isEmpty) {
          return Padding(
            padding: AppSpacing.emptyStatePaddingAll,
            child: Center(
              child: Text(
                context.loc.importOnlineEmpty,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return SafeArea(
          bottom: true,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: decks.length,
                  itemBuilder: (context, index) {
                    final deck = decks[index];
                    final isSelected = _selectedDeckNames.contains(deck.name);
                    return CheckboxListTile(
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
                      title: Text(
                        deck.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (deck.description.isNotEmpty) Text(deck.description),
                          Text(
                            context.loc.importOnlineSpeciesCount(
                              deck.speciesNames?.length ?? 0,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      secondary: deck.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CachedNetworkImage(
                                imageUrl: deck.imageUrl!,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    Container(color: Colors.grey[300]),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.broken_image),
                              ),
                            )
                          : const Icon(Icons.image_not_supported),
                    );
                  },
                ),
              ),
              Padding(
                padding: AppSpacing.screenPaddingAll,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isImporting || _selectedDeckNames.isEmpty
                        ? null
                        : () => _importSelected(decks),
                    icon: _isImporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(context.loc.importDeckTitle),
                  ),
                ),
              ),
            ],
          ),
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

class _QrScannerTabState extends State<_QrScannerTab> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  Future<void> _handleScan(String code) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final importService = context.read<ImportExportService>();
      final deckId = await importService.importDeckFromJson(code);
      if (mounted) {
        await showINatDownloadFlow(context, deckId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.importSuccess),
            backgroundColor: OceanColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.importFailed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _importFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final result = await _scannerController.analyzeImage(image.path);
    if (result != null && result.barcodes.isNotEmpty) {
      final code = result.barcodes.first.rawValue;
      if (code != null) {
        _handleScan(code);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.importNoQrCode),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
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
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final String? code = barcode.rawValue;
                      if (code != null) {
                        _handleScan(code);
                      }
                    }
                  },
                ),
                // Overlay helpers
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
              onPressed: _importFromGallery,
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

// ---------------------------------------------------------------------------
// JSON Import Tab
// ---------------------------------------------------------------------------
class _JsonImportTab extends StatefulWidget {
  const _JsonImportTab();

  @override
  State<_JsonImportTab> createState() => _JsonImportTabState();
}

class _JsonImportTabState extends State<_JsonImportTab> {
  final TextEditingController _jsonController = TextEditingController();
  bool _isImporting = false;

  Future<void> _importJson() async {
    final text = _jsonController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      final importService = context.read<ImportExportService>();
      final deckId = await importService.importDeckFromJson(text);
      if (mounted) {
        await showINatDownloadFlow(context, deckId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.importSuccess),
            backgroundColor: OceanColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.importFailed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      _jsonController.text = content;
    }
  }

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: SingleChildScrollView(
        padding: AppSpacing.screenPaddingAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text(
            context.loc.importJsonTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          AppSpacing.heightS16,
          TextField(
            controller: _jsonController,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: context.loc.importJsonPasteLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.file_open),
                onPressed: _importFile,
              ),
            ),
          ),
          AppSpacing.heightS24,
          ElevatedButton(
            key: const ValueKey('import-json-button'),
            onPressed: _isImporting ? null : _importJson,
            child: _isImporting
                ? const CircularProgressIndicator()
                : Text(context.loc.importJsonButton),
          ),
        ],
      ),
    ),
  );
}
}
