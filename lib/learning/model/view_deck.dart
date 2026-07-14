import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';

class ViewDeck extends BaseDeck {
  double progress;
  LearningMode learningMode;

  ViewDeck(
    super.id,
    super.name,
    super.description,
    this.progress, {
    super.coverImagePath,
    super.language,
    this.learningMode = LearningMode.species,
  });

  ViewDeck.fromBase(
    BaseDeck baseDeck,
    this.progress, {
    this.learningMode = LearningMode.species,
  }) : super(
         baseDeck.id,
         baseDeck.name,
         baseDeck.description,
         coverImagePath: baseDeck.coverImagePath,
         language: baseDeck.language,
       );
}
