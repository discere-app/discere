import 'package:discere/learning/decks/edit/deck_update_dialog.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Small icon button shown on a deck card when [DeckUpdateService] knows of a
/// newer online catalog entry for this deck — tapping it opens the
/// species-diff dialog. Renders nothing when there's no known update, mostly
/// because the check only runs once per app start (see
/// `bootstrap_app.dart`'s `startDeferred`), so most decks simply never have
/// an entry.
class DeckUpdateHint extends StatelessWidget {
  final String deckId;

  const DeckUpdateHint({required this.deckId, super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<DeckUpdateService, CreateDeck?>(
      selector: (context, service) => service.updateFor(deckId),
      builder: (context, remote, child) {
        if (remote == null) return const SizedBox.shrink();
        return IconButton(
          key: Key('deck_card_update_button_$deckId'),
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.system_update_alt,
            color: Theme.of(context).colorScheme.primary,
          ),
          tooltip: context.loc.deckUpdateAvailableTooltip,
          onPressed: () => showDeckUpdateDialog(context, deckId, remote),
        );
      },
    );
  }
}
