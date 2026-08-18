import 'package:discere/learning/import/deck_import_flow.dart';
import 'package:discere/learning/import/import_online_decks_tab.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// First-run entry point shown instead of a blocking "Welcome" dialog: picking
/// decks (or skipping) is the only choice a brand-new user needs to make
/// before reaching the app, everything else (enrichment, permission consent)
/// stays exactly as [runDeckImportFlow] already handles it for the regular
/// [ImportDeckPage] flow reached later via the FAB.
class OnboardingDeckPickerPage extends StatelessWidget {
  const OnboardingDeckPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.welcomeTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.loc.welcomeSkipAction),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                context.loc.welcomeMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: ImportOnlineDecksTab(
                loadDecks: () =>
                    context.read<RemoteDeckService>().fetchRemoteDecks(),
                onImportDecks: (decks) => _importDecks(context, decks),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importDecks(BuildContext context, List<CreateDeck> decks) {
    return runDeckImportFlow(context, (service) => service.importDecks(decks));
  }
}
