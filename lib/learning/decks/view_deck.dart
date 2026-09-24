import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';

/// A deck as the deck list shows it: the stored deck plus the progress and
/// learning settings the card displays.
class ViewDeck extends BaseDeck {
  final double progress;
  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;

  ViewDeck({
    super.id,
    required super.name,
    required super.description,
    required this.progress,
    super.coverImagePath,
    super.language,
    super.updatedAt,
    this.learningMode = LearningMode.species,
    this.nameType = NameType.commonName,
    this.reviewMode = ReviewMode.flip,
  });

  // sourceId is intentionally not carried over: it is internal catalog
  // bookkeeping (used during import), not something the UI needs. Keeping it
  // off ViewDeck avoids tempting a screen into displaying it.
  ViewDeck.fromBase(
    BaseDeck baseDeck,
    this.progress, {
    this.learningMode = LearningMode.species,
    this.nameType = NameType.commonName,
    this.reviewMode = ReviewMode.flip,
  }) : super(
         id: baseDeck.id,
         name: baseDeck.name,
         description: baseDeck.description,
         coverImagePath: baseDeck.coverImagePath,
         language: baseDeck.language,
         updatedAt: baseDeck.updatedAt,
       );
}
