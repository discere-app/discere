import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';

/// The deck's learning progress as a bar with the learned/total count next to
/// it — the one place the card states it. Both read the stat the deck list
/// loaded with [deck], so the count never lags behind the bar and agrees with
/// the start button below.
///
/// Announced as one sentence ("30 of 150 learned"): the bar's own percentage
/// and the bare "30/150" would only repeat it in a less readable form. A deck
/// without a card in its mode shows the empty bar but no "0/0", and announces
/// nothing — the start button below already says there are no cards.
class DeckProgressRow extends StatelessWidget {
  final DeckViewModel deck;

  const DeckProgressRow({super.key, required this.deck});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasCards = deck.totalCount > 0;

    return Semantics(
      label: hasCards
          ? context.loc.deckProgressSemantics(
              deck.learnedCount,
              deck.totalCount,
            )
          : null,
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: deck.progress,
                minHeight: 6,
                backgroundColor: colorScheme.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  deck.progress >= 1.0
                      ? OceanColors.success
                      : colorScheme.primary,
                ),
              ),
            ),
          ),
          if (hasCards) ...[
            AppSpacing.widthS12,
            Text(
              context.loc.deckProgressCount(deck.learnedCount, deck.totalCount),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
