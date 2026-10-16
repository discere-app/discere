import 'package:discere/catalog/repository/taxon_assignment_repository.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/repository/flashcard_stat_mode_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';

/// Which of a deck's species are cards in a learning mode.
///
/// A species without an answer in the mode ([LearningMode.hasNoAnswerFor]) —
/// no genus in genus mode, no family or a placeholder family in family mode
/// — is no card there: never initialized, never counted, never due. Its rows
/// stay, because rows are what makes it a member of the deck, and a species
/// with rows only in this mode would otherwise drop out of it entirely.
///
/// Which species these are is the reference database's answer, and a new
/// reference database can change it. So it is worked out again for every
/// question rather than stored: from the deck's species in the user
/// database and the ranks the reference database leaves unassigned for
/// them, nothing more.
class AnswerableCardsService {
  final FlashcardStatRepository _stats;
  final FlashcardStatModeRepository _modeStats;
  final TaxonAssignmentRepository _assignments;

  const AnswerableCardsService(this._stats, this._modeStats, this._assignments);

  /// The species of [deckId] without an answer in [learningMode]. None in
  /// species mode, which asks nothing a species could lack, so that mode
  /// costs no query.
  Future<Set<String>> speciesWithoutAnswer(
    String deckId,
    LearningMode learningMode,
  ) async {
    if (learningMode.askedRank == null) return const {};
    return _withoutAnswerAmong(
      await _stats.getSpeciesIdsByDeckId(deckId),
      learningMode,
    );
  }

  /// [FlashcardStatRepository.getDeckStat], counting only the species with
  /// an answer in [learningMode].
  ///
  /// Counted from the mode's rows themselves once some species are left
  /// out: a row of such a species may still carry a review date from before
  /// it lost its answer, until the next session resets it, and must not
  /// count as initialized or due meanwhile.
  Future<DeckStat> deckStat(
    String deckId, {
    required LearningMode learningMode,
    required NameType nameType,
  }) async {
    Future<DeckStat> allSpecies() => _stats.getDeckStat(
      deckId,
      learningMode: learningMode,
      nameType: nameType,
    );
    if (learningMode.askedRank == null) return allSpecies();

    final deckSpecies = await _stats.getSpeciesIdsByDeckId(deckId);
    final withoutAnswer = await _withoutAnswerAmong(deckSpecies, learningMode);
    if (withoutAnswer.isEmpty) return allSpecies();

    final cards = deckSpecies.difference(withoutAnswer);
    final reviewDates = await _modeStats.getNextReviewDates(
      deckId,
      learningMode,
      nameType,
    );
    final now = DateTime.now();
    var initialized = 0;
    var due = 0;
    for (final speciesId in cards) {
      final nextReview = reviewDates[speciesId];
      if (nextReview == null) continue;
      initialized++;
      if (!nextReview.isAfter(now)) due++;
    }
    return DeckStat(cards.length, cards.length - initialized, due);
  }

  /// Resets every row of [deckId] for [learningMode] whose species has no
  /// answer in it — a review date from before it lost its answer, or from
  /// when it was asked as "Not assigned" — and returns those species. Rows
  /// of other modes are not touched: the species may well have an answer
  /// there.
  Future<Set<String>> resetCardsWithoutAnswer(
    String deckId,
    LearningMode learningMode,
  ) async {
    final withoutAnswer = await speciesWithoutAnswer(deckId, learningMode);
    await _modeStats.resetStats(deckId, learningMode, withoutAnswer);
    return withoutAnswer;
  }

  Future<Set<String>> _withoutAnswerAmong(
    Set<String> speciesIds,
    LearningMode learningMode,
  ) async {
    final unassigned = await _assignments.unassignedRanksOf(speciesIds);
    return {
      for (final MapEntry(key: speciesId, value: ranks) in unassigned.entries)
        if (learningMode.hasNoAnswerGiven(ranks)) speciesId,
    };
  }
}
