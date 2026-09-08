import 'package:discere/learning/decks/view_deck.dart';
import 'package:discere/learning/decks/widgets/button_content.dart';
import 'package:discere/learning/decks/widgets/learning_mode_icon_column.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

class ActionButton extends StatelessWidget {
  final ViewDeck deck;
  final VoidCallback onTap;
  final Future<DeckStat> deckStatFuture;

  const ActionButton({
    super.key,
    required this.deck,
    required this.onTap,
    required this.deckStatFuture,
  });

  @override
  Widget build(BuildContext context) {
    final modeIcons =
        LearningModeIconColumn.hasNonDefault(
          learningMode: deck.learningMode,
          nameType: deck.nameType,
          reviewMode: deck.reviewMode,
        )
        ? LearningModeIconColumn(
            learningMode: deck.learningMode,
            nameType: deck.nameType,
            reviewMode: deck.reviewMode,
          )
        : null;

    return SizedBox(
      width: double.infinity,
      child: FutureBuilder<DeckStat>(
        future: deckStatFuture,
        builder: (context, snapshot) {
          final stat = snapshot.data;
          // Optimistically enabled until the stat is known, so the button
          // doesn't flash disabled→enabled while the future resolves.
          final hasCardsAvailable =
              stat == null || stat.dueCount > 0 || stat.uninitializedCount > 0;

          final parts = <String>[];
          if (stat != null) {
            if (stat.dueCount > 0) {
              parts.add(context.loc.deckReviewButton(stat.dueCount));
            }
            if (stat.uninitializedCount > 0) {
              parts.add(
                context.loc.deckNewCardsButton(stat.uninitializedCount),
              );
            }
          }
          final label = parts.isNotEmpty
              ? parts.join('\n')
              : context.loc.commonNoFlashcardsAvailable;
          return ElevatedButton(
            onPressed: hasCardsAvailable ? onTap : null,
            child: ButtonContent(
              icon: Icons.play_arrow,
              label: label,
              modeIcons: modeIcons,
            ),
          );
        },
      ),
    );
  }
}
