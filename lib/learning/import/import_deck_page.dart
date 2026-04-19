import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:discere/learning/import/import_json_tab.dart';
import 'package:discere/learning/import/import_online_decks_tab.dart';
import 'package:discere/learning/import/import_qr_scanner_tab.dart';
import 'package:discere/learning/import/import_result_dialog.dart';

class ImportDeckPage extends StatelessWidget {
  static final _log = Logger.forType(ImportDeckPage);
  const ImportDeckPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            context.loc.importDeckTitle,
            key: const Key('import_deck_page_title'),
          ),
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
        body: TabBarView(
          children: [
            ImportOnlineDecksTab(
              loadDecks: () =>
                  context.read<RemoteDeckService>().fetchRemoteDecks(),
              onImportDecks: (decks) => _importDecks(context, decks),
            ),
            ImportQrScannerTab(
              onImportJson: (jsonText) => _importJson(context, jsonText),
            ),
            ImportJsonTab(
              onImportJson: (jsonText) => _importJson(context, jsonText),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importDecks(BuildContext context, List<CreateDeck> decks) {
    return _runImport(context, (service) => service.importDecks(decks));
  }

  Future<void> _importJson(BuildContext context, String jsonText) {
    return _runImport(context, (service) => service.importJson(jsonText));
  }

  Future<void> _runImport(
    BuildContext context,
    Future<DeckImportResult> Function(DeckImportService service) importAction,
  ) async {
    _log.debug('Import tapped');
    final result = await importAction(context.read<DeckImportService>());
    if (!context.mounted) return;

    // Start image downloads and background name resolution immediately,
    // independent of the dialog. This runs completely in the background.
    if (result.hasSuccess) {
      context.read<INatEnrichmentQueueService>().scheduleDeckEnrichment(
        result.importedDeckIds,
        includeINatPhotos: false,
        includeCommonNames: false,
        coverImageUrlsByDeckId: result.imageUrlByDeckId,
        unresolvedNamesByDeckId: result.unresolvedNamesByDeckId,
      );
    }

    // Show result dialog while images are already downloading
    _log.debug(
      'Show import result dialog success=${result.successCount}/${result.attemptedCount} '
      'unresolved=${result.unresolvedNames.length}',
    );
    final includeINat = await showImportResultDialog(context, result);
    if (!context.mounted) return;

    if (result.hasSuccess) {
      if (includeINat) {
        // Add iNat photos and multilingual names to the running enrichment
        context.read<INatEnrichmentQueueService>().scheduleDeckEnrichment(
          result.importedDeckIds,
          includeINatPhotos: true,
          includeCommonNames: true,
          coverImageUrlsByDeckId: result.imageUrlByDeckId,
        );
      }
      Navigator.of(context).pop();
    }
  }
}
