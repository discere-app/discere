import '../learning/base_deck.dart';

class CreateDeck extends BaseDeck {
  final Set<String>? speciesNames;
  Set<String>? speciesIds;

  CreateDeck({
    required String name,
    required String description,
    this.speciesNames,
    this.speciesIds,
  }) : super(null, name, description);
}
