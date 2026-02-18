
import '../learning/base_deck.dart';

class ViewDeck extends BaseDeck {
  double progress;

  ViewDeck(super.id, super.name, super.description, this.progress);
  ViewDeck.fromBase(BaseDeck baseDeck, this.progress)
      : super(
          baseDeck.id,
          baseDeck.name,
          baseDeck.description,
        );
}
