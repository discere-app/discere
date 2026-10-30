import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';

/// A deck as the deck list shows it: the stored deck plus the progress counts
/// and learning settings the card displays.
///
/// Holds the stored deck instead of extending it, so the compiler refuses a
/// view model wherever a [BaseDeck] is expected — in particular on a save
/// path. A screen that opens, edits or shares the deck is handed [stored]
/// explicitly.
///
/// [stored] is the deck as it is, `sourceId` and `imageUrl` included. The list
/// shows neither, and no screen has reason to. Withholding them here would
/// not change that — composition makes the hop explicit, it does not hide a
/// field — and it would hand the screens that open, edit or share the deck an
/// incomplete one, which is the worse failure of the two: a deck missing a
/// field it has is indistinguishable from a deck whose field is empty, and
/// the difference matters on the way back to the database.
class DeckViewModel {
  final BaseDeck stored;

  /// Cards of the deck's learning mode a session has already taken up — the
  /// ones the card counts as learned.
  final int learnedCount;

  /// Cards the deck holds in its learning mode.
  final int totalCount;

  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;

  const DeckViewModel({
    required this.stored,
    required this.learnedCount,
    required this.totalCount,
    this.learningMode = LearningMode.species,
    this.nameType = NameType.commonName,
    this.reviewMode = ReviewMode.flip,
  });

  /// Share of [totalCount] learned, from 0 to 1. A deck without a card in its
  /// mode — empty, or none of its species has an answer there — has learned
  /// nothing, not everything.
  double get progress => totalCount == 0 ? 0 : learnedCount / totalCount;
}
