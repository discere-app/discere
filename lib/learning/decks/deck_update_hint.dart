import 'package:discere/learning/decks/edit/deck_update_dialog.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One-line "update available" hint on a deck card, shown when
/// [DeckUpdateService] knows of a newer online catalog entry for this deck —
/// tapping it opens the species-diff dialog. Mirrors [DeckEnrichmentHint]'s
/// icon+text row so it reads as a peer status line rather than just another
/// icon in the favorite/edit/share row, which made it easy to miss. Renders
/// nothing when there's no known update, mostly because the check only runs
/// once per app start (see `bootstrap_app.dart`'s `startDeferred`), so most
/// decks simply never have an entry.
class DeckUpdateHint extends StatelessWidget {
  final String deckId;

  const DeckUpdateHint({required this.deckId, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Selector<DeckUpdateService, CreateDeck?>(
      selector: (context, service) => service.updateFor(deckId),
      builder: (context, remote, child) {
        if (remote == null) return const SizedBox.shrink();
        final color = theme.colorScheme.primary;

        return InkWell(
          key: Key('deck_card_update_button_$deckId'),
          onTap: () => showDeckUpdateDialog(context, deckId, remote),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(Icons.system_update_alt, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.loc.deckUpdateAvailableTooltip,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
