import '../learning/base_deck.dart';

class ViewDeck extends BaseDeck {
  double progress;

  ViewDeck(super.id, super.name, super.description, this.progress,
      {super.coverImagePath});
  ViewDeck.fromBase(BaseDeck baseDeck, this.progress)
      : super(
          baseDeck.id,
          baseDeck.name,
          baseDeck.description,
          coverImagePath: baseDeck.coverImagePath,
        );
}
