import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/decks/widgets/button_content.dart';
import 'package:discere/learning/decks/widgets/deck_action_presenter.dart';
import 'package:discere/learning/decks/widgets/learning_mode_icon_column.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Start-review button shown at the bottom of the card. Names in one line
/// what the session begins with — due reviews before new cards — and is
/// disabled when neither is available right now. The deck's overall progress
/// doesn't factor in here, only what the FSRS scheduler says is ready.
class ActionButton extends StatelessWidget {
  static const _presenter = DeckActionPresenter();

  final DeckViewModel deck;
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
          final action = _presenter.actionFor(snapshot.data);
          return ElevatedButton(
            onPressed: action.canStart ? onTap : null,
            child: ButtonContent(
              icon: Icons.play_arrow,
              label: _labelFor(action, context),
              modeIcons: modeIcons,
            ),
          );
        },
      ),
    );
  }

  // Pending — loading, or a load that failed — shows no label rather than a
  // guess: any text would claim a count or a state the stat has not
  // confirmed. The play icon holds the button's height, so the one-line label
  // arriving does not shift the card.
  String _labelFor(DeckAction action, BuildContext context) =>
      switch (action) {
        DeckActionPending() => '',
        DeckActionReview(:final dueCount) =>
          context.loc.deckReviewCardsButton(dueCount),
        DeckActionLearnNew() => context.loc.deckLearnNewCardsButton,
        DeckActionNothingDue() => context.loc.deckNothingDueButton,
        DeckActionNoCards() => context.loc.commonNoFlashcardsAvailable,
      };
}
