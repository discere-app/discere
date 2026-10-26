import 'package:discere/learning/import/deck_merge_flow.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One-line "replaced by …" hint on a deck card, shown when
/// [DeckUpdateService] knows of a catalog entry that supersedes this deck —
/// tapping it offers to merge the deck into that entry. The same status
/// line as [DeckUpdateHint], which a superseded deck never shows: it is not
/// updated any more, it is replaced.
class DeckReplacementHint extends StatelessWidget {
  final String deckId;

  const DeckReplacementHint({required this.deckId, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Selector<DeckUpdateService, CreateDeck?>(
      selector: (context, service) => service.replacementFor(deckId),
      builder: (context, replacement, child) {
        if (replacement == null) return const SizedBox.shrink();
        final color = theme.colorScheme.primary;

        return InkWell(
          key: Key('deck_card_replacement_button_$deckId'),
          onTap: () => runDeckMergeFlow(
            context,
            entry: replacement,
            catalog: context.read<DeckUpdateService>().catalog,
          ),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(Icons.merge_type, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.loc.deckReplacedByHint(replacement.name),
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
