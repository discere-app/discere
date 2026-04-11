import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/ocean_theme/ocean_colors.dart';
import 'package:discere/learning/import/import_json_tab.dart';
import 'package:discere/learning/import/import_online_decks_tab.dart';
import 'package:discere/learning/import/import_qr_scanner_tab.dart';
import 'package:discere/learning/import/inat_download_dialog.dart';

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
    final result = await importAction(context.read<DeckImportService>());
    if (!context.mounted) return;

    if (result.hasSuccess) {
      await showINatDownloadFlow(context, result.importedDeckIds);
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.loc.importSuccess),
          backgroundColor: OceanColors.success,
        ),
      );

      if (result.allSucceeded) {
        Navigator.of(context).pop();
      }
      return;
    }

    if (result.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.loc.importFailed(result.lastError!)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}
