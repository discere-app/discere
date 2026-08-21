import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/learning/import/deck_import_flow.dart';
import 'package:discere/learning/import/import_json_tab.dart';
import 'package:discere/learning/import/import_online_decks_tab.dart';
import 'package:discere/learning/import/import_qr_scanner_tab.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ImportDeckPage extends StatelessWidget {
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
        body: SafeArea(
          child: TabBarView(
            children: [
              ImportOnlineDecksTab(
                loadDecks: () =>
                    context.read<RemoteDeckService>().fetchRemoteDecks(),
                onImportDecks: (decks) => _importDecks(context, decks),
              ),
              ImportQrScannerTab(
                onScanResult: (gzipText) => _importGzip(context, gzipText),
              ),
              ImportJsonTab(
                onImportJson: (jsonText) => _importJson(context, jsonText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importDecks(BuildContext context, List<CreateDeck> decks) {
    return runDeckImportFlow(context, (service) => service.importDecks(decks));
  }

  Future<void> _importJson(BuildContext context, String jsonText) {
    return _openCreateDeckPagePrefilled(
      context,
      (service) => service.parseJson(jsonText),
    );
  }

  Future<void> _importGzip(BuildContext context, String gzipText) {
    return _openCreateDeckPagePrefilled(
      context,
      (service) => service.parseGzip(gzipText),
    );
  }

  /// Scanning a QR code or importing a file/JSON payload no longer creates
  /// the deck straight away — it opens [CreateDeckPage] pre-filled with the
  /// parsed values so the user can review/edit them before confirming.
  Future<void> _openCreateDeckPagePrefilled(
    BuildContext context,
    Future<CreateDeck> Function(DeckImportService service) parse,
  ) async {
    final CreateDeck deck;
    try {
      deck = await parse(context.read<DeckImportService>());
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.loc.importFailed(context.loc.describeError(error)),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    if (!context.mounted) return;

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateDeckPage(
          initialName: deck.name,
          initialDescription: deck.description,
          initialSpeciesNames: deck.speciesNames,
          initialLanguage: deck.language,
          initialImageUrl: deck.imageUrl,
        ),
      ),
    );
    if (created == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
