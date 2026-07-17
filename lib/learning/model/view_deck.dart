import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';

class ViewDeck extends BaseDeck {
  double progress;
  LearningMode learningMode;
  NameType nameType;

  ViewDeck(
    super.id,
    super.name,
    super.description,
    this.progress, {
    super.coverImagePath,
    super.language,
    super.updatedAt,
    this.learningMode = LearningMode.species,
    this.nameType = NameType.commonName,
  });

  // sourceId is intentionally not carried over: it is internal catalog
  // bookkeeping (used during import), not something the UI needs. Keeping it
  // off ViewDeck avoids tempting a screen into displaying it.
  ViewDeck.fromBase(
    BaseDeck baseDeck,
    this.progress, {
    this.learningMode = LearningMode.species,
    this.nameType = NameType.commonName,
  }) : super(
         baseDeck.id,
         baseDeck.name,
         baseDeck.description,
         coverImagePath: baseDeck.coverImagePath,
         language: baseDeck.language,
         updatedAt: baseDeck.updatedAt,
       );
}
