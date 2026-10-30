import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/decks/widgets/button_content.dart';
import 'package:discere/learning/decks/widgets/deck_action_presenter.dart';
import 'package:discere/learning/decks/widgets/learning_mode_icon_column.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Start-review button shown at the bottom of the card. Names in one line
/// what the session begins with — due reviews before new cards — and is
/// disabled when neither is available right now. The deck's overall progress
/// doesn't factor in here, only what the FSRS scheduler says is ready in the
/// stat the deck list loaded with [deck].
class ActionButton extends StatelessWidget {
  static const _presenter = DeckActionPresenter();

  final DeckViewModel deck;
  final VoidCallback onTap;

  const ActionButton({super.key, required this.deck, required this.onTap});

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

    final action = _presenter.actionFor(deck.stat);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: action.canStart ? onTap : null,
        child: ButtonContent(
          icon: Icons.play_arrow,
          label: _labelFor(action, context),
          modeIcons: modeIcons,
        ),
      ),
    );
  }

  String _labelFor(DeckAction action, BuildContext context) =>
      switch (action) {
        DeckActionReview(:final dueCount) =>
          context.loc.deckReviewCardsButton(dueCount),
        DeckActionLearnNew() => context.loc.deckLearnNewCardsButton,
        DeckActionNothingDue() => context.loc.deckNothingDueButton,
        DeckActionNoCards() => context.loc.commonNoFlashcardsAvailable,
      };
}
