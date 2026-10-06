import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/learning/import/deck_import_flow.dart';
import 'package:discere/learning/import/import_online_decks_tab.dart';
import 'package:discere/learning/import/import_qr_scanner_tab.dart';
import 'package:discere/learning/import/import_text_recognizer.dart';
import 'package:discere/learning/import/import_text_tab.dart';
import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/learning/model/create_deck.dart';
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
                key: const ValueKey('import_tab_online'),
                text: context.loc.importTabOnline,
                icon: const Icon(Icons.public),
              ),
              Tab(
                key: const ValueKey('import_tab_scanner'),
                text: context.loc.importTabScanner,
                icon: const Icon(Icons.qr_code_scanner),
              ),
              Tab(
                key: const ValueKey('import_tab_text'),
                text: context.loc.importTabText,
                icon: const Icon(Icons.text_snippet_outlined),
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
                onScanResult: (code) => _importText(context, code),
              ),
              ImportTextTab(
                onImportText: (text, sourceFileName) =>
                    _importText(context, text, sourceFileName: sourceFileName),
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

  /// Where a scanned QR code and a pasted or picked text both end up: unlike
  /// the online import, nothing is created straight away — [CreateDeckPage]
  /// opens pre-filled with what the text holds, for the user to review.
  ///
  /// A species list carries no deck name; the picked file's name stands in
  /// for it, and pasted text leaves the name for the user to fill in.
  Future<void> _importText(
    BuildContext context,
    String text, {
    String? sourceFileName,
  }) async {
    final recognized = await context.read<ImportTextRecognizer>().recognize(
      text,
    );
    if (!context.mounted) return;

    final prefill = switch (recognized) {
      RecognizedDeck(:final deck) => deck,
      RecognizedSpeciesList(:final speciesNames) => CreateDeck(
        name: sourceFileName ?? '',
        description: '',
        speciesNames: speciesNames,
      ),
      UnrecognizedImport() => null,
    };
    if (prefill == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.loc.importFormatUnrecognized),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateDeckPage(
          initialName: prefill.name,
          initialDescription: prefill.description,
          initialSpeciesNames: prefill.speciesNames,
          initialLanguage: prefill.language,
          initialImageUrl: prefill.imageUrl,
        ),
      ),
    );
    if (created == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
